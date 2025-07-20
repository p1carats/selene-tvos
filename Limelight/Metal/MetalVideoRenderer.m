#import "MetalVideoRenderer.h"
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>
#import "ImGuiPlots.h"

#include <Limelight.h>

#define MAX_VIDEO_PLANES 3

struct CscParams {
    vector_float3 matrix[3];
    vector_float3 offsets;
};

struct ParamBuffer {
    struct CscParams cscParams;
};

static const struct CscParams k_CscParams_Bt601Lim = {
    // CSC Matrix
    {{1.1644f, 0.0f, 1.5960f}, {1.1644f, -0.3917f, -0.8129f}, {1.1644f, 2.0172f, 0.0f}},

    // Offsets
    {16.0f / 255.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
static const struct CscParams k_CscParams_Bt601Full = {
    {
        {1.0f, 0.0f, 1.4020f},
        {1.0f, -0.3441f, -0.7141f},
        {1.0f, 1.7720f, 0.0f},
    },
    {0.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
static const struct CscParams k_CscParams_Bt709Lim = {
    {
        {1.1644f, 0.0f, 1.7927f},
        {1.1644f, -0.2132f, -0.5329f},
        {1.1644f, 2.1124f, 0.0f},
    },
    {16.0f / 255.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
static const struct CscParams k_CscParams_Bt709Full = {
    {
        {1.0f, 0.0f, 1.5748f},
        {1.0f, -0.1873f, -0.4681f},
        {1.0f, 1.8556f, 0.0f},
    },
    {0.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
static const struct CscParams k_CscParams_Bt2020Lim_10bit = {
    {
        {1.1644f, 0.0f, 1.6781f},
        {1.1644f, -0.1874f, -0.6505f},
        {1.1644f, 2.1418f, 0.0f},
    },
    {64.0f / 1023.0f, 512.0f / 1023.0f, 512.0f / 1023.0f},
};
static const struct CscParams k_CscParams_Bt2020Full_10bit = {
    {
        {1.0f, 0.0f, 1.4746f},
        {1.0f, -0.1646f, -0.5714f},
        {1.0f, 1.8814f, 0.0f},
    },
    {0.0f, 512.0f / 1023.0f, 512.0f / 1023.0f},
};

struct Vertex {
    vector_float4 position;
    vector_float2 texCoord;
};

static const NSUInteger MaxFramesInFlight = 3;

@implementation MetalVideoRenderer {
    dispatch_queue_t _sq;
    id<MTLDevice> _device;
    float _framerate;
    id<ConnectionCallbacks> _callbacks;
    id<MTLCommandQueue> _commandQueue;
    id<MTLLibrary> _shaderLibrary;
    id<MTLRenderPipelineState> _videoPipelineState[MAX_VIDEO_PLANES];
    MTLRenderPassDescriptor *_renderPassDescriptor;
    CVMetalTextureCacheRef _textureCache;
    CVMetalTextureRef _cvMetalTextures[MAX_VIDEO_PLANES];

    CGFloat _currentEDRHeadroom;
    int _lastColorSpace;
    BOOL _lastFullRange;
    size_t _lastFrameWidth;
    size_t _lastFrameHeight;
    size_t _lastDrawableWidth;
    size_t _lastDrawableHeight;
    id<MTLBuffer> _CscParamsBuffer;
    id<MTLBuffer> _VideoVertexBuffer;

    // https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work?language=objc
    dispatch_semaphore_t _inFlightSemaphore;
}

- (instancetype)initWithMetalDevice:(id<MTLDevice>)device drawablePixelFormat:(MTLPixelFormat)drawablePixelFormat framerate:(float)framerate {
    self = [super init];
    if (self) {
        _sq = dispatch_queue_create("com.moonlight.MetalVideoRenderer",
                                    dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
        _averageGPUTime = (1.0f / framerate) / 2;
        _device = device;
        _colorPixelFormat = MTLPixelFormatBGR10A2Unorm;
        _framerate = framerate;
        _commandQueue = [_device newCommandQueue];
        _currentEDRHeadroom = 1.0f;
        _lastColorSpace = -1;
        _lastFullRange = NO;
        _lastPresented = 0.0f;
        _inFlightSemaphore = dispatch_semaphore_create(MaxFramesInFlight);
        _isStopping = NO;

        CFStringRef keys[1] = {kCVMetalTextureUsage};
        NSUInteger values[1] = {MTLTextureUsageShaderRead};
        CFDictionaryRef cacheAttributes = CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, (const void **)values, 1, NULL, NULL);
        CVMetalTextureCacheCreate(kCFAllocatorDefault, cacheAttributes, _device, NULL, &_textureCache);
        CFRelease(cacheAttributes);

        _renderPassDescriptor = [MTLRenderPassDescriptor new];
        _renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        _renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
        _renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    }
    return self;
}

- (void)dealloc {
    if (_CscParamsBuffer) {
        _CscParamsBuffer = nil;
    }
    if (_VideoVertexBuffer) {
        _VideoVertexBuffer = nil;
    }
    for (int i = 0; i < MAX_VIDEO_PLANES; i++) {
        if (_videoPipelineState[i]) {
            _videoPipelineState[i] = nil;
        }
    }
    if (_renderPassDescriptor) {
        _renderPassDescriptor = nil;
    }
}

- (int)getFrameColorspaceAndRange:(Frame *)frame isFullRange:(BOOL *)isFullRange {
    CFDictionaryRef ext = [frame getFormatDescExtensions];

    // FQLog(LOG_I, @"%@", ext);

    // Full Range boolean
    CFBooleanRef fullRangeRef = CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_FullRangeVideo);
    *isFullRange = NO;
    if (fullRangeRef && CFGetTypeID(fullRangeRef) == CFBooleanGetTypeID()) {
        *isFullRange = CFBooleanGetValue(fullRangeRef);
    }

    // Colorspace
    CFStringRef frame_color = CFDictionaryGetValue(ext, kCVImageBufferColorPrimariesKey);
    if (CFEqual(frame_color, kCVImageBufferColorPrimaries_ITU_R_709_2)) {
        return COLORSPACE_REC_709;
    } else if (CFEqual(frame_color, kCVImageBufferColorPrimaries_ITU_R_2020)) {
        return COLORSPACE_REC_2020;
    }
    return COLORSPACE_REC_601;
}

- (BOOL)updateColorSpaceForFrame:(Frame *)frame toLayer:(CAMetalLayer *)layer layerDidChange:(BOOL *)layerDidChange {
    BOOL fullRange = NO;
    int colorspace = [self getFrameColorspaceAndRange:frame isFullRange:&fullRange];
    if (colorspace != _lastColorSpace || fullRange != _lastFullRange) {
        CGColorSpaceRef newColorSpace = nil;
        MTLPixelFormat newPixelFormat = layer.pixelFormat;
        BOOL isHDR = NO;
        struct ParamBuffer paramBuffer;

        switch (colorspace) {
            case COLORSPACE_REC_709:
                newColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
                newPixelFormat = MTLPixelFormatBGRA8Unorm;
                paramBuffer.cscParams = (fullRange ? k_CscParams_Bt709Full : k_CscParams_Bt709Lim);
                break;
            case COLORSPACE_REC_2020: {
                CFDictionaryRef ext = [frame getFormatDescExtensions];
                CFStringRef frame_trc = CFDictionaryGetValue(ext, kCVImageBufferTransferFunctionKey);
                if (CFEqual(frame_trc, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)) {
                    isHDR = YES;
                    newColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ);
                } else {
                    // SDR 2020, I'm not sure it's possible to stream this though
                    newColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2020);
                }
                newPixelFormat = MTLPixelFormatBGR10A2Unorm;
                paramBuffer.cscParams = (fullRange ? k_CscParams_Bt2020Full_10bit : k_CscParams_Bt2020Lim_10bit);
                break;
            }
            case COLORSPACE_REC_601:
                newColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                newPixelFormat = MTLPixelFormatBGRA8Unorm;
                paramBuffer.cscParams = (fullRange ? k_CscParams_Bt601Full : k_CscParams_Bt601Lim);
        }

        // The CAMetalLayer retains the CGColorSpace
        if (newColorSpace || newPixelFormat != layer.pixelFormat) {
            *layerDidChange = YES;
            if (newColorSpace) {
                Log(LOG_I,
                    @"Frame colorspace %@ - changing MetalLayer's colorspace to %@",
                    colorspace == COLORSPACE_REC_709        ? @"REC_709"
                        : colorspace == COLORSPACE_REC_2020 ? @"REC_2020"
                        : colorspace == COLORSPACE_REC_601  ? @"REC_601 (sRGB)"
                                                            : [NSString stringWithFormat:@"Unknown: %d", colorspace],
                    newColorSpace);
            }
            if (newPixelFormat != layer.pixelFormat) {
                Log(LOG_I,
                    @"Frame pixel format %@ - changing MetalLayer's pixel format to %@",
                    layer.pixelFormat == MTLPixelFormatBGRA8Unorm         ? @"MTLPixelFormatBGRA8Unorm"
                        : layer.pixelFormat == MTLPixelFormatBGR10A2Unorm ? @"MTLPixelFormatBGR10A2Unorm"
                                                                          : [NSString stringWithFormat:@"Unknown: %lu", layer.pixelFormat],
                    newPixelFormat == MTLPixelFormatBGRA8Unorm         ? @"MTLPixelFormatBGRA8Unorm"
                        : newPixelFormat == MTLPixelFormatBGR10A2Unorm ? @"MTLPixelFormatBGR10A2Unorm"
                                                                       : [NSString stringWithFormat:@"Unknown: %lu", (unsigned long)layer.pixelFormat]);
            }
            
            // These can only be changed on the main thread
            dispatch_sync(dispatch_get_main_queue(), ^{
                layer.colorspace = newColorSpace;
                layer.pixelFormat = newPixelFormat;
            });
            CGColorSpaceRelease(newColorSpace);
        }

        // Create the new colorspace parameter buffer for our fragment shader
        MTLResourceOptions bufferOptions = MTLResourceStorageModeShared;
        _CscParamsBuffer = [_device newBufferWithBytes:(void *)&paramBuffer length:sizeof(paramBuffer) options:bufferOptions];
        if (!_CscParamsBuffer) {
            Log(LOG_E, @"Failed to create CSC parameters buffer");
            return NO;
        }

        _lastColorSpace = colorspace;
        _lastFullRange = fullRange;
    }

    return YES;
}

- (void)scaleSource:(CGRect *)src toDest:(CGRect *)dst {
    int dstH = ceilf((float)dst->size.width * src->size.height / src->size.width);
    int dstW = ceilf((float)dst->size.height * src->size.width / src->size.height);

    if (dstH > dst->size.height) {
        dst->origin.x += (dst->size.width - dstW) / 2;
        dst->size.width = dstW;
    } else {
        dst->origin.y += (dst->size.height - dstH) / 2;
        dst->size.height = dstH;
    }
}

- (void)screenSpace:(CGRect *)src toNormalizedDeviceCoords:(CGRect *)dst withDrawableWidth:(int)viewportWidth drawableHeight:(int)viewportHeight {
    dst->origin.x = ((float)src->origin.x / (viewportWidth / 2.0f)) - 1.0f;
    dst->origin.y = ((float)src->origin.y / (viewportHeight / 2.0f)) - 1.0f;
    dst->size.width = (float)src->size.width / (viewportWidth / 2.0f);
    dst->size.height = (float)src->size.height / (viewportHeight / 2.0f);
}

- (BOOL)updateVideoRegionSizeForFrame:(Frame *)frame toLayer:(CAMetalLayer *)layer {
    int drawableWidth = layer.drawableSize.width;
    int drawableHeight = layer.drawableSize.height;

    // Check if anything has changed since the last vertex buffer upload
    if (_VideoVertexBuffer && [frame width] == _lastFrameWidth && [frame height] == _lastFrameHeight && drawableWidth == _lastDrawableWidth &&
        drawableHeight == _lastDrawableHeight) {
        // Nothing to do
        return YES;
    }

    // Determine the correct scaled size for the video region
    CGRect src = CGRectMake(0.0, 0.0, [frame width], [frame height]);
    CGRect dst = CGRectMake(0.0, 0.0, drawableWidth, drawableHeight);
    [self scaleSource:&src toDest:&dst];

    // Convert screen space to normalized device coordinates
    CGRect renderRect;
    [self screenSpace:&dst toNormalizedDeviceCoords:&renderRect withDrawableWidth:drawableWidth drawableHeight:drawableHeight];

    struct Vertex verts[] = {
        {{renderRect.origin.x, renderRect.origin.y, 0.0f, 1.0f}, {0.0f, 1.0f}},
        {{renderRect.origin.x, renderRect.origin.y + renderRect.size.height, 0.0f, 1.0f}, {0.0f, 0}},
        {{renderRect.origin.x + renderRect.size.width, renderRect.origin.y, 0.0f, 1.0f}, {1.0f, 1.0f}},
        {{renderRect.origin.x + renderRect.size.width, renderRect.origin.y + renderRect.size.height, 0.0f, 1.0f}, {1.0f, 0}},
    };

    MTLResourceOptions bufferOptions = MTLResourceStorageModeShared;
    _VideoVertexBuffer = [_device newBufferWithBytes:verts length:sizeof(verts) options:bufferOptions];
    if (!_VideoVertexBuffer) {
        Log(LOG_E, @"Failed to create video vertex buffer");
        return NO;
    }

    _lastFrameWidth = [frame width];
    _lastFrameHeight = [frame height];
    _lastDrawableWidth = drawableWidth;
    _lastDrawableHeight = drawableHeight;

    return YES;
}

- (void)renderFrame:(Frame *)frame toLayer:(CAMetalLayer *)layer {
    @autoreleasepool {
        if (self.isStopping) {
            Log(LOG_I, @"XXX Metal renderThread is stopping. returning from renderFrame");
            return;
        }

        // Handle changes to the frame's colorspace from last time we rendered
        BOOL layerDidChange = NO;
        if (![self updateColorSpaceForFrame:frame toLayer:layer layerDidChange:&layerDidChange]) {
            return;
        }

        // Handle changes to the video size or drawable size
        if (![self updateVideoRegionSizeForFrame:frame toLayer:layer]) {
            return;
        }

        FQLog(LOG_I, @"[%d / %.3f ms] Metal frame rendering", frame.frameNumber, frame.pts);

        size_t planes = CVPixelBufferGetPlaneCount(frame.pixelBuffer);
        assert(planes <= MAX_VIDEO_PLANES);

        if (layerDidChange && frame.frameNumber > 1) {
            Log(LOG_I, @"Metal frame changed layer's colorspace and/or pixel format");
            _videoPipelineState[planes] = nil;
        }

        // This is created once and cached based on the planes value
        if (!_videoPipelineState[planes]) {
            MTLRenderPipelineDescriptor *pipelineDesc = [MTLRenderPipelineDescriptor new];
            id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

            // RGB shaders
            id<MTLFunction> vertexVsDraw = [defaultLibrary newFunctionWithName:@"vs_draw"];
            id<MTLFunction> fragmentBiplanar = [defaultLibrary newFunctionWithName:@"ps_draw_biplanar"];
            id<MTLFunction> fragmentTriplanar = [defaultLibrary newFunctionWithName:@"ps_draw_triplanar"];

            // linear shaders
            id<MTLFunction> yuvToLinear = [defaultLibrary newFunctionWithName:@"yuvToLinear"];

            pipelineDesc.colorAttachments[0].pixelFormat = layer.pixelFormat;
            pipelineDesc.vertexBuffers[0].mutability = MTLMutabilityImmutable;

            if (layer.pixelFormat == MTLPixelFormatRGBA16Float) {
                // 4:2:0 or 4:4:4 YUV -> BT.2020 RGB -> linear float
                pipelineDesc.vertexFunction = vertexVsDraw;
                pipelineDesc.fragmentFunction = yuvToLinear;
            } else {
                // 4:2:0 or 4:4:4 YUV -> BT.2020 RGB
                pipelineDesc.vertexFunction = vertexVsDraw;
                pipelineDesc.fragmentFunction = (planes == 2) ? fragmentBiplanar : fragmentTriplanar;
            }

            NSError *error = nil;
            _videoPipelineState[planes] = [_device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
            if (!_videoPipelineState[planes]) {
                Log(LOG_E, @"Failed to create video pipeline state: %@", error);
                return;
            }
        }

        for (size_t i = 0; i < planes; i++) {
            MTLPixelFormat fmt;

            switch (CVPixelBufferGetPixelFormatType(frame.pixelBuffer)) {
                case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
                case kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange:
                case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
                case kCVPixelFormatType_444YpCbCr8BiPlanarFullRange:
                    fmt = (i == 0) ? MTLPixelFormatR8Unorm : MTLPixelFormatRG8Unorm;
                    break;

                case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
                case kCVPixelFormatType_444YpCbCr10BiPlanarFullRange:
                case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
                case kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange:
                    fmt = (i == 0) ? MTLPixelFormatR16Unorm : MTLPixelFormatRG16Unorm;
                    break;

                default:
                    Log(LOG_E, @"Unknown pixel format: %@", CVPixelBufferGetPixelFormatType(frame.pixelBuffer));
                    return;
            }

            CVReturn err = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                     _textureCache,
                                                                     frame.pixelBuffer,
                                                                     NULL,
                                                                     fmt,
                                                                     CVPixelBufferGetWidthOfPlane(frame.pixelBuffer, i),
                                                                     CVPixelBufferGetHeightOfPlane(frame.pixelBuffer, i),
                                                                     i,
                                                                     &_cvMetalTextures[i]);
            if (err != kCVReturnSuccess) {
                Log(LOG_E, @"CVMetalTextureCacheCreateTextureFromImage() failed: %d", err);
                return;
            }
        }

        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (!drawable) {
            Log(LOG_E, @"Failed to get nextDrawable");
            return;
        }
        _renderPassDescriptor.colorAttachments[0].texture = drawable.texture;

        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_renderPassDescriptor];

        [renderEncoder setRenderPipelineState:_videoPipelineState[planes]];
        for (size_t i = 0; i < planes; i++) {
            [renderEncoder setFragmentTexture:CVMetalTextureGetTexture(_cvMetalTextures[i]) atIndex:i];
        }

//        if (layer.pixelFormat == MTLPixelFormatRGBA16Float) {
//            [self pollCurrentEDRHeadroom];
//            [renderEncoder setFragmentBytes:&_currentEDRHeadroom length:sizeof(CGFloat) atIndex:0];
//        }

        [renderEncoder setVertexBuffer:_VideoVertexBuffer offset:0 atIndex:0];
        [renderEncoder setFragmentBuffer:_CscParamsBuffer offset:0 atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [renderEncoder endEncoding];

#if !TARGET_OS_SIMULATOR
        __block MetalVideoRenderer *strongSelf = self;
        [drawable addPresentedHandler:^(id<MTLDrawable> d) {
            if (strongSelf.lastPresented > 0.0f) {
                CFTimeInterval frametime = d.presentedTime - strongSelf.lastPresented;
                [[ImGuiPlots sharedInstance] observeFloat:PLOT_FRAMETIME value:(frametime * 1000.0)];
            }
            strongSelf.lastPresented = d.presentedTime;
        }];
#endif

        // signal semaphore, compute GPU time average, and clear textures
        __block dispatch_semaphore_t block_semaphore = _inFlightSemaphore;
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> cb) {
            dispatch_semaphore_signal(block_semaphore);

            const CFTimeInterval GPUTime = cb.GPUEndTime - cb.GPUStartTime;
            const double alpha = 0.25f;
            self->_averageGPUTime = (GPUTime * alpha) + (self->_averageGPUTime * (1.0 - alpha));

            // Free textures after completion of rendering
            for (size_t i = 0; i < planes; i++) {
                if (self->_cvMetalTextures[i]) {
                    CFRelease(self->_cvMetalTextures[i]);
                    self->_cvMetalTextures[i] = nil;
                }
            }

            CVMetalTextureCacheFlush(self->_textureCache, 0);
        }];

#if TARGET_OS_SIMULATOR
        [commandBuffer presentDrawable:drawable];
#else
        // present for a minimum duration for best frame pacing
        [commandBuffer presentDrawable:drawable afterMinimumDuration:1.0f / _framerate];
#endif

        [commandBuffer commit];

        // Wait for the command buffer to complete and free our CVMetalTextureCache references
        [commandBuffer waitUntilCompleted];
    }
}

- (void)waitToRenderTo:(nonnull CAMetalLayer *)layer {
    // Wait to ensure only `MaxFramesInFlight` number of frames are getting processed
    // by any stage in the Metal pipeline (CPU, GPU, Metal, Drivers, etc.).
    if (!self.isStopping) {
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1f * NSEC_PER_SEC));  // 100ms
        dispatch_semaphore_wait(_inFlightSemaphore, timeout);
    }
}

- (void)shutdown {
    Log(LOG_I, @"XXX MetalVideoRenderer shutodwn");
    self.isStopping = YES;

    // Ensure no rendering is in flight
    for (NSUInteger i = 0; i < MaxFramesInFlight; i++) {
        dispatch_semaphore_signal(_inFlightSemaphore);
    }
}

/// Responds to the drawable's size or orientation changes.
- (void)drawableResize:(CGSize)drawableSize {
    [self resize:drawableSize];
}

- (void)resize:(CGSize)size {
}

@end

//
//  VideoDecoderRenderer.m
//  Selene
//
//  Created by Cameron Gutman on 18/10/2014.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import VideoToolbox;
@import GameStreamKit;

#import "VideoDecoderRenderer.h"
#import "DataManager.h"
#import "TemporarySettings.h"
#import "FrameQueue.h"
#import "StreamView.h"
#import "Plot.h"
#import "Frame.h"
#import "MetalVideoRenderer.h"
#import "FloatBuffer.h"
#import "PlotManager.h"
#import "Logger.h"

@implementation VideoDecoderRenderer {
    dispatch_queue_t _sq, _vtq;
    StreamView* _view;
    id<ConnectionCallbacks> _callbacks;
    float _streamAspectRatio;

    int _videoFormat;
    int _frameRate;

    NSMutableArray *_parameterSetBuffers;
    NSData *_masteringDisplayColorVolume;
    NSData *_contentLightLevelInfo;
    CMVideoFormatDescriptionRef _formatDesc;
    VTDecompressionSessionRef _decompressionSession;

    FrameQueue *_frameQueue;
    NSInteger _maxRefreshRate;

}


- (instancetype)initWithView:(StreamView*)view callbacks:(id<ConnectionCallbacks>)callbacks streamAspectRatio:(float)aspectRatio
{
    self = [super init];

    _sq = dispatch_queue_create("me.noebarlet.Selene.VideoDecoderRenderer",
                                 dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));

    // Video decoder needs to run at the highest priority since DisplayLink waits on it
    _vtq = dispatch_queue_create("me.noebarlet.Selene.VideoDecoderRenderer.VTDecoder",
                                dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));

    _view = view;
    _callbacks = callbacks;
    _streamAspectRatio = aspectRatio;
    
    _maxRefreshRate = [[UIScreen mainScreen] maximumFramesPerSecond];
    _parameterSetBuffers = [[NSMutableArray alloc] init];

    DataManager* dataMan = [[DataManager alloc] init];
    
    _frameQueue = [FrameQueue sharedInstance];
    [_frameQueue start];
    [_frameQueue setHighWaterMark:(int)[[dataMan getSettings].frameQueueSize integerValue]];

    return self;
}

# pragma mark DisplayLink vsync callback

- (void)setupWithVideoFormat:(int)videoFormat width:(int)videoWidth height:(int)videoHeight frameRate:(int)frameRate
{
    self->_videoFormat = videoFormat;
    self->_frameRate = frameRate;
    
    // reset plot data in case we've already used it for a previous renderer
    [[PlotManager sharedInstance] clearData];
}


- (void)setupDecompressionSessionWithAttributes:(NSDictionary *)destinationPixelBufferAttributes {
    if (_decompressionSession != NULL) {
        VTDecompressionSessionInvalidate(_decompressionSession);
        CFRelease(_decompressionSession);
        _decompressionSession = nil;
    }
    
    NSDictionary *decoderSpec = @{
        (__bridge NSString*)kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: @YES
    };

    int status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _formatDesc,
                                              (__bridge CFDictionaryRef)decoderSpec,
                                              (__bridge CFDictionaryRef)destinationPixelBufferAttributes,
                                              nil,
                                              &_decompressionSession);
    if (status != noErr) {
        Log(LOG_E, @"Failed to create VTDecompressionSession, status %d", status);
    }
    
    // Real-time
    VTSessionSetProperty(_decompressionSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    
    // Ensure we're using HW accelerated decoding
    CFTypeRef v = NULL;
    if (VTSessionCopyProperty(_decompressionSession,
                              kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
                              kCFAllocatorDefault, &v) == noErr) {
        Log(LOG_I, @"Using HW decode: %@", (v == kCFBooleanTrue) ? @"YES" : @"NO");
        if (v) CFRelease(v);
    }
}

- (void)setupDecompressionSession {
#if TARGET_OS_SIMULATOR
    NSNumber *pixelFormat = @(kCVPixelFormatType_32BGRA);
#else
    NSNumber *pixelFormat = nil;
    if (self->_videoFormat & [StreamVideoFormat maskYuv444]) {
        if (self->_videoFormat & [StreamVideoFormat mask10Bit]) {
            pixelFormat = @(kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange);
        }
        else {
            pixelFormat = @(kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange);
        }
    }
    else {
        if (self->_videoFormat & [StreamVideoFormat mask10Bit]) {
            pixelFormat = @(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange);
        }
        else {
            pixelFormat = @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
        }
    }
#endif

    NSDictionary *destinationPixelBufferAttributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey : pixelFormat,
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferMetalCompatibilityKey: @YES,
        //(id)kCVPixelBufferPoolMinimumBufferCountKey: @12,
    };

    return [self setupDecompressionSessionWithAttributes:destinationPixelBufferAttributes];
}


int DrSubmitDecodeUnit(StreamDecodeUnit* decodeUnit);


- (void)cleanup
{
    [_frameQueue stop];

    if (_decompressionSession != NULL) {
        VTDecompressionSessionInvalidate(_decompressionSession);
        CFRelease(_decompressionSession);
        _decompressionSession = nil;
    }
}

#define NALU_START_PREFIX_SIZE 3
#define NAL_LENGTH_PREFIX_SIZE 4

- (void)updateAnnexBBufferForRange:(CMBlockBufferRef)frameBuffer dataBlock:(CMBlockBufferRef)dataBuffer offset:(int)offset length:(int)nalLength
{
    OSStatus status;
    size_t oldOffset = CMBlockBufferGetDataLength(frameBuffer);

    // Append a 4 byte buffer to the frame block for the length prefix
    status = CMBlockBufferAppendMemoryBlock(frameBuffer, NULL,
                                            NAL_LENGTH_PREFIX_SIZE,
                                            kCFAllocatorDefault, NULL, 0,
                                            NAL_LENGTH_PREFIX_SIZE, 0);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferAppendMemoryBlock failed: %d", (int)status);
        return;
    }

    // Write the length prefix to the new buffer
    const int dataLength = nalLength - NALU_START_PREFIX_SIZE;
    const uint8_t lengthBytes[] = {(uint8_t)(dataLength >> 24), (uint8_t)(dataLength >> 16),
        (uint8_t)(dataLength >> 8), (uint8_t)dataLength};
    status = CMBlockBufferReplaceDataBytes(lengthBytes, frameBuffer,
                                           oldOffset, NAL_LENGTH_PREFIX_SIZE);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferReplaceDataBytes failed: %d", (int)status);
        return;
    }

    // Attach the data buffer to the frame buffer by reference
    status = CMBlockBufferAppendBufferReference(frameBuffer, dataBuffer, offset + NALU_START_PREFIX_SIZE, dataLength, 0);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferAppendBufferReference failed: %d", (int)status);
        return;
    }
}

#pragma mark VideoRecv thread - Decoder

// This function must free data for bufferType == BUFFER_TYPE_PICDATA
- (int)submitDecodeBuffer:(unsigned char *)data
                   length:(int)length
               bufferType:(int)bufferType
               decodeUnit:(StreamDecodeUnit*)du
          decodeStartTime:(CFTimeInterval)decodeStartTime
{
    OSStatus status;

    // Construct a new format description object each time we receive an IDR frame
    if (du.frameType == StreamFrameTypeIdrFrame) {
        if (bufferType != StreamBufferTypePictureData) {
            if (bufferType == StreamBufferTypeVps || bufferType == StreamBufferTypeSps || bufferType == StreamBufferTypePps) {
                // Add new parameter set into the parameter set array
                int startLen = data[2] == 0x01 ? 3 : 4;
                [_parameterSetBuffers addObject:[NSData dataWithBytes:&data[startLen] length:length - startLen]];
            }

            // Data is NOT to be freed here. It's a direct usage of the caller's buffer.

            // No frame data to submit for these NALUs
            return DecoderRendererStatusOk;
        }

        // Create the new format description when we get the first picture data buffer of an IDR frame.
        // This is the only way we know that there is no more CSD for this frame.
        //
        // NB: This logic depends on the fact that we submit all picture data in one buffer!

        // Free the old format description
        if (_formatDesc != NULL) {
            CFRelease(_formatDesc);
            _formatDesc = NULL;
        }

        if (_videoFormat & StreamVideoFormat.maskH264) {
            // Construct parameter set arrays for the format description
            size_t parameterSetCount = [_parameterSetBuffers count];
            const uint8_t* parameterSetPointers[parameterSetCount];
            size_t parameterSetSizes[parameterSetCount];
            for (int i = 0; i < parameterSetCount; i++) {
                NSData* parameterSet = _parameterSetBuffers[i];
                parameterSetPointers[i] = parameterSet.bytes;
                parameterSetSizes[i] = parameterSet.length;
            }

            Log(LOG_I, @"Constructing new H264 format description");
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                         parameterSetCount,
                                                                         parameterSetPointers,
                                                                         parameterSetSizes,
                                                                         NAL_LENGTH_PREFIX_SIZE,
                                                                         &_formatDesc);
            if (status != noErr) {
                Log(LOG_E, @"Failed to create H264 format description: %d", (int)status);
                _formatDesc = NULL;
            }

            LogOnce(LOG_I, @"H264 format description: %@", _formatDesc);

            // Free parameter set buffers after submission
            [_parameterSetBuffers removeAllObjects];
        }
        else if (_videoFormat & StreamVideoFormat.maskH265) {
            // Construct parameter set arrays for the format description
            size_t parameterSetCount = [_parameterSetBuffers count];
            const uint8_t* parameterSetPointers[parameterSetCount];
            size_t parameterSetSizes[parameterSetCount];
            for (int i = 0; i < parameterSetCount; i++) {
                NSData* parameterSet = _parameterSetBuffers[i];
                parameterSetPointers[i] = parameterSet.bytes;
                parameterSetSizes[i] = parameterSet.length;
            }

            Log(LOG_I, @"Constructing new HEVC format description");

            NSMutableDictionary* videoFormatParams = [[NSMutableDictionary alloc] init];

            if (_contentLightLevelInfo) {
                [videoFormatParams setObject:_contentLightLevelInfo forKey:(__bridge NSString*)kCMFormatDescriptionExtension_ContentLightLevelInfo];
            }

            if (_masteringDisplayColorVolume) {
                [videoFormatParams setObject:_masteringDisplayColorVolume forKey:(__bridge NSString*)kCMFormatDescriptionExtension_MasteringDisplayColorVolume];
            }

            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault,
                                                                         parameterSetCount,
                                                                         parameterSetPointers,
                                                                         parameterSetSizes,
                                                                         NAL_LENGTH_PREFIX_SIZE,
                                                                         (__bridge CFDictionaryRef)videoFormatParams,
                                                                         &_formatDesc);

            if (status != noErr) {
                Log(LOG_E, @"Failed to create HEVC format description: %d", (int)status);
                _formatDesc = NULL;
            }

            LogOnce(LOG_I, @"HEVC format description: %@", _formatDesc);

            // Free parameter set buffers after submission
            [_parameterSetBuffers removeAllObjects];
        }
        else {
            // Unsupported codec!
            abort();
        }
    }

    if (_formatDesc == NULL) {
        // Can't decode if we haven't gotten our parameter sets yet
        free(data);
        return DecoderRendererStatusNeedIdr;
    }

    // Now we're decoding actual frame data here
    CMBlockBufferRef frameBlockBuffer;
    CMBlockBufferRef dataBlockBuffer;

    status = CMBlockBufferCreateWithMemoryBlock(NULL, data, length, kCFAllocatorDefault, NULL, 0, length, 0, &dataBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateWithMemoryBlock failed: %d", (int)status);
        free(data);
        return DecoderRendererStatusNeedIdr;
    }

    // From now on, CMBlockBuffer owns the data pointer and will free it when it's dereferenced

    status = CMBlockBufferCreateEmpty(NULL, 0, 0, &frameBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateEmpty failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        return DecoderRendererStatusNeedIdr;
    }

    // H.264 and HEVC formats require NAL prefix fixups from Annex B to length-delimited
    if (_videoFormat & (StreamVideoFormat.maskH264 | StreamVideoFormat.maskH265)) {
        int lastOffset = -1;
        for (int i = 0; i < length - NALU_START_PREFIX_SIZE; i++) {
            // Search for a NALU
            if (data[i] == 0 && data[i+1] == 0 && data[i+2] == 1) {
                // It's the start of a new NALU
                if (lastOffset != -1) {
                    // We've seen a start before this so enqueue that NALU
                    [self updateAnnexBBufferForRange:frameBlockBuffer dataBlock:dataBlockBuffer offset:lastOffset length:i - lastOffset];
                }

                lastOffset = i;
            }
        }

        if (lastOffset != -1) {
            // Enqueue the remaining data
            [self updateAnnexBBufferForRange:frameBlockBuffer dataBlock:dataBlockBuffer offset:lastOffset length:length - lastOffset];
        }
    }
    else {
        // For formats that require no length-changing fixups, just append a reference to the raw data block
        status = CMBlockBufferAppendBufferReference(frameBlockBuffer, dataBlockBuffer, 0, length, 0);
        if (status != noErr) {
            Log(LOG_E, @"CMBlockBufferAppendBufferReference failed: %d", (int)status);
            return DecoderRendererStatusNeedIdr;
        }
    }

    // Set the current frame's pts, in RTP 90khz units. We will set the duration
    // later in FrameQueue because it requires the next frame's timestamp.
    CMSampleTimingInfo sampleTiming = {
        .duration              = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMake((int64_t)du.rtpTimestamp, 90000),
        .decodeTimeStamp       = kCMTimeInvalid,
    };

    CMSampleBufferRef sampleBuffer;
    status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                  frameBlockBuffer,
                                  _formatDesc, 1, 1,
                                  &sampleTiming, 0, NULL,
                                  &sampleBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMSampleBufferCreate failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        CFRelease(frameBlockBuffer);
        return DecoderRendererStatusNeedIdr;
    }

    OSStatus decodeStatus = [self decodeFrameWithSampleBuffer:sampleBuffer
                                                  frameNumber:du.frameNumber
                                                    frameType:du.frameType
                                              decodeStartTime:decodeStartTime];
    // Dereference the buffers
    CFRelease(dataBlockBuffer);
    CFRelease(frameBlockBuffer);
    CFRelease(sampleBuffer);

    return decodeStatus == noErr ? DecoderRendererStatusOk : DecoderRendererStatusNeedIdr;
}

- (OSStatus)decodeFrameWithSampleBuffer:(CMSampleBufferRef)sampleBuffer
                            frameNumber:(int)frameNumber
                              frameType:(int)frameType
                        decodeStartTime:(CFTimeInterval)decodeStartTime {
  if (frameType == StreamFrameTypeIdrFrame || _decompressionSession == nil) {
    [self setupDecompressionSession];
  }

  OSStatus status = VTDecompressionSessionDecodeFrameWithOutputHandler(
      _decompressionSession,
      sampleBuffer,
      0,
      NULL,
      ^(OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef _Nullable imageBuffer, CMTime presentationTimestamp, CMTime presentationDuration) {
          if (status != noErr || !imageBuffer) {
            NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
            Log(LOG_E, @"Decompression session error: %@", error);
            [GameStream requestIdrFrame];
            return;
          }

          // Metal path: retain the pixelBuffer here so it survives the dispatch
          CVPixelBufferRef pixelBuffer = CVPixelBufferRetain((CVPixelBufferRef)imageBuffer);

          // Dispatch onto our higher priority queue
          dispatch_async(self->_vtq, ^{
              Frame *frame = [[Frame alloc] initWithPixelBufffer:pixelBuffer frameNumber:frameNumber frameType:frameType pts:presentationTimestamp];
              [frame setFormatDesc:self->_formatDesc];
              int framesDropped = [self->_frameQueue enqueue:frame withSlackSize:3];

              static PlotMetrics frameQueueMetrics = {};
              [[PlotManager sharedInstance] observeFloatReturnMetrics:PlotTypeQueuedFrames value:[self->_frameQueue count] plotMetrics:(struct PlotMetrics *)&frameQueueMetrics];
              [self safeCopyMetricsTo:&self->_frameQueueMetrics from:&frameQueueMetrics];

              [[PlotManager sharedInstance] observeFloat:PlotTypeDropped value:framesDropped];

              // It's important we capture host metrics on the incoming thread, as this frame object
              // may have been dropped by the above enqueue
              static CFTimeInterval lastHostFrame = 0.0f;
              if (lastHostFrame != 0) {
                [[PlotManager sharedInstance] observeFloat:PlotTypeHostFrametime value:(frame.pts - lastHostFrame) * 1000.0];
              }
              lastHostFrame = frame.pts;

              // Decode time is not graphed because it is marked as hidden, but we can use the same mechanism for the value used by stats
              static PlotMetrics decodeMetrics = {};
              [[PlotManager sharedInstance] observeFloatReturnMetrics:PlotTypeDecode value:(CACurrentMediaTime() - decodeStartTime) * 1000.0 plotMetrics:(struct PlotMetrics *)&decodeMetrics];
              [self safeCopyMetricsTo:&self->_decodeMetrics from:&decodeMetrics];
          });
      });

  return status;
}

- (void)setHdrMode:(BOOL)enabled {
    SSHdrMetadata* hdrMetadata = [GameStream getHdrMetadata];

    BOOL hasMetadata = enabled && hdrMetadata;
    BOOL metadataChanged = NO;

    if (hasMetadata && hdrMetadata.displayPrimaries[0].x != 0 && hdrMetadata.maxDisplayLuminance != 0) {
        // This data is all in big-endian
        struct {
          vector_ushort2 primaries[3];
          vector_ushort2 white_point;
          uint32_t luminance_max;
          uint32_t luminance_min;
        } __attribute__((packed, aligned(4))) mdcv;

        // mdcv is in GBR order while SS_HDR_METADATA is in RGB order
        mdcv.primaries[0].x = __builtin_bswap16(hdrMetadata.displayPrimaries[1].x);
        mdcv.primaries[0].y = __builtin_bswap16(hdrMetadata.displayPrimaries[1].y);
        mdcv.primaries[1].x = __builtin_bswap16(hdrMetadata.displayPrimaries[2].x);
        mdcv.primaries[1].y = __builtin_bswap16(hdrMetadata.displayPrimaries[2].y);
        mdcv.primaries[2].x = __builtin_bswap16(hdrMetadata.displayPrimaries[0].x);
        mdcv.primaries[2].y = __builtin_bswap16(hdrMetadata.displayPrimaries[0].y);

        mdcv.white_point.x = __builtin_bswap16(hdrMetadata.whitePoint.x);
        mdcv.white_point.y = __builtin_bswap16(hdrMetadata.whitePoint.y);

        // These luminance values are in 10000ths of a nit
        mdcv.luminance_max = __builtin_bswap32((uint32_t)hdrMetadata.maxDisplayLuminance * 10000);
        mdcv.luminance_min = __builtin_bswap32(hdrMetadata.minDisplayLuminance);

        NSData* newMdcv = [NSData dataWithBytes:&mdcv length:sizeof(mdcv)];
        if (_masteringDisplayColorVolume == nil || ![newMdcv isEqualToData:_masteringDisplayColorVolume]) {
            _masteringDisplayColorVolume = newMdcv;
            metadataChanged = YES;

            Log(LOG_I, @"HDR Mastering Display Color Volume: G(%d,%d) B(%d,%d) R(%d,%d) white point(%d,%d) luminance (%d,%d)",
                mdcv.primaries[0].x, mdcv.primaries[0].y,
                mdcv.primaries[1].x, mdcv.primaries[1].y,
                mdcv.primaries[2].x, mdcv.primaries[2].y,
                mdcv.white_point.x, mdcv.white_point.y,
                mdcv.luminance_max, mdcv.luminance_min);
        }
    }
    else if (_masteringDisplayColorVolume != nil) {
        _masteringDisplayColorVolume = nil;
        metadataChanged = YES;
    }

    if (hasMetadata && hdrMetadata.maxContentLightLevel != 0 && hdrMetadata.maxFrameAverageLightLevel != 0) {
        // This data is all in big-endian
        struct {
            uint16_t max_content_light_level;
            uint16_t max_frame_average_light_level;
        } __attribute__((packed, aligned(2))) cll;

        cll.max_content_light_level = __builtin_bswap16(hdrMetadata.maxContentLightLevel);
        cll.max_frame_average_light_level = __builtin_bswap16(hdrMetadata.maxFrameAverageLightLevel);

        NSData* newCll = [NSData dataWithBytes:&cll length:sizeof(cll)];
        if (_contentLightLevelInfo == nil || ![newCll isEqualToData:_contentLightLevelInfo]) {
            _contentLightLevelInfo = newCll;
            metadataChanged = YES;

            Log(LOG_I, @"HDR maxCLL: %d maxFALL: %d",
                cll.max_content_light_level, cll.max_frame_average_light_level);
        }
    }
    else if (_contentLightLevelInfo != nil) {
        _contentLightLevelInfo = nil;
        metadataChanged = YES;
    }

    // If the metadata changed, request an IDR frame to re-create the CMVideoFormatDescription
    if (metadataChanged) {
        [GameStream requestIdrFrame];
    }
}

- (void)safeCopyMetricsTo:(PlotMetrics *)dst from:(PlotMetrics *)src {
    if (dst != nil && src != nil) {
        dispatch_sync(_sq, ^{
            memcpy(dst, src, sizeof(PlotMetrics));
        });
    }
}

- (void)getAllStats:(VideoStats *)stats {
    stats->renderingBackendString = [NSString stringWithFormat:@"Metal, colorspace: %@", [MetalVideoRenderer currentColorSpace]];

    dispatch_sync(_sq, ^{
        memcpy(&stats->decodeMetrics, &_decodeMetrics, sizeof(PlotMetrics));
        memcpy(&stats->frameQueueMetrics, &_frameQueueMetrics, sizeof(PlotMetrics));
        [_frameQueue.frameDropMetrics copyMetrics:&stats->frameDropMetrics];
    });
}

@end

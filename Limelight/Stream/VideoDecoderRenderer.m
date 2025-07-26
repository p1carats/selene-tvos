//
//  VideoDecoderRenderer.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/18/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import VideoToolbox;
@import GameStreamKit;

#import "DataManager.h"
#import "TemporarySettings.h"
#import "VideoDecoderRenderer.h"
#import "FrameQueue.h"
#import "ConnectionCallbacks.h"
#import "StreamView.h"
#import "Plot.h"
#import "Frame.h"
#import "PlatformThreads.h"
#import "MetalViewController.h"
#import "FloatBuffer.h"
#import "PlotManager.h"
#import "Logger.h"

@class StreamView;

// Define for extra logging related to frame pacing
#define DISPLAYLINK_VERBOSE

@implementation VideoDecoderRenderer {
    dispatch_queue_t _sq, _vtq;
    StreamView* _view;
    id<ConnectionCallbacks> _callbacks;
    float _streamAspectRatio;

    AVSampleBufferDisplayLayer* _displayLayer;
    int _videoFormat;
    int _frameRate;

    NSMutableArray *_parameterSetBuffers;
    NSData *_masteringDisplayColorVolume;
    NSData *_contentLightLevelInfo;
    CMVideoFormatDescriptionRef _formatDesc;
    CMVideoFormatDescriptionRef _formatDescImageBuffer;
    VTDecompressionSessionRef _decompressionSession;

    CADisplayLink *_displayLink;
    FrameQueue *_frameQueue;
    NSInteger _maxRefreshRate;
    RenderingBackend _renderingBackend;

}

- (void)reinitializeDisplayLayer
{
    CALayer *oldLayer = _displayLayer;

    _displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    _displayLayer.backgroundColor = [UIColor blackColor].CGColor;

    // Ensure the AVSampleBufferDisplayLayer is sized to preserve the aspect ratio
    // of the video stream. We used to use AVLayerVideoGravityResizeAspect, but that
    // respects the PAR encoded in the SPS which causes our computed video-relative
    // touch location to be wrong in StreamView if the aspect ratio of the host
    // desktop doesn't match the aspect ratio of the stream.
    CGSize videoSize;
    if (_view.bounds.size.width > _view.bounds.size.height * _streamAspectRatio) {
        videoSize = CGSizeMake(_view.bounds.size.height * _streamAspectRatio, _view.bounds.size.height);
    } else {
        videoSize = CGSizeMake(_view.bounds.size.width, _view.bounds.size.width / _streamAspectRatio);
    }
    _displayLayer.position = CGPointMake(CGRectGetMidX(_view.bounds), CGRectGetMidY(_view.bounds));
    _displayLayer.bounds = CGRectMake(0, 0, videoSize.width, videoSize.height);
    _displayLayer.videoGravity = AVLayerVideoGravityResize;

    // Hide the layer until we get an IDR frame. This ensures we
    // can see the loading progress label as the stream is starting.
    _displayLayer.hidden = YES;

    if (oldLayer != nil) {
        // Switch out the old display layer with the new one
        [_view.layer replaceSublayer:oldLayer with:_displayLayer];
    }
    else {
        [_view.layer addSublayer:_displayLayer];
    }

    if (_formatDesc != nil) {
        CFRelease(_formatDesc);
        _formatDesc = nil;
    }

    if (_formatDescImageBuffer != nil) {
        CFRelease(_formatDescImageBuffer);
        _formatDescImageBuffer = nil;
    }

    if (_decompressionSession != nil){
        VTDecompressionSessionInvalidate(_decompressionSession);
        CFRelease(_decompressionSession);
        _decompressionSession = nil;
    }
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

    _parameterSetBuffers = [[NSMutableArray alloc] init];
    _frameQueue = [FrameQueue sharedInstance];
    _maxRefreshRate = [[UIScreen mainScreen] maximumFramesPerSecond];

    DataManager* dataMan = [[DataManager alloc] init];

    [_frameQueue setHighWaterMark:(int)[[dataMan getSettings].frameQueueSize integerValue]];

    [self reinitializeDisplayLayer];

    return self;
}

# pragma mark DisplayLink vsync callback

- (void)setupWithVideoFormat:(int)videoFormat width:(int)videoWidth height:(int)videoHeight frameRate:(int)frameRate
{
    self->_videoFormat = videoFormat;
    self->_frameRate = frameRate;

    DataManager* dataMan = [[DataManager alloc] init];
    if ([[dataMan getSettings].renderingBackend integerValue] == RenderingBackendAVSampleBuffer) {
        // FramePacingModeVSync:
        // Deliver 1 frame at each vsync interval. Ignores server pts timestamps.
        // Drop frames intelligently to maintain chosen queue size.
        _renderingBackend = RenderingBackendAVSampleBuffer;
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderModeAVSB:)];
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(self->_frameRate, self->_frameRate, self->_frameRate);
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } else {
        _renderingBackend = RenderingBackendMetal;
        // RENDER_METAL begins in StreamFrameViewController.
    }
}


- (void)setupDecompressionSessionWithAttributes:(NSDictionary *)destinationPixelBufferAttributes {
    if (_decompressionSession != NULL) {
        VTDecompressionSessionInvalidate(_decompressionSession);
        CFRelease(_decompressionSession);
        _decompressionSession = nil;
    }

    int status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _formatDesc,
                                              nil,
                                              (__bridge CFDictionaryRef)destinationPixelBufferAttributes,
                                              nil,
                                              &_decompressionSession);
    if (status != noErr) {
        Log(LOG_E, @"Failed to create VTDecompressionSession, status %d", status);
    }
}

- (void)setupDecompressionSession {
#if TARGET_OS_SIMULATOR
    NSNumber *pixelFormat = @(kCVPixelFormatType_32BGRA);
#else
    NSNumber *pixelFormat = nil;
    if (self->_videoFormat & VIDEO_FORMAT_MASK_YUV444) {
        pixelFormat = @(kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange);
    }
    else {
        pixelFormat = @(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange);
    }
#endif

    NSDictionary *destinationPixelBufferAttributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey : pixelFormat,
        (id)kVTDecompressionPropertyKey_GeneratePerFrameHDRDisplayMetadata : @YES,
        (id)kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder : @YES
    };

    return [self setupDecompressionSessionWithAttributes:destinationPixelBufferAttributes];
}

- (void) checkDisplayLayer {
    // Check for issues with the SampleBuffer, this should be much less likely since
    // AVSB is not actually decoding the frames anymore
    if (self->_displayLayer.sampleBufferRenderer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        Log(LOG_E, @"Display layer rendering failed: %@", _displayLayer.sampleBufferRenderer.error);

        // Recreate the display layer. We are already on the main thread,
        // so this is safe to do right here.
        [self reinitializeDisplayLayer];

        // Request an IDR frame to initialize the new decoder
        LiRequestIdrFrame();
    }
}

int DrSubmitDecodeUnit(PDECODE_UNIT decodeUnit);

#pragma mark DisplayLink - Frame Pacing - Vsync with FrameQueue

// This frame pacing method was inspired by the behavior of moonlight-qt's Pacer class, although it has evolved
// a few additional features. Incoming frames from Sunshine are asynchronously processed into a queue by the VideoRecv thread.
// DisplayLink calls us every vsync we we try to present the most recent frame. We try to maintain a user-configurable buffer
// of 1-5 frames. If the buffer is full, every other frame is dropped which just appears to the user as a lower framerate stream.
- (void)renderModeAVSB:(CADisplayLink *)link {
    CFTimeInterval start = link.timestamp;
    CFTimeInterval deadline = link.targetTimestamp;
    static CFTimeInterval lastTargetLocal = 0.0f;
    CFTimeInterval dl0 = CACurrentMediaTime();

    static int lateCallbacks = 0;
    if (dl0 > deadline) {
        // we already missed it, count how often this happens
        lateCallbacks++;
        return;
    }

    [self checkDisplayLayer];

    static CFTimeInterval avgOverhead = 0.004f; // averaged each callback
    CFTimeInterval waitFor = deadline - dl0 - avgOverhead;
    if (waitFor < 0.001f) {
        waitFor = 0.0f;
    }

    // Get the next frame or wait if necessary. If no frame arrives the previous one will be redisplayed automatically.
    Frame *frame = [_frameQueue dequeueWithTimeout:waitFor];
    if (frame) {
        CFTimeInterval dl1 = CACurrentMediaTime();

        LogOnce(LOG_I, @"Frame pacing: using AVSampleBufferDisplayLayer target %f Hz with %d FPS stream", 1.0f / (deadline - start), self->_frameRate);

        // The system works best with properly timed video frames, which we time to the end of the next vsync period,
        // the earliest they can be displayed due to double-buffering.
        CFTimeInterval targetLocal = deadline + link.duration;

        [self renderFrame:frame atTime:CMTimeMakeWithSeconds(targetLocal, NSEC_PER_SEC)];

#ifdef DISPLAYLINK_VERBOSE
        Log(LOG_I, @"[%.3f] rendering frame %d, waitFor %.3f ms, overhead %.3f ms, lateCallbacks %d, queue size %d",
            deadline, frame.frameNumber, waitFor * 1000.0, avgOverhead * 1000.0, lateCallbacks, [_frameQueue count]);
#endif

        // Update metrics
        if (lastTargetLocal != 0) {
            CFTimeInterval frametime = targetLocal - lastTargetLocal;
            if (frametime > deadline - start + 0.0005f) {
                // we missed a callback
                // Log(LOG_W, @"*** slow frametime %.3f ms", frametime * 1000.0);
            }
            [[PlotManager sharedInstance] observeFloat:PlotTypeFrametime value:frametime * 1000.0];
        }
        lastTargetLocal = targetLocal;

        // weighted moving average of how much time displayLink needs after dequeuing a frame.
        // This is used to avoid overshooting a vsync by waiting too long.
        const double alpha = 0.1f;
        avgOverhead = ((CACurrentMediaTime() - dl1) * alpha) + (avgOverhead * (1.0 - alpha));
    }
}

// Render frame at a specific targetTime
- (void)renderFrame:(Frame *)frame atTime:(CMTime)targetTime {
    CMSampleBufferSetOutputPresentationTimeStamp(frame.sampleBuffer, targetTime);

    if (frame.frameNumber == 1) {
        // On first frame, set timebase to the initial presentation time.
        // This will let us present frames using the local clock (vsync pacing) or
        // the pts timestamps from the host.
        CMTimebaseRef timebase = NULL;
        CMTimebaseCreateWithSourceClock(CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &timebase);

        // Set the timebase to the initial pts here
        CMTime pts = CMSampleBufferGetOutputPresentationTimeStamp(frame.sampleBuffer);
        CMTimebaseSetTime(timebase, pts);
        CMTimebaseSetRate(timebase, 1.0);

        [self->_displayLayer setControlTimebase:timebase];
        Log(LOG_I, @"Setting timebase for stream to %d / %d", pts.value, pts.timescale);
    }

    [self->_displayLayer.sampleBufferRenderer enqueueSampleBuffer:frame.sampleBuffer];

#ifdef DISPLAYLINK_VERBOSE
    // Some OS-level metrics I'm not sure what to do with
    if (frame.frameNumber % 600 == 0) {
        [self->_displayLayer.sampleBufferRenderer loadVideoPerformanceMetricsWithCompletionHandler:^(AVVideoPerformanceMetrics * videoMetrics) {
            Log(LOG_I, @"AVVideoPerformanceMetrics: frames %d, dropped %d (%.1f%%), optimized %d (%.1f%%), accumulatedDelay %f",
                videoMetrics.totalNumberOfFrames, // The total number of frames that display if no frames drop.
                videoMetrics.numberOfDroppedFrames, // The total number of frames the system drops prior to decoding or from missing the display deadline
                ((double)videoMetrics.numberOfDroppedFrames / videoMetrics.totalNumberOfFrames) * 100.0,
                videoMetrics.numberOfFramesDisplayedUsingOptimizedCompositing, // The total number of full screen frames rendered in a special power-efficient mode that didn’t require compositing with other UI elements.
                ((double)videoMetrics.numberOfFramesDisplayedUsingOptimizedCompositing / videoMetrics.totalNumberOfFrames) * 100.0,
                videoMetrics.totalAccumulatedFrameDelay); // The accumulated amount of time between the prescribed presentation times of displayed video frames and their actual time of display.
        }];
    }
#endif

    if (frame.frameType == FRAME_TYPE_IDR) {
        // Ensure the layer is visible now
        self->_displayLayer.hidden = NO;

        // Tell our parent VC to hide the progress indicator
        [self->_callbacks videoContentShown];
    }
}

- (void)cleanup
{
    [_frameQueue shutdown];
    
    if (_renderingBackend == RenderingBackendAVSampleBuffer) {
        [_displayLink invalidate];
    }

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
               decodeUnit:(PDECODE_UNIT)du
          decodeStartTime:(CFTimeInterval)decodeStartTime
{
    OSStatus status;

    // Construct a new format description object each time we receive an IDR frame
    if (du->frameType == FRAME_TYPE_IDR) {
        if (bufferType != BUFFER_TYPE_PICDATA) {
            if (bufferType == BUFFER_TYPE_VPS || bufferType == BUFFER_TYPE_SPS || bufferType == BUFFER_TYPE_PPS) {
                // Add new parameter set into the parameter set array
                int startLen = data[2] == 0x01 ? 3 : 4;
                [_parameterSetBuffers addObject:[NSData dataWithBytes:&data[startLen] length:length - startLen]];
            }

            // Data is NOT to be freed here. It's a direct usage of the caller's buffer.

            // No frame data to submit for these NALUs
            return DR_OK;
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

        if (_videoFormat & VIDEO_FORMAT_MASK_H264) {
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
        else if (_videoFormat & VIDEO_FORMAT_MASK_H265) {
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
        return DR_NEED_IDR;
    }

    // Now we're decoding actual frame data here
    CMBlockBufferRef frameBlockBuffer;
    CMBlockBufferRef dataBlockBuffer;

    status = CMBlockBufferCreateWithMemoryBlock(NULL, data, length, kCFAllocatorDefault, NULL, 0, length, 0, &dataBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateWithMemoryBlock failed: %d", (int)status);
        free(data);
        return DR_NEED_IDR;
    }

    // From now on, CMBlockBuffer owns the data pointer and will free it when it's dereferenced

    status = CMBlockBufferCreateEmpty(NULL, 0, 0, &frameBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateEmpty failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        return DR_NEED_IDR;
    }

    // H.264 and HEVC formats require NAL prefix fixups from Annex B to length-delimited
    if (_videoFormat & (VIDEO_FORMAT_MASK_H264 | VIDEO_FORMAT_MASK_H265)) {
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
            return DR_NEED_IDR;
        }
    }

    // Set the current frame's pts, in RTP 90khz units. We will set the duration
    // later in FrameQueue because it requires the next frame's timestamp.
    CMSampleTimingInfo sampleTiming = {
        .duration              = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMake((int64_t)du->rtpTimestamp, 90000),
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
        return DR_NEED_IDR;
    }

    OSStatus decodeStatus = [self decodeFrameWithSampleBuffer:sampleBuffer
                                                  frameNumber:du->frameNumber
                                                    frameType:du->frameType
                                              decodeStartTime:decodeStartTime];
    // Dereference the buffers
    CFRelease(dataBlockBuffer);
    CFRelease(frameBlockBuffer);
    CFRelease(sampleBuffer);

    return DR_OK;
}

- (OSStatus)decodeFrameWithSampleBuffer:(CMSampleBufferRef)sampleBuffer
                            frameNumber:(int)frameNumber
                              frameType:(int)frameType
                        decodeStartTime:(CFTimeInterval)decodeStartTime {
  if (frameType == FRAME_TYPE_IDR || _decompressionSession == nil) {
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
            LiRequestIdrFrame();
            return;
          }

          CMSampleBufferRef sampleBufferOut = nil;
          CVPixelBufferRef pixelBuffer = nil;

          // AVSampleBuffer path: package into a SampleBuffer
          if (self->_renderingBackend == RenderingBackendAVSampleBuffer) {
            if (self->_formatDescImageBuffer == NULL || !CMVideoFormatDescriptionMatchesImageBuffer(self->_formatDescImageBuffer, imageBuffer)) {
              OSStatus res = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, imageBuffer, &(self->_formatDescImageBuffer));
              if (res != noErr) {
                Log(LOG_E, @"Failed to create video format description from imageBuffer");
                return;
              }
            }

            if (self->_formatDescImageBuffer == NULL || !CMVideoFormatDescriptionMatchesImageBuffer(self->_formatDescImageBuffer, imageBuffer)) {
              OSStatus res = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, imageBuffer, &(self->_formatDescImageBuffer));
              if (res != noErr) {
                Log(LOG_E, @"Failed to create video format description from imageBuffer");
                return;
              }
            }

            CMSampleTimingInfo sampleTiming = {kCMTimeInvalid, presentationTimestamp, presentationDuration};

            OSStatus err =
                CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, imageBuffer, self->_formatDescImageBuffer, &sampleTiming, &sampleBufferOut);
            if (err != noErr) {
              Log(LOG_E, @"Error creating sample buffer for decompressed image buffer %d", (int)err);
              return;
            }
          } else if (self->_renderingBackend == RenderingBackendMetal) {
            // Metal path: retain the pixelBuffer here so it survives the dispatch
            pixelBuffer = CVPixelBufferRetain((CVPixelBufferRef)imageBuffer);
          }

          // Dispatch onto our higher priority queue
          dispatch_async(self->_vtq, ^{
              Frame *frame = nil;
              if (self->_renderingBackend == RenderingBackendAVSampleBuffer) {
                frame = [[Frame alloc] initWithSampleBuffer:sampleBufferOut frameNumber:frameNumber frameType:frameType];
              } else {
                frame = [[Frame alloc] initWithPixelBufffer:pixelBuffer frameNumber:frameNumber frameType:frameType pts:presentationTimestamp];
                [frame setFormatDesc:self->_formatDesc];
              }
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
    SS_HDR_METADATA hdrMetadata;

    BOOL hasMetadata = enabled && LiGetHdrMetadata(&hdrMetadata);
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
        LiRequestIdrFrame();
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
    if (_renderingBackend == RenderingBackendMetal) {
        float edrHeadroom = [[UIScreen mainScreen] currentEDRHeadroom];
        UIScreenReferenceDisplayModeStatus referenceStatus = [[UIScreen mainScreen] referenceDisplayModeStatus];
        if (edrHeadroom > 1.0) {
            NSString *ref;
            // Device has a reference display that may or may not be enabled
            switch (referenceStatus) {
            case UIScreenReferenceDisplayModeStatusLimited:
                ref = @"(Reference mode limited),";
                break;
            case UIScreenReferenceDisplayModeStatusEnabled:
                ref = @"(Reference mode),";
                break;
            default:
                ref = @",";
                break;
            }
            int peakNits = 1000;
            stats->renderingBackendString = [NSString stringWithFormat:@"Metal, EDR %.1f %@ tone-mapped: %d nits",
                                             edrHeadroom, ref, peakNits];
        } else {
            // if HDR
            stats->renderingBackendString = [NSString stringWithFormat:@"Metal, tone-mapped: HDR->sRGB"];
        }
    } else {
        stats->renderingBackendString = @"AVSampleBuffer";
    }

    dispatch_sync(_sq, ^{
        memcpy(&stats->decodeMetrics, &_decodeMetrics, sizeof(PlotMetrics));
        memcpy(&stats->frameQueueMetrics, &_frameQueueMetrics, sizeof(PlotMetrics));
        [_frameQueue.frameDropMetrics copyMetrics:&stats->frameDropMetrics];
    });
}

// When streaming lower framerate content on a ProMotion display, the screen refresh rate can be
// reduced, optimizing battery life. Not currently used, it doesn't seem as reliable as I'd like.
- (void)optimizeRefreshRate {
    static NSArray<NSNumber *> *supportedRates;
    static dispatch_once_t onceToken;
    static int lastTargetRate = 0;
    int targetRate = (int)_maxRefreshRate;

    if (_maxRefreshRate <= 60 || _maxRefreshRate == 90) {
        return;
    }

    dispatch_once(&onceToken, ^{
        // https://developer.apple.com/documentation/quartzcore/optimizing-promotion-refresh-rates-for-iphone-13-pro-and-ipad-pro?language=objc
        UIDevice *device = [UIDevice currentDevice];
        if (device.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            supportedRates = @[@24, @30, @40, @60, @120];
        }
        else if (device.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
            supportedRates = @[@10, @12, @15, @16, @20, @24, @30, @40, @48, @60, @80, @120];
        }
        else {
            supportedRates = @[@30, @60];
        }
    });

    CFTimeInterval streamFps = [_frameQueue estimatedFramerate];
    if (streamFps > _maxRefreshRate) {
        streamFps = _maxRefreshRate;
    }

    for (NSNumber *r in supportedRates) {
        NSInteger rate = r.integerValue;
        if (rate >= (int)streamFps) {
            targetRate = (int)rate;
            break;
        }
    }

    if (targetRate == lastTargetRate) {
        return;
    }
    lastTargetRate = targetRate;

    Log(LOG_I, @"optimizeRefreshRate: new rate %d Hz based on streamFps of %.2f fps", targetRate, streamFps);

    _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(targetRate, _maxRefreshRate, targetRate);
}

@end

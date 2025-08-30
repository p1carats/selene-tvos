//
//  VideoDecoderRenderer.h
//  Selene
//
//  Created by Cameron Gutman on 18/10/2014.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;
@import AVFoundation;
@import UIKit;

#import "Plot.h"

NS_ASSUME_NONNULL_BEGIN

@class StreamDecodeUnit;

@protocol ConnectionCallbacks;

@interface VideoDecoderRenderer : NSObject

@property (atomic, readonly) PlotMetrics decodeMetrics;
@property (atomic, readonly) PlotMetrics frameQueueMetrics;

- (instancetype)initWithView:(UIView*)view callbacks:(id<ConnectionCallbacks>)callbacks streamAspectRatio:(float)aspectRatio;

- (void)setupWithVideoFormat:(int)videoFormat width:(int)videoWidth height:(int)videoHeight frameRate:(int)frameRate;
- (void)cleanup;
- (void)setHdrMode:(BOOL)enabled;
- (void)safeCopyMetricsTo:(PlotMetrics *)dst from:(PlotMetrics *)src;
- (void)getAllStats:(VideoStats *)stats;

- (int)submitDecodeBuffer:(unsigned char *)data
                   length:(int)length
               bufferType:(int)bufferType
               decodeUnit:(StreamDecodeUnit*)du
          decodeStartTime:(CFTimeInterval)decodeStartTime;

- (OSStatus)decodeFrameWithSampleBuffer:(CMSampleBufferRef)sampleBuffer
                            frameNumber:(int)frameNumber
                              frameType:(int)frameType
                        decodeStartTime:(CFTimeInterval)decodeStartTime;

@end

NS_ASSUME_NONNULL_END

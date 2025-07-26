//
//  Connection.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import Foundation;

#import "ConnectionCallbacks.h"
#import "Plot.h"

NS_ASSUME_NONNULL_BEGIN

@class BandwidthTracker;
@class StreamConfiguration;
@class VideoDecoderRenderer;

#define CONN_TEST_SERVER "ios.conntest.moonlight-stream.org"

@interface Connection : NSOperation <NSStreamDelegate>

-(instancetype) initWithConfig:(StreamConfiguration*)config renderer:(VideoDecoderRenderer*)myRenderer connectionCallbacks:(id<ConnectionCallbacks>)callbacks;
-(void) terminate;
-(void) main;
-(BandwidthTracker *) getBwTracker;
-(BOOL) getVideoStats:(VideoStats*)stats;
-(NSString*) getActiveCodecName;

@end

NS_ASSUME_NONNULL_END

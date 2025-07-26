//
//  StreamManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@class StreamConfiguration;

@protocol ConnectionCallbacks;

@interface StreamManager : NSOperation

- (instancetype) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view connectionCallbacks:(id<ConnectionCallbacks>)callback;

- (void) stopStream;

- (NSString*) getStatsOverlayText;

@end

NS_ASSUME_NONNULL_END

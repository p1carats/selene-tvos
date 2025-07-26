//
//  DiscoveryWorker.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/2/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@class TemporaryHost;

@interface DiscoveryWorker : NSOperation

- (instancetype) initWithHost:(TemporaryHost*)host uniqueId:(NSString*)uniqueId;
- (void) discoverHost;
- (TemporaryHost*) getHost;

@end

NS_ASSUME_NONNULL_END

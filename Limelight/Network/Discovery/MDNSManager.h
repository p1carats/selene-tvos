//
//  MDNSManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/14/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@class TemporaryHost;

@protocol MDNSCallback <NSObject>

- (void) updateHost:(TemporaryHost*)host;

@end

@interface MDNSManager : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>

@property id<MDNSCallback> callback;

- (instancetype) initWithCallback:(id<MDNSCallback>) callback;
- (void) searchForHosts;
- (void) stopSearching;
- (void) forgetHosts;

@end

NS_ASSUME_NONNULL_END


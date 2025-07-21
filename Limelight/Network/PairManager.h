//
//  PairManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import Foundation;

@class HttpManager;

@protocol PairCallback <NSObject>

- (void) startPairing:(NSString*)PIN;
- (void) pairSuccessful:(NSData*)serverCert;
- (void) pairFailed:(NSString*)message;
- (void) alreadyPaired;

@end

@interface PairManager : NSOperation
- (instancetype) initWithManager:(HttpManager*)httpManager clientCert:(NSData*)clientCert callback:(id<PairCallback>)callback;
@end

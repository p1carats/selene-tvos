//
//  HttpManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/16/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class StreamConfiguration;
@class TemporaryHost;

@interface HttpManager : NSObject <NSURLSessionDelegate>

- (instancetype) initWithHost:(TemporaryHost*) host;
- (instancetype) initWithAddress:(NSString*) hostAddressPortString httpsPort:(unsigned short) httpsPort serverCert:(nullable NSData*) serverCert;
- (void) setServerCert:(nullable NSData*) serverCert;
- (nullable NSURLRequest*) newPairRequest:(NSData*)salt clientCert:(NSData*)clientCert;
- (nullable NSURLRequest*) newUnpairRequest;
- (nullable NSURLRequest*) newChallengeRequest:(NSData*)challenge;
- (nullable NSURLRequest*) newChallengeRespRequest:(NSData*)challengeResp;
- (nullable NSURLRequest*) newClientSecretRespRequest:(NSString*)clientPairSecret;
- (nullable NSURLRequest*) newPairChallenge;
- (nullable NSURLRequest*) newAppListRequest;
- (nullable NSURLRequest*) newServerInfoRequest:(bool)fastFail;
- (nullable NSURLRequest*) newHttpServerInfoRequest:(bool)fastFail;
- (nullable NSURLRequest*) newHttpServerInfoRequest;
- (nullable NSURLRequest*) newLaunchOrResumeRequest:(NSString*)verb config:(StreamConfiguration*)config;
- (nullable NSURLRequest*) newQuitAppRequest;
- (nullable NSURLRequest*) newAppAssetRequestWithAppId:(NSString*)appId;
- (void) executeRequestSynchronously:(HttpRequest*)request;

@end

NS_ASSUME_NONNULL_END


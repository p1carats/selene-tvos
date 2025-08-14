//
//  HttpRequest.h
//  Moonlight
//
//  Created by Diego Waxemberg on 2/1/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

@import Foundation;

#import "HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpRequest : NSObject

@property (nonatomic) id<Response> response;
@property (nonatomic) NSURLRequest* request;
@property (nonatomic) int fallbackError;
@property (nonatomic, nullable) NSURLRequest* fallbackRequest;

+ (instancetype) requestForResponse:(id<Response>)response withUrlRequest:(nullable NSURLRequest*)req fallbackError:(int)error fallbackRequest:(nullable NSURLRequest*) fallbackReq;
+ (instancetype) requestForResponse:(id<Response>)response withUrlRequest:(nullable NSURLRequest*)req;
+ (instancetype) requestWithUrlRequest:(nullable NSURLRequest*)req;

@end

NS_ASSUME_NONNULL_END

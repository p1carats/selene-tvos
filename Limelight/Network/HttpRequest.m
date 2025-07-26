//
//  HttpRequest.m
//  Moonlight
//
//  Created by Diego Waxemberg on 2/1/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "HttpRequest.h"

@implementation HttpRequest

+ (HttpRequest*) requestForResponse:(id<Response>)response withUrlRequest:(NSURLRequest*)req {
    HttpRequest* request = [[HttpRequest alloc] init];
    request.request = req;
    request.response = response;
    return request;
}

+ (HttpRequest*) requestWithUrlRequest:(NSURLRequest*)req {
    HttpRequest* request = [[HttpRequest alloc] init];
    request.request = req;
    return request;
}

+ (HttpRequest*) requestForResponse:(id<Response>)response withUrlRequest:(nullable NSURLRequest*)req fallbackError:(int)error fallbackRequest:(nullable NSURLRequest*) fallbackReq {
    HttpRequest* request = [[HttpRequest alloc] init];
    request.request = req;
    request.response = response;
    request.fallbackError = error;
    request.fallbackRequest = fallbackReq;
    return request;
}

@end

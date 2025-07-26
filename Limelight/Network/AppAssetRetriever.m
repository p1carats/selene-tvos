//
//  AppAssetRetriever.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/31/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "AppAssetRetriever.h"
#import "HttpManager.h"
#import "AppAssetManager.h"
#import "AppAssetResponse.h"
#import "HttpRequest.h"
#import "TemporaryApp.h"

@implementation AppAssetRetriever
static const double RETRY_DELAY = 2; // seconds
static const int MAX_ATTEMPTS = 5;

- (void) main {
    int attempts = 0;
    while (![self isCancelled] && attempts++ < MAX_ATTEMPTS) {
        HttpManager* hMan = [[HttpManager alloc] initWithHost:_host];
        AppAssetResponse* appAssetResp = [[AppAssetResponse alloc] init];
        [hMan executeRequestSynchronously:[HttpRequest requestForResponse:appAssetResp withUrlRequest:[hMan newAppAssetRequestWithAppId:self.app.id]]];

        if (appAssetResp.data != nil) {
            NSString* boxArtPath = [AppAssetManager boxArtPathForApp:self.app];
            [[NSFileManager defaultManager] createDirectoryAtPath:[boxArtPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            [appAssetResp.data writeToFile:boxArtPath atomically:NO];
            break;
        }
        
        if (![self isCancelled]) {
            [NSThread sleepForTimeInterval:RETRY_DELAY];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self sendCallbackForApp:self.app];
    });
}

- (void) sendCallbackForApp:(TemporaryApp*)app {
    [self.callback receivedAssetForApp:app];
}

@end

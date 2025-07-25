//
//  ConnectionHelper.m
//  Moonlight macOS
//
//  Created by Felix Kratz on 22.03.18.
//  Copyright © 2018 Felix Kratz. All rights reserved.
//

#import "ConnectionHelper.h"
#import "AppListResponse.h"
#import "HttpManager.h"
#import "HttpRequest.h"
#import "Logger.h"

@implementation ConnectionHelper

+(AppListResponse*) getAppListForHost:(TemporaryHost*)host {
    HttpManager* hMan = [[HttpManager alloc] initWithHost:host];
    
    // Try up to 5 times to get the app list
    AppListResponse* appListResp = nil;
    for (int i = 0; i < 5; i++) {
        appListResp = [[AppListResponse alloc] init];
        [hMan executeRequestSynchronously:[HttpRequest requestForResponse:appListResp withUrlRequest:[hMan newAppListRequest]]];
        if (![appListResp isStatusOk] || [appListResp getAppList] == nil) {
            Log(LOG_W, @"Failed to get applist on try %d: %@", i, appListResp.statusMessage);
            
            // Wait for one second then retry
            [NSThread sleepForTimeInterval:1];
        }
        else {
            Log(LOG_I, @"App list successfully retreived - took %d tries", i);
            break;
        }
    }
    
    return appListResp;
}

@end


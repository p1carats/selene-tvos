//
//  AppListResponse.h
//  Moonlight
//
//  Created by Diego Waxemberg on 2/1/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

@import Foundation;

#import "HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppListResponse : NSObject <Response>

- (void)populateWithData:(NSData *)data;
- (NSSet*) getAppList;
- (BOOL) isStatusOk;

@end

NS_ASSUME_NONNULL_END

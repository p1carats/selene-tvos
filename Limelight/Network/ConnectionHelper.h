//
//  ConnectionHelper.h
//  Moonlight macOS
//
//  Created by Felix Kratz on 22.03.18.
//  Copyright © 2018 Felix Kratz. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@class TemporaryHost;
@class AppListResponse;

@interface ConnectionHelper : NSObject

+(AppListResponse*) getAppListForHost:(TemporaryHost*)host;

@end

NS_ASSUME_NONNULL_END

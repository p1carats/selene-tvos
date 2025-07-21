//
//  ConnectionHelper.h
//  Moonlight macOS
//
//  Created by Felix Kratz on 22.03.18.
//  Copyright © 2018 Felix Kratz. All rights reserved.
//

@import Foundation;

#import "AppListResponse.h"

@class TemporaryHost;

@interface ConnectionHelper : NSObject

+(AppListResponse*) getAppListForHost:(TemporaryHost*)host;

@end

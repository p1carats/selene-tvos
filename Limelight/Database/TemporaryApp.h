//
//  TemporaryApp.h
//  Moonlight
//
//  Created by Cameron Gutman on 9/30/15.
//  Copyright © 2015 Moonlight Stream. All rights reserved.
//

@import Foundation;

#import "App+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

@class TemporaryHost;

@interface TemporaryApp : NSObject

@property (nullable, nonatomic, strong) NSString *id;
@property (nullable, nonatomic, strong) NSString *name;
@property (nullable, nonatomic, strong) NSString *installPath;
@property (nonatomic) BOOL hdrSupported;
@property (nonatomic) BOOL hidden;
@property (nullable, nonatomic, strong) TemporaryHost *host;

- (instancetype) initFromApp:(App*)app withTempHost:(TemporaryHost*)tempHost;

- (NSComparisonResult)compareName:(TemporaryApp *)other;

- (void) propagateChangesToParent:(App*)parent withHost:(Host*)host;

@end

NS_ASSUME_NONNULL_END

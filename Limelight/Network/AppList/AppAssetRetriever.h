//
//  AppAssetRetriever.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/31/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@class TemporaryApp;
@class TemporaryHost;

@protocol AppAssetCallback;

@interface AppAssetRetriever : NSOperation

@property (nonatomic) TemporaryHost* host;
@property (nonatomic) TemporaryApp* app;
@property (nonatomic) id<AppAssetCallback> callback;

@end

NS_ASSUME_NONNULL_END

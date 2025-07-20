//
//  PlotManager.h
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@class PlotDefinition;

struct PlotMetrics;

@interface PlotManager : NSObject

@property (nonatomic, strong, readonly) NSArray<PlotDefinition *> *plots;

+ (instancetype _Nonnull)sharedInstance;
- (void)observeFloat:(int)plotId value:(CFTimeInterval)value;
- (void)observeFloatReturnMetrics:(int)plotId value:(CFTimeInterval)value plotMetrics:(nullable struct PlotMetrics *)plotMetrics;

@end

NS_ASSUME_NONNULL_END

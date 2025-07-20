//
//  GraphRenderer.h
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@class PlotDefinition;

struct PlotMetrics;

typedef void (^MetricsHandler)(int plotId, CFTimeInterval value);

@interface GraphRenderer : UIViewController

@property (nonatomic, readonly) BOOL enableGraphs;
@property (nonatomic, readonly) float graphOpacity;
@property (nonatomic, readonly) CGRect bounds;
@property (nonatomic, readonly) NSArray<PlotDefinition *> *plots;
@property (nonatomic, copy, nullable) MetricsHandler metricsHandler;

- (nonnull instancetype)initWithFrame:(CGRect)bounds
                           streamFps:(int)streamFps
                        enableGraphs:(BOOL)enableGraphs
                        graphOpacity:(int)graphOpacity;

- (void)start;
- (void)stop;
- (void)show;
- (void)hide;

- (void)observeFloat:(int)plotId value:(CFTimeInterval)value;
- (void)observeFloatReturnMetrics:(int)plotId value:(CFTimeInterval)value plotMetrics:(nullable struct PlotMetrics *)plotMetrics;

@end

NS_ASSUME_NONNULL_END

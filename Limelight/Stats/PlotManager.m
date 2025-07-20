//
//  PlotManager.m
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

#import "PlotManager.h"
#import "PlotDefinition.h"
#import "FloatBuffer.h"
#import "Plot.h"

@implementation PlotManager

+ (instancetype)sharedInstance {
    static PlotManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSMutableArray<PlotDefinition *> *plotArray = [NSMutableArray arrayWithCapacity:PlotTypeCount];
        
        // Initialize PlotTypeFrametime
        PlotDefinition *frametimePlot = [[PlotDefinition alloc] initWithTitle:@"Frametime"
                                                                         unit:@"ms"
                                                                         side:PlotSideLeft
                                                                    labelType:PlotLabelTypeMinMaxAverage
                                                                     scaleMin:(1000.0 / 120) - 1
                                                                     scaleMax:50.0f
                                                                  scaleTarget:0];
        [plotArray addObject:frametimePlot];
        
        // Initialize PlotTypeHostFrametime
        PlotDefinition *hostFrametimePlot = [[PlotDefinition alloc] initWithTitle:@"Host Frametime"
                                                                             unit:@"ms"
                                                                             side:PlotSideLeft
                                                                        labelType:PlotLabelTypeMinMaxAverage
                                                                         scaleMin:(1000.0 / 120) - 1
                                                                         scaleMax:50.0f
                                                                      scaleTarget:0];
        [plotArray addObject:hostFrametimePlot];
        
        // Initialize PlotTypeQueuedFrames
        PlotDefinition *queuedFramesPlot = [[PlotDefinition alloc] initWithTitle:@"Frame queue"
                                                                            unit:@""
                                                                            side:PlotSideRight
                                                                       labelType:PlotLabelTypeMinMaxAverageInt
                                                                        scaleMin:-0.5
                                                                        scaleMax:15
                                                                     scaleTarget:0];
        [plotArray addObject:queuedFramesPlot];
        
        // Initialize PlotTypeDropped
        PlotDefinition *droppedPlot = [[PlotDefinition alloc] initWithTitle:@"Frames dropped"
                                                                       unit:@""
                                                                       side:PlotSideRight
                                                                  labelType:PlotLabelTypeTotalInt
                                                                   scaleMin:0
                                                                   scaleMax:0
                                                                scaleTarget:2];
        [plotArray addObject:droppedPlot];
        
        // Initialize PlotTypeDecode
        PlotDefinition *decodePlot = [[PlotDefinition alloc] initWithTitle:@"Decode time"
                                                                      unit:@"ms"
                                                                      side:PlotSideHidden
                                                                 labelType:PlotLabelTypeMinMaxAverage
                                                                  scaleMin:0
                                                                  scaleMax:0
                                                               scaleTarget:0];
        [plotArray addObject:decodePlot];
        
        _plots = [plotArray copy];
    }
    return self;
}

- (void)observeFloat:(int)plotId value:(CFTimeInterval)value {
    if (plotId >= 0 && plotId < self.plots.count) {
        [self.plots[plotId].buffer addValue:(float)value];
    }
}

- (void)observeFloatReturnMetrics:(int)plotId value:(CFTimeInterval)value plotMetrics:(struct PlotMetrics *)plotMetrics {
    if (plotId >= 0 && plotId < self.plots.count) {
        [self.plots[plotId].buffer addValue:(float)value];
        if (plotMetrics != nil) {
            [self.plots[plotId].buffer copyMetrics:(PlotMetrics *)plotMetrics];
        }
    }
}

@end

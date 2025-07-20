//
//  Plot.h
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FramePacingMode) {
    FramePacingModeVSync = 0,
    FramePacingModePTS
};

typedef NS_ENUM(NSInteger, PlotType) {
    PlotTypeFrametime = 0,
    PlotTypeHostFrametime,
    PlotTypeQueuedFrames,
    PlotTypeDropped,
    PlotTypeDecode,
    PlotTypeCount
};

typedef NS_ENUM(NSInteger, PlotLabelType) {
    PlotLabelTypeMinMaxAverage = 0,
    PlotLabelTypeMinMaxAverageInt,
    PlotLabelTypeTotalInt
};

typedef NS_ENUM(NSInteger, PlotSide) {
    PlotSideHidden = 0,
    PlotSideLeft,
    PlotSideRight
};

typedef struct {
    float min;
    float max;
    float avg;
    float total;
    int nsamples;
    float samplerate;
} PlotMetrics;

typedef NS_ENUM(NSInteger, RenderingBackend) {
    RenderingBackendMetal = 0,
    RenderingBackendAVSampleBuffer
};

typedef struct {
    CFTimeInterval startTime;
    CFTimeInterval endTime;
    int totalFrames;
    int receivedFrames;
    int networkDroppedFrames;
    int totalHostProcessingLatency;
    int framesWithHostProcessingLatency;
    int maxHostProcessingLatency;
    int minHostProcessingLatency;
    PlotMetrics decodeMetrics;
    PlotMetrics frameQueueMetrics;
    PlotMetrics frameDropMetrics;
    NSString *renderingBackendString;
} VideoStats;

NS_ASSUME_NONNULL_END

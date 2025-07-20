//
//  GraphRenderer.m
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

#import "GraphRenderer.h"
#import "Plot.h"
#import "GraphView.h"
#import "PlotManager.h"
#import "PlotDefinition.h"
#import "Logger.h"
#import "FloatBuffer.h"

@interface GraphRenderer ()
@property (nonatomic, readwrite) BOOL enableGraphs;
@property (nonatomic, readwrite) float graphOpacity;
@property (nonatomic, readwrite) CGRect bounds;
@property (nonatomic, readwrite) NSArray<PlotDefinition *> *plots;
@property (nonatomic, strong) NSMutableArray<GraphView *> *leftGraphViews;
@property (nonatomic, strong) NSMutableArray<GraphView *> *rightGraphViews;
@property (nonatomic, strong) UIView *leftContainer;
@property (nonatomic, strong) UIView *rightContainer;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) int streamFps;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) float *graphDataBuffer;
@property (nonatomic, assign) int graphDataBufferSize;
@end

@implementation GraphRenderer

- (nonnull instancetype)initWithFrame:(CGRect)bounds
                           streamFps:(int)streamFps
                        enableGraphs:(BOOL)enableGraphs
                        graphOpacity:(int)graphOpacity {
    self = [super init];
    if (self) {
        _enableGraphs = enableGraphs;
        _graphOpacity = (float)(graphOpacity / 100.0);
        _bounds = bounds;
        _streamFps = streamFps;
        _plots = [PlotManager sharedInstance].plots;
        _leftGraphViews = [NSMutableArray array];
        _rightGraphViews = [NSMutableArray array];
        _isRunning = NO;
        
        // Set up the metrics handler to forward to our observeFloat method
        __weak typeof(self) weakSelf = self;
        _metricsHandler = ^(int plotId, CFTimeInterval value) {
            [weakSelf observeFloat:plotId value:value];
        };
    }
    return self;
}

- (void)dealloc {
    [self stop];
    if (_graphDataBuffer) {
        free(_graphDataBuffer);
        _graphDataBuffer = NULL;
    }
}

- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:self.bounds];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.userInteractionEnabled = NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupGraphViews];
    
    if (self.enableGraphs) {
        [self start];
    }
}

- (void)setupGraphViews {
    // Calculate graph dimensions based on screen size
    CGSize screenSize = self.bounds.size;
    float graphW = 0.0f;
    float graphH = 0.0f;
    
    // Sizing logic
    switch ((int)screenSize.width) {
        case 1920: // ATV 4K 1920x1080 2x
            graphW = 525.0f; graphH = 80.0f; break;
        default:
            graphW = screenSize.width * 0.327f;
            graphH = screenSize.height * 0.044f;
    }
    
    LogOnce(LOG_I, @"Creating graphs of size %.1f x %.1f in viewport %.1f x %.1f using opacity %.2f",
            graphW, graphH, screenSize.width, screenSize.height, self.graphOpacity);
    
    // Create left container
    self.leftContainer = [[UIView alloc] initWithFrame:CGRectMake(10, 10, graphW, graphH * 4)];
    self.leftContainer.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.leftContainer];
    
    // Create right container
    self.rightContainer = [[UIView alloc] initWithFrame:CGRectMake(screenSize.width - graphW - 10, 10, graphW, graphH * 4)];
    self.rightContainer.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.rightContainer];
    
    // Create graph views for each plot
    int leftIndex = 0;
    int rightIndex = 0;
    
    for (int i = 0; i < PlotTypeCount; i++) {
        if (self.plots[i].side == PlotSideLeft) {
            GraphView *graphView = [[GraphView alloc] initWithFrame:CGRectMake(0, leftIndex * graphH, graphW, graphH)];
            [self configureGraphView:graphView forPlot:i];
            [self.leftContainer addSubview:graphView];
            [self.leftGraphViews addObject:graphView];
            leftIndex++;
        } else if (self.plots[i].side == PlotSideRight) {
            GraphView *graphView = [[GraphView alloc] initWithFrame:CGRectMake(0, rightIndex * graphH, graphW, graphH)];
            [self configureGraphView:graphView forPlot:i];
            [self.rightContainer addSubview:graphView];
            [self.rightGraphViews addObject:graphView];
            rightIndex++;
        }
    }
}

- (void)configureGraphView:(GraphView *)graphView forPlot:(int)plotIndex {
    PlotDefinition *plot = self.plots[plotIndex];
    
    graphView.title = plot.title;
    graphView.unit = plot.unit;
    graphView.labelType = plot.labelType;
    graphView.scaleMin = plot.scaleMin;
    graphView.scaleMax = plot.scaleMax;
    graphView.scaleTarget = plot.scaleTarget;
    graphView.opacity = self.graphOpacity;
}

- (void)start {
    if (!self.enableGraphs || self.isRunning) return;
    
    self.isRunning = YES;
    self.view.hidden = NO;
    
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(refreshGraphs)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

}

- (void)stop {
    if (!self.isRunning) return;
    
    self.isRunning = NO;
    [self.displayLink invalidate];
    self.displayLink = nil;
    self.view.hidden = YES;
}

- (void)show {
    self.view.hidden = NO;
}

- (void)hide {
    self.view.hidden = YES;
}

- (void)refreshGraphs {
    if (!self.enableGraphs || !self.isRunning) return;
    
    // Allocate buffer for graph data
    static float *buffer = NULL;
    static int bufferSize = 0;
    
    if (buffer == NULL) {
        bufferSize = 512;
        buffer = (float *)malloc(sizeof(float) * bufferSize);
    }
    
    // Update left graphs
    int leftIndex = 0;
    for (int i = 0; i < PlotTypeCount; i++) {
        if (self.plots[i].side == PlotSideLeft && leftIndex < self.leftGraphViews.count) {
            [self updateGraphView:self.leftGraphViews[leftIndex] withPlot:i buffer:buffer];
            leftIndex++;
        }
    }
    
    // Update right graphs
    int rightIndex = 0;
    for (int i = 0; i < PlotTypeCount; i++) {
        if (self.plots[i].side == PlotSideRight && rightIndex < self.rightGraphViews.count) {
            [self updateGraphView:self.rightGraphViews[rightIndex] withPlot:i buffer:buffer];
            rightIndex++;
        }
    }
}

- (void)updateGraphView:(GraphView *)graphView withPlot:(int)plotIndex buffer:(float *)buffer {
    PlotDefinition *plot = self.plots[plotIndex];
    
    float minY, maxY;
    int count = [plot.buffer copyValuesIntoBuffer:buffer min:&minY max:&maxY];
    
    if (count > 0) {
        float avgY = [plot.buffer averageValue];
        float total = [plot.buffer total];
        
        [graphView updateWithValues:buffer
                              count:count
                            minimum:minY
                            maximum:maxY
                            average:avgY
                              total:total];
    }
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

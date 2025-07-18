/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The implementation of the cross-platform game view controller.
*/

#import "MetalViewController.h"
#import "FrameQueue.h"
#import "MetalVideoRenderer.h"
#import "Logger.h"

@implementation MetalViewController {
    /// A queue to initialize the renderer asynchronously from the main thread.
    dispatch_queue_t _dispatch_queue;
    FrameQueue *_frameQueue;
    float _framerate;
    BOOL _enableHdr;
    MetalView *_metalView;
    MetalVideoRenderer *_renderer;
    MetricsHandler _metricsHandler;
    BOOL _stopping;
}

- (nonnull instancetype)initWithFrame:(CGRect)bounds framerate:(float)framerate enableHdr:(BOOL)enableHdr metricsHandler:(MetricsHandler)metricsHandler {
    self = [super init];
    if (self) {
        _bounds = bounds;
        _frameQueue = [FrameQueue sharedInstance];
        _framerate = framerate;
        _enableHdr = enableHdr;
        _metricsHandler = metricsHandler;
        _stopping = NO;
    }
    return self;
}

- (void)loadView {
    self.view = [[MetalView alloc] initWithFrame:_bounds];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    /// A queue to initialize the renderer asynchronously from the main thread.
    _dispatch_queue = dispatch_queue_create("com.moonlight.Metal", DISPATCH_QUEUE_CONCURRENT);

    __block MetalView *view = (MetalView *)self.view;
    if (!view) {
        Log(LOG_E, @"The view attached to MetalViewController isn't a MetalView.");
        return;
    }
    _metalView = view;
    _metalView.delegate = self;
    _metalView.framerate = _framerate;

    // Select the device to render with.
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        Log(LOG_E, @"Metal isn't supported on this device.");
        self.view = [[UIView alloc] initWithFrame:self.view.frame];
        return;
    }
    view.metalLayer.device = device;

    // Initialize the renderer.
    MetalVideoRenderer *renderer = [[MetalVideoRenderer alloc] initWithMetalDevice:device
                                                               drawablePixelFormat:MTLPixelFormatBGR10A2Unorm
                                                                         framerate:self->_framerate];
    if (!renderer) {
        Log(LOG_E, @"The renderer couldn't be initialized.");
        return;
    }

    // Initialize the renderer-dependent view properties.
    view.metalLayer.pixelFormat = renderer.colorPixelFormat;
    view.metalLayer.colorspace = renderer.colorspace;
    view.metalLayer.maximumDrawableCount = 3;

    self->_renderer = renderer;
}

- (void)waitToRenderTo:(nonnull CAMetalLayer *)layer {
    if (!_stopping) {
        // Renderer obtains a nextDrawable, waiting if necessary
        [_renderer waitToRenderTo:layer];

        // If we don't have a frame yet, wait on that too
        [_frameQueue waitForEnqueue];
    }
}

/// Draw frame (used by manual loop)
- (void)renderTo:(nonnull CAMetalLayer *)layer {
    if (!_renderer) {
        return;
    }

    CFTimeInterval timeout = (1.0f / _framerate) - _renderer.averageGPUTime;
    Frame *frame = [_frameQueue dequeueWithTimeout:timeout];
    if (frame) {
        [_renderer renderFrame:frame toLayer:layer];
    }
}

- (void)drawableResize:(CGSize)size {
    [_renderer drawableResize:size];
}

@end

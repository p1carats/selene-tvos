// This is based on the following Apple example:
// https://developer.apple.com/documentation/metal/achieving-smooth-frame-rates-with-a-metal-display-link?language=objc
// https://developer.apple.com/wwdc23/10123/

#import "MetalView.h"
#import "Logger.h"

@implementation MetalView {
    // The secondary thread containing the render loop.
    NSThread *_renderThread;

    // The flag to indicate that rendering needs to cease on the main thread.
    BOOL _continueRunLoop;
}

#pragma mark - Initialization and Setup.

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self initCommon];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initCommon];
    }
    return self;
}

- (void)initCommon {
    _metalLayer = (CAMetalLayer *)self.layer;

    self.layer.delegate = self;
}

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (void)didMoveToWindow {
    [self movedToWindow];
}

- (void)movedToWindow {
    // Protect _continueRunLoop with a `@synchronized` block because it's accessed by the separate
    // animation thread.
    @synchronized(self) {
        // Stop the animation loop, allowing it to complete if it's in progress.
        _continueRunLoop = NO;
    }

    // Create and start a secondary NSThread that has another runloop. The NSThread
    // class calls the 'runThread' method at the start of the secondary thread's execution.
    _renderThread = [[NSThread alloc] initWithTarget:self selector:@selector(runThread) object:nil];
    _renderThread.name = @"MetalVideoRenderer";
    _continueRunLoop = YES;
    _renderThread.qualityOfService = NSQualityOfServiceUserInteractive;
    [_renderThread start];

    // Perform any actions that need to know the size and scale of the drawable. When UIKit calls
    // didMoveToWindow after the view initialization, this is the first opportunity to notify
    // components of the drawable's size.
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)runThread {
    // The system sets the '_continueRunLoop' ivar outside this thread, so it needs to synchronize. Create a
    // 'continueRunLoop' local var that the system can set from the _continueRunLoop ivar in a @synchronized block.
    BOOL continueRunLoop = YES;

    // Begin the run loop.
    while (continueRunLoop) {
        @autoreleasepool {
            [_delegate waitToRenderTo:_metalLayer];

            @synchronized(self) {
                continueRunLoop = _continueRunLoop;
            }
            if (!continueRunLoop) {
                break;
            }

            [_delegate renderTo:_metalLayer];

            @synchronized(self) {
                continueRunLoop = _continueRunLoop;
            }
        }
    }
}

#pragma mark - Resizing

// Override all methods that indicate the view's size has changed.

- (void)setContentScaleFactor:(CGFloat)contentScaleFactor {
    [super setContentScaleFactor:contentScaleFactor];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)resizeDrawable:(CGFloat)scaleFactor {
    CGSize newSize = self.bounds.size;
    newSize.width *= scaleFactor;
    newSize.height *= scaleFactor;

    if (newSize.width <= 0 || newSize.width <= 0) {
        return;
    }

    // The system calls all AppKit and UIKit calls that notify of a resize on the main thread. Use
    // a synchronized block to ensure that resize notifications on the delegate are atomic.
    @synchronized(_metalLayer) {
        if (newSize.width == _metalLayer.drawableSize.width && newSize.height == _metalLayer.drawableSize.height) {
            return;
        }

        Log(LOG_I, @"[MetalView] resizeDrawable: %.2f x %.2f", newSize.width, newSize.height);

        _metalLayer.drawableSize = newSize;

        [_delegate drawableResize:newSize];
    }
}

@end

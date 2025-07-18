@import Metal;
@import QuartzCore.CAMetalDisplayLink;
@import QuartzCore.CAMetalLayer;
@import UIKit;

// The protocol to provide resize and redraw callbacks to a delegate.
@protocol MetalViewDelegate <NSObject>

- (void)drawableResize:(CGSize)size;
- (void)renderTo:(nonnull CAMetalLayer *)layer;
- (void)waitToRenderTo:(nonnull CAMetalLayer *)layer;

@end

// The Metal game view base class.
@interface MetalView : UIView <CALayerDelegate>

@property (nonatomic, nonnull, readonly) CAMetalLayer *metalLayer;
@property (nonatomic, getter=isPaused) BOOL paused;
@property (nonatomic, nullable) id<MetalViewDelegate> delegate;
@property (nonatomic) float framerate;

- (void)initCommon;
- (void)resizeDrawable:(CGFloat)scaleFactor;

@end

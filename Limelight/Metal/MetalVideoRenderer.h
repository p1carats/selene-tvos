#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/QuartzCore.h>

#import "ConnectionCallbacks.h"
#import "Frame.h"

NS_ASSUME_NONNULL_BEGIN

@interface MetalVideoRenderer : NSObject

@property (atomic) CFTimeInterval averageGPUTime;
@property (nonatomic) NSUInteger sampleCount;
@property (nonatomic) MTLPixelFormat colorPixelFormat;
@property (nonatomic, nonnull) CGColorSpaceRef colorspace;
@property (nonatomic) id<CAMetalDrawable> _Nullable nextDrawable;

- (nonnull instancetype)initWithMetalDevice:(nonnull id<MTLDevice>)device
                        drawablePixelFormat:(MTLPixelFormat)drawablePixelFormat
                                  framerate:(float)framerate;
- (void)renderFrame:(nonnull Frame *)frame toLayer:(nonnull CAMetalLayer *)layer;
- (void)waitToRenderTo:(nonnull CAMetalLayer *)layer;
- (void)drawableResize:(CGSize)drawableSize;
- (void)plotFrametime:(CFTimeInterval)presentedTime;

@end

NS_ASSUME_NONNULL_END

@import Foundation;
@import QuartzCore.CAMetalLayer;
@import QuartzCore;
@import simd;

NS_ASSUME_NONNULL_BEGIN

@class Frame;

@protocol ConnectionCallbacks;

@interface MetalVideoRenderer : NSObject

@property (atomic) CFTimeInterval averageGPUTime;
@property (nonatomic) NSUInteger sampleCount;
@property (nonatomic) MTLPixelFormat colorPixelFormat;
@property (nonatomic) CFTimeInterval lastPresented;
@property (nonatomic) id<CAMetalDrawable> _Nullable nextDrawable;
@property (atomic) BOOL isStopping;

- (nonnull instancetype)initWithMetalDevice:(nonnull id<MTLDevice>)device drawablePixelFormat:(MTLPixelFormat)drawablePixelFormat framerate:(float)framerate;
- (void)renderFrame:(nonnull Frame *)frame toLayer:(nonnull CAMetalLayer *)layer;
- (void)waitToRenderTo:(nonnull CAMetalLayer *)layer;
- (void)drawableResize:(CGSize)drawableSize;
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END

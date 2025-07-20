#import <Metal/Metal.h>
#import "FrameQueue.h"
#import "GraphRenderer.h"
#import "MetalVideoRenderer.h"
#import "MetalView.h"

#import <UIKit/UIKit.h>

@interface MetalViewController : UIViewController <MetalViewDelegate>

@property (nonatomic) CGRect bounds;

- (nonnull instancetype)initWithFrame:(CGRect)bounds
                            framerate:(float)framerate
                            enableHdr:(BOOL)enableHdr
                       metricsHandler:(nonnull MetricsHandler)metricsHandler;

@end

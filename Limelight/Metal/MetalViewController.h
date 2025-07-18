@import Metal;
@import UIKit;

#import "GraphRenderer.h"
#import "MetalView.h"

@interface MetalViewController : UIViewController <MetalViewDelegate>

@property (nonatomic) CGRect bounds;

- (nonnull instancetype)initWithFrame:(CGRect)bounds
                            framerate:(float)framerate
                            enableHdr:(BOOL)enableHdr
                       metricsHandler:(nonnull MetricsHandler)metricsHandler;

@end

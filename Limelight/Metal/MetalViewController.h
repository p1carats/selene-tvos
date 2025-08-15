//
//  MetalViewController.h
//  Selene
//
//  Created by Andy Grundman on 03/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;
@import UIKit;

#import "GraphRenderer.h"
#import "MetalView.h"

NS_ASSUME_NONNULL_BEGIN

@interface MetalViewController : UIViewController <MetalViewDelegate>

@property (nonatomic) CGRect bounds;

- (nonnull instancetype)initWithFrame:(CGRect)bounds
                            framerate:(float)framerate
                            enableHdr:(BOOL)enableHdr
                       metricsHandler:(nonnull MetricsHandler)metricsHandler;

@end

NS_ASSUME_NONNULL_END

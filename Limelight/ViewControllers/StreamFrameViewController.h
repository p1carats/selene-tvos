//
//  StreamFrameViewController.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

@import Foundation;
@import GameController;
@import UIKit;

#import "ConnectionCallbacks.h"
#import "ControllerSupport.h"
#import "StreamView.h"

NS_ASSUME_NONNULL_BEGIN

@class StreamConfiguration;
@class MetalViewController;
@class GraphRenderer;

@interface StreamFrameViewController : GCEventViewController <ConnectionCallbacks, ControllerSupportDelegate, UserInteractionDelegate, UIScrollViewDelegate>

@property (nonatomic) StreamConfiguration* streamConfig;
@property (nonatomic, strong) MetalViewController *metalViewController;
@property (nonatomic, strong) GraphRenderer *graphRenderer;

-(void)updatePreferredDisplayMode:(BOOL)streamActive;

@end

NS_ASSUME_NONNULL_END

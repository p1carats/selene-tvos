//
//  StreamFrameViewController.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

@import Foundation;
@import UIKit;
@import GameController;

#import "ConnectionCallbacks.h"
#import "ControllerSupport.h"
#import "StreamView.h"

@class StreamConfiguration;
@class MetalViewController;
@class GraphRenderer;

@interface StreamFrameViewController : GCEventViewController <ConnectionCallbacks, ControllerSupportDelegate, UserInteractionDelegate, UIScrollViewDelegate>

@property (nonatomic) StreamConfiguration* streamConfig;
@property (nonatomic, strong) MetalViewController *metalViewController;
@property (nonatomic, strong) GraphRenderer *graphRenderer;

-(void)updatePreferredDisplayMode:(BOOL)streamActive;

@end

//
//  StreamFrameViewController.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "Connection.h"
#import "FloatBuffer.h"
#import "GraphRenderer.h"
#import "MetalViewController.h"
#import "StreamConfiguration.h"
#import "StreamView.h"

#import <UIKit/UIKit.h>

@import GameController;

@interface StreamFrameViewController : GCEventViewController <ConnectionCallbacks, ControllerSupportDelegate, UserInteractionDelegate, UIScrollViewDelegate>

@property (nonatomic) StreamConfiguration* streamConfig;
@property (nonatomic, strong) MetalViewController *metalViewController;
@property (nonatomic, strong) GraphRenderer *graphRenderer;

-(void)updatePreferredDisplayMode:(BOOL)streamActive;

@end

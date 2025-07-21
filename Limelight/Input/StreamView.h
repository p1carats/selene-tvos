//
//  StreamView.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import Foundation;
@import UIKit;

#import "Selene-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@class ControllerSupport;
@class StreamConfiguration;

@protocol UserInteractionDelegate <NSObject>

- (void) userInteractionBegan;
- (void) userInteractionEnded;

@end

@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate>

@property (nonatomic) UIResponder* touchHandler;

- (void) setupStreamView:(ControllerSupport*)controllerSupport
     interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                  config:(StreamConfiguration*)streamConfig;

@end

NS_ASSUME_NONNULL_END

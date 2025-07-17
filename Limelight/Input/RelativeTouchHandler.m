//
//  RelativeTouchHandler.m
//  Selene
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

@import UIKit.UIGestureRecognizerSubclass;
@import GameStreamKit;

#import "RelativeTouchHandler.h"

static const int REFERENCE_WIDTH = 1280;
static const int REFERENCE_HEIGHT = 720;

@implementation RelativeTouchHandler {
    UIView* view;
    BOOL isDragging;
}

- (instancetype)initWithView:(StreamView*)attachedView {
    self = [super init];
    if (self) {
        view = attachedView;
        
        //view.userInteractionEnabled = NO;

        // Pan = trackpad movement
        UIPanGestureRecognizer* panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [view addGestureRecognizer:panRecognizer];
        
        // Tap = left click
        _remotePressRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(remoteButtonPressed:)];
        _remotePressRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
        [view addGestureRecognizer:_remotePressRecognizer];
        
        // Long press = click and hold (drag)
        _remoteLongPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(remoteButtonLongPressed:)];
        _remoteLongPressRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
        [view addGestureRecognizer:_remoteLongPressRecognizer];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer*)gesture {
    CGPoint translation = [gesture translationInView:view];
    [gesture setTranslation:CGPointZero inView:view];

    int deltaX = translation.x * (REFERENCE_WIDTH / view.bounds.size.width);
    int deltaY = translation.y * (REFERENCE_HEIGHT / view.bounds.size.height);

    if (deltaX != 0 || deltaY != 0) {
        LiSendMouseMoveEvent(deltaX, deltaY);
    }

    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (!isDragging) {
            isDragging = YES;
            LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
        }
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        if (isDragging) {
            LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
            isDragging = NO;
        }
    }
}

- (void)remoteButtonPressed:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
        usleep(100 * 1000); // Simulate quick press
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    });
}

- (void)remoteButtonLongPressed:(id)sender {
    // Simulate click-and-hold
    if (!isDragging) {
        isDragging = YES;
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
    }
}

@end

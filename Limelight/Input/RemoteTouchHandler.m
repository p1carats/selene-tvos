//
//  RemoteTouchHandler.m
//  Selene
//
//  Created by Noé Barlet on 26/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import GameStreamKit;

#import "RemoteTouchHandler.h"
#import "StreamView.h"

@implementation RemoteTouchHandler {
    StreamView* view;
    BOOL isDragging; // Track if we're in drag mode (left button held down)
    int streamWidth;
    int streamHeight;
    
    // Drag mode
    BOOL hasMovedSinceDragStart;
    NSTimer* dragInactivityTimer;
    
    // Manual double-click detection for immediate single clicks
    NSTimeInterval lastClickTime;
    
    // Manual drag (long press + movement)
    BOOL isLongPressing;
    NSTimer* longPressRightClickTimer;
}

- (instancetype)initWithView:(StreamView*)attachedView streamWidth:(int)width streamHeight:(int)height {
    self = [super init];
    if (self) {
        view = attachedView;
        streamWidth = width;
        streamHeight = height;
        _mouseSensitivity = 1.0; // Default sensitivity
        isDragging = NO;
        hasMovedSinceDragStart = NO;
        dragInactivityTimer = nil;
        lastClickTime = 0;
        isLongPressing = NO;
        longPressRightClickTimer = nil;
        
        // Pan gesture for mouse movement
        UIPanGestureRecognizer* panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [view addGestureRecognizer:panRecognizer];
        
        // Immediate click = left click
        UITapGestureRecognizer* immediateClickRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleImmediateClick:)];
        immediateClickRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
        immediateClickRecognizer.numberOfTapsRequired = 1;
        [view addGestureRecognizer:immediateClickRecognizer];
        
        // Long click = right click
        UILongPressGestureRecognizer* longClickRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongClick:)];
        longClickRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
        longClickRecognizer.minimumPressDuration = 0.6; // 600ms for right click
        [view addGestureRecognizer:longClickRecognizer];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer*)gesture {
    CGPoint translation = [gesture translationInView:view];
    [gesture setTranslation:CGPointZero inView:view];

    // Apply sensitivity multiplier with normalized scaling
    // Use a reference resolution ratio (regular HD) to normalize high-res streams
    float referenceWidth = 1920.0f;
    float referenceHeight = 1080.0f;
    float scaleFactorX = (referenceWidth / view.bounds.size.width) * _mouseSensitivity;
    float scaleFactorY = (referenceHeight / view.bounds.size.height) * _mouseSensitivity;
    
    // Apply aspect ratio correction based on actual stream vs reference
    float aspectCorrection = (float)streamWidth / streamHeight / (referenceWidth / referenceHeight);
    if (aspectCorrection > 1.0f) {
        scaleFactorX *= aspectCorrection;
    } else {
        scaleFactorY /= aspectCorrection;
    }
    
    float deltaX = translation.x * scaleFactorX;
    float deltaY = translation.y * scaleFactorY;

    int intDeltaX = (int)deltaX;
    int intDeltaY = (int)deltaY;

    if (intDeltaX != 0 || intDeltaY != 0) {
        LiSendMouseMoveEvent(intDeltaX, intDeltaY);
        
        // Track movement for drag mode refinements
        if (isDragging) {
            hasMovedSinceDragStart = YES;
            [self resetDragInactivityTimer];
        } else if (isLongPressing && !hasMovedSinceDragStart) {
            // User started moving during long press - convert to manual drag
            hasMovedSinceDragStart = YES;
            [longPressRightClickTimer invalidate]; // Cancel right click
            longPressRightClickTimer = nil;
            
            // Start manual drag
            isDragging = YES;
            LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
        }
    }
}

- (void)handleImmediateClick:(UITapGestureRecognizer*)gesture {
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    if (isDragging) {
        // Click while dragging = end drag mode
        [self endDragMode];
        lastClickTime = 0; // Reset timing after ending drag
        return;
    }
    
    // Check for double-click (within 600ms)
    if (currentTime - lastClickTime < 0.6 && lastClickTime > 0) {
        [self startDragMode];
        lastClickTime = 0; // Reset timing after starting drag
    } else {
        // Single click = execute immediately
        lastClickTime = currentTime;
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    }
}

- (void)handleLongClick:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (isDragging) {
            // Long press while dragging = end drag mode
            [self endDragMode];
        } else {
            // Start long press = wait to see if user moves
            isLongPressing = YES;
            hasMovedSinceDragStart = NO; // Reset movement tracking
            
            // Set timer for right click if no movement detected
            longPressRightClickTimer = [NSTimer scheduledTimerWithTimeInterval:0.8
                                                                        target:self
                                                                      selector:@selector(executeLongPressRightClick:)
                                                                      userInfo:nil
                                                                       repeats:NO];
        }
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        // End long press
        [longPressRightClickTimer invalidate];
        longPressRightClickTimer = nil;
        
        if (isLongPressing && isDragging) {
            // End manual drag operation
            [self endDragMode];
        }
        
        isLongPressing = NO;
    }
}

- (void)startDragMode {
    isDragging = YES;
    hasMovedSinceDragStart = NO;
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
    
    // Start timer to auto-cancel if no movement
    dragInactivityTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                           target:self
                                                         selector:@selector(handleDragInactivity:)
                                                         userInfo:nil
                                                          repeats:NO];
}

- (void)endDragMode {
    if (isDragging) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
        isDragging = NO;
        hasMovedSinceDragStart = NO;
        isLongPressing = NO; // Clear long press state
        [dragInactivityTimer invalidate];
        dragInactivityTimer = nil;
        [longPressRightClickTimer invalidate];
        longPressRightClickTimer = nil;
    }
}

- (void)resetDragInactivityTimer {
    [dragInactivityTimer invalidate];
    
    // Auto-exit drag mode if no movement for 2 seconds
    dragInactivityTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                           target:self
                                                         selector:@selector(handleDragInactivity:)
                                                         userInfo:nil
                                                          repeats:NO];
}

- (void)handleDragInactivity:(NSTimer*)timer {
    if (isDragging) {
        if (!hasMovedSinceDragStart) {
            // User double-clicked but never moved = likely accidental
            [self endDragMode];
        } else {
            // User was dragging but stopped moving = auto-exit drag mode
            [self endDragMode];
        }
    }
}

- (void)executeLongPressRightClick:(NSTimer*)timer {
    if (isLongPressing && !hasMovedSinceDragStart) {
        // No movement detected during long press = execute right click
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
        isLongPressing = NO;
    }
    longPressRightClickTimer = nil;
}

@end

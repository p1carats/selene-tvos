//
//  Controller.m
//  Selene
//
//  Created by Noé Barlet on 27/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

#import "Controller.h"
#import "HapticContext.h"

@implementation Controller

- (instancetype)init {
    self = [super init];
    if (self) {
        [self resetInputState];
    }
    return self;
}

- (void)resetInputState {
    self.lastButtonFlags = 0;
    self.lastLeftTrigger = 0;
    self.lastRightTrigger = 0;
    self.lastLeftStickX = 0;
    self.lastLeftStickY = 0;
    self.lastRightStickX = 0;
    self.lastRightStickY = 0;
    self.primaryTouch = (ControllerTouchContext){0, 0};
    self.secondaryTouch = (ControllerTouchContext){0, 0};
}

- (void)cleanup {
    // Invalidate timers immediately to prevent callbacks after controller disconnect
    [self.accelTimer invalidate];
    self.accelTimer = nil;
    [self.gyroTimer invalidate];
    self.gyroTimer = nil;
    [self.batteryTimer invalidate];
    self.batteryTimer = nil;
    
    // Clean up haptics
    [self.lowFreqMotor cleanup];
    [self.highFreqMotor cleanup];
    [self.leftTriggerMotor cleanup];
    [self.rightTriggerMotor cleanup];
    
    // Clear gamepad reference
    self.gamepad = nil;
}

- (void)dealloc {
    [self cleanup];
}

@end

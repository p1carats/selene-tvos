//
//  Controller.h
//  Selene
//
//  Created by Noé Barlet on 27/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;
@import GameController;
@import CoreHaptics;

NS_ASSUME_NONNULL_BEGIN

@class HapticContext;

typedef struct {
    float lastX;
    float lastY;
} ControllerTouchContext;

@interface Controller : NSObject

// Core properties
@property (nonatomic, strong, nullable) GCController *gamepad;
@property (nonatomic, assign) NSInteger playerIndex;

// Input state
@property (nonatomic, assign) uint32_t lastButtonFlags;
@property (nonatomic, assign) uint8_t lastLeftTrigger;
@property (nonatomic, assign) uint8_t lastRightTrigger;
@property (nonatomic, assign) int16_t lastLeftStickX;
@property (nonatomic, assign) int16_t lastLeftStickY;
@property (nonatomic, assign) int16_t lastRightStickX;
@property (nonatomic, assign) int16_t lastRightStickY;

// Touch state
@property (nonatomic, assign) ControllerTouchContext primaryTouch;
@property (nonatomic, assign) ControllerTouchContext secondaryTouch;

// Haptic feedback
@property (nonatomic, strong, nullable) HapticContext *lowFreqMotor;
@property (nonatomic, strong, nullable) HapticContext *highFreqMotor;
@property (nonatomic, strong, nullable) HapticContext *leftTriggerMotor;
@property (nonatomic, strong, nullable) HapticContext *rightTriggerMotor;

// Motion sensors
@property (nonatomic, strong, nullable) NSTimer *accelTimer;
@property (nonatomic, assign) GCAcceleration lastAccelSample;
@property (nonatomic, strong, nullable) NSTimer *gyroTimer;
@property (nonatomic, assign) GCRotationRate lastGyroSample;

// Battery monitoring
@property (nonatomic, strong, nullable) NSTimer *batteryTimer;
@property (nonatomic, assign) GCDeviceBatteryState lastBatteryState;
@property (nonatomic, assign) float lastBatteryLevel;

// Status tracking
@property (nonatomic, assign) BOOL reportedArrival;

// Convenience methods
- (void)resetInputState;
- (void)cleanup;

@end

NS_ASSUME_NONNULL_END

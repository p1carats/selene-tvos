//
//  ControllerSupport.h
//  Selene
//
//  Created by Noé Barlet on 27/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@class Controller;

@protocol ControllerSupportDelegate <NSObject>

- (void)gamepadPresenceChanged;
- (void)streamExitRequested;

@end

@interface ControllerSupport : NSObject

// Initialization
- (instancetype)initWithDelegate:(id<ControllerSupportDelegate>)delegate;

// Connection management
- (void)connectionEstablished;
- (void)cleanup;

// Input processing
- (void)updateController:(Controller *)controller
               leftStick:(CGPoint)leftStick 
              rightStick:(CGPoint)rightStick 
                triggers:(CGPoint)triggers 
                 buttons:(uint32_t)buttons;

// Haptic feedback
- (void)rumbleController:(uint16_t)controllerNumber
            lowFreqMotor:(uint16_t)lowFreqMotor 
           highFreqMotor:(uint16_t)highFreqMotor;

- (void)rumbleTriggersForController:(uint16_t)controllerNumber 
                        leftTrigger:(uint16_t)leftTrigger 
                       rightTrigger:(uint16_t)rightTrigger;

// Advanced features
- (void)setMotionEventState:(uint16_t)controllerNumber
                 motionType:(uint8_t)motionType 
               reportRateHz:(uint16_t)reportRateHz;

- (void)setControllerLED:(uint16_t)controllerNumber 
                       r:(uint8_t)r 
                       g:(uint8_t)g 
                       b:(uint8_t)b;

// Status queries
- (NSUInteger)connectedGamepadCount;
+ (int)connectedGamepadMask;
+ (int)connectedGamepadCount;

@end

NS_ASSUME_NONNULL_END

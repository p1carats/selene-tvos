//
//  ControllerSupport.m
//  Selene
//
//  Created by Noé Barlet on 27/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import GameController;
@import GameStreamKit;

#import "ControllerSupport.h"
#import "Controller.h"
#import "HapticContext.h"
#import "Logger.h"

// Constants
static const NSTimeInterval kBatteryPollingInterval = 30.0;

@interface ControllerSupport ()

// Core state management
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, Controller *> *controllers;

// Configuration
@property (nonatomic, assign) uint16_t controllerNumbers;

// Delegate
@property (nonatomic, weak) id<ControllerSupportDelegate> delegate;

// Observer tokens
@property (nonatomic, strong) id controllerConnectObserver;
@property (nonatomic, strong) id controllerDisconnectObserver;

@end

@implementation ControllerSupport

#pragma mark - Initialization

- (instancetype)initWithDelegate:(id<ControllerSupportDelegate>)delegate {
    self = [super init];
    if (self) {
        _controllers = [[NSMutableDictionary alloc] init];
        _controllerNumbers = 0;
        _delegate = delegate;
        
        Log(LOG_I, @"ControllerSupport initialized - Connected gamepads: %d",
            [self class].connectedGamepadCount);
        
        [self setupInitialControllers];
        [self setupObservers];
    }
    return self;
}

- (void)setupInitialControllers {
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad) {
            [self assignController:controller];
            [self registerControllerCallbacks:controller];
        }
    }
    
}

- (void)setupObservers {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSOperationQueue *mainQueue = NSOperationQueue.mainQueue;
    
    __weak typeof(self) weakSelf = self;
    
    _controllerConnectObserver = [center addObserverForName:GCControllerDidConnectNotification
                                                     object:nil
                                                      queue:mainQueue
                                                 usingBlock:^(NSNotification *note) {
        [weakSelf handleControllerConnected:note.object];
    }];
    
    _controllerDisconnectObserver = [center addObserverForName:GCControllerDidDisconnectNotification
                                                        object:nil
                                                         queue:mainQueue
                                                    usingBlock:^(NSNotification *note) {
        [weakSelf handleControllerDisconnected:note.object];
    }];
}

#pragma mark - Connection Management

- (void)connectionEstablished {
    for (Controller *controller in self.controllers.allValues) {
        [self reportControllerArrival:controller];
    }
}

- (void)cleanup {
    // Remove observers
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center removeObserver:_controllerConnectObserver];
    [center removeObserver:_controllerDisconnectObserver];
    
    // Clean up controllers directly
    for (Controller *controller in self.controllers.allValues) {
        [controller cleanup];
    }
    [self.controllers removeAllObjects];
    self.controllerNumbers = 0;
    
    // Unregister callbacks
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad) {
            [self unregisterControllerCallbacks:controller];
        }
    }
    

}

#pragma mark - Controller Management

- (void)handleControllerConnected:(GCController *)controller {
    if (!controller.extendedGamepad) {
        return;
    }
        
    Log(LOG_I, @"Controller connected: %@ - Type: %@", controller.productCategory, [self controllerTypeDescription:controller]);
    
    Controller *gameController = [self assignController:controller];
    if (gameController) {
        [self registerControllerCallbacks:controller];
        [self reportControllerArrival:gameController];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate gamepadPresenceChanged];
        });
    }
}

- (void)handleControllerDisconnected:(GCController *)controller {
    if (!controller.extendedGamepad) {
        return;
    }
    
    Log(LOG_I, @"Controller disconnected: %@", controller.productCategory);
    
    // Find and cleanup the controller immediately
    Controller *gameController = [self.controllers objectForKey:@(controller.playerIndex)];
    if (gameController) {
        [gameController cleanup]; // Clean up timers and resources immediately
    }
    
    // Handle controller disconnect directly for minimal latency
    [self unregisterControllerCallbacks:controller];
    self.controllerNumbers &= ~(1 << controller.playerIndex);
    if (gameController) {
        [self.controllers removeObjectForKey:@(controller.playerIndex)];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate gamepadPresenceChanged];
        });
    }
}

- (nullable Controller *)assignController:(GCController *)controller {
    // Support up to 16 controllers (Sunshine protocol)
    for (int i = 0; i < 16; i++) {
        if (!(self.controllerNumbers & (1 << i))) {
            self.controllerNumbers |= (1 << i);
            controller.playerIndex = i;
            
            Controller *gameController = [[Controller alloc] init];
            gameController.playerIndex = i;
            gameController.gamepad = controller;
            
            // Initialize haptics
            [self initializeControllerHaptics:gameController];
            
            self.controllers[@(controller.playerIndex)] = gameController;
            
            Log(LOG_I, @"Assigned %@ controller to index: %d", [self controllerTypeDescription:controller], i);
            return gameController;
        }
    }
    
    return nil;
}

- (NSString *)controllerTypeDescription:(GCController *)controller {
    if ([controller.extendedGamepad isKindOfClass:[GCXboxGamepad class]]) {
        return @"Xbox";
    } else if ([controller.extendedGamepad isKindOfClass:[GCDualShockGamepad class]]) {
        return @"DualShock";
    } else if ([controller.extendedGamepad isKindOfClass:[GCDualSenseGamepad class]]) {
        return @"DualSense";
    } else if (controller.physicalInputProfile) {
        return @"MFi Controller";
    }
    return @"Unknown";
}

#pragma mark - Input Processing

- (void)updateController:(Controller *)controller
               leftStick:(CGPoint)leftStick 
              rightStick:(CGPoint)rightStick 
                triggers:(CGPoint)triggers 
                 buttons:(uint32_t)buttons {
    
    // Validate controller and input bounds
    if (!controller || !controller.gamepad) {
        return; // Controller was disconnected
    }
    
    // Clamp input values to valid ranges to prevent overflow
    CGFloat clampedLeftX = fmax(-1.0f, fmin(1.0f, leftStick.x));
    CGFloat clampedLeftY = fmax(-1.0f, fmin(1.0f, leftStick.y));
    CGFloat clampedRightX = fmax(-1.0f, fmin(1.0f, rightStick.x));
    CGFloat clampedRightY = fmax(-1.0f, fmin(1.0f, rightStick.y));
    CGFloat clampedTriggerX = fmax(0.0f, fmin(1.0f, triggers.x));
    CGFloat clampedTriggerY = fmax(0.0f, fmin(1.0f, triggers.y));
    
    @synchronized(controller) {
        // Direct analog input conversion with validated inputs
        controller.lastLeftStickX = (int16_t)(clampedLeftX * 0x7FFE);
        controller.lastLeftStickY = (int16_t)(clampedLeftY * 0x7FFE);
        controller.lastRightStickX = (int16_t)(clampedRightX * 0x7FFE);
        controller.lastRightStickY = (int16_t)(clampedRightY * 0x7FFE);
        controller.lastLeftTrigger = (uint8_t)(clampedTriggerX * 0xFF);
        controller.lastRightTrigger = (uint8_t)(clampedTriggerY * 0xFF);
        
        // Update button state
        [self updateButtonFlags:controller flags:buttons];
        
        [self sendControllerUpdate:controller];
    }
}

- (void)updateButtonFlags:(Controller *)controller flags:(uint32_t)flags {
    controller.lastButtonFlags = flags;
}

- (void)sendControllerUpdate:(Controller *)controller {
    // Check for exit combo
    if (controller.lastButtonFlags == ([ControllerConstants playFlag] | [ControllerConstants backFlag] | [ControllerConstants lbFlag] | [ControllerConstants rbFlag])) {
        controller.lastButtonFlags = 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate streamExitRequested];
        });
        return;
    }
    
    // Only send if controller arrival was reported
    if (!controller.reportedArrival) {
        return;
    }
            
    // Network transmission
    [GameStream sendMultiControllerEventWithControllerNumber:(uint8_t)controller.playerIndex
                                           activeGamepadMask:[self activeGamepadMask]
                                                 buttonFlags:controller.lastButtonFlags
                                                 leftTrigger:controller.lastLeftTrigger
                                                rightTrigger:controller.lastRightTrigger
                                                  leftStickX:controller.lastLeftStickX
                                                  leftStickY:controller.lastLeftStickY
                                                 rightStickX:controller.lastRightStickX
                                                 rightStickY:controller.lastRightStickY];
}

#pragma mark - Controller Callbacks

- (void)registerControllerCallbacks:(GCController *)controller {
    if (!controller) return;
    
    Log(LOG_I, @"Registering callbacks for %@ controller", [self controllerTypeDescription:controller]);
    
    if (controller.extendedGamepad) {
        [self setupGamepadCallbacks:controller];
    }
}

- (void)setupGamepadCallbacks:(GCController *)controller {
    // Disable system gestures for optimal gaming performance
    for (GCControllerElement *element in controller.physicalInputProfile.allElements) {
        element.preferredSystemGestureState = GCSystemGestureStateDisabled;
    }
    
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    Controller *gameController = self.controllers[@(controller.playerIndex)];
    
    __weak typeof(self) weakSelf = self;
    gamepad.valueChangedHandler = ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !gameController) return;
        
        // Collect all input states atomically
        CGPoint leftStick = CGPointMake(gamepad.leftThumbstick.xAxis.value, gamepad.leftThumbstick.yAxis.value);
        CGPoint rightStick = CGPointMake(gamepad.rightThumbstick.xAxis.value, gamepad.rightThumbstick.yAxis.value);
        CGPoint triggers = CGPointMake(gamepad.leftTrigger.value, gamepad.rightTrigger.value);
        uint32_t buttons = [strongSelf buildButtonFlags:gamepad];
        
        [strongSelf updateController:gameController leftStick:leftStick rightStick:rightStick triggers:triggers buttons:buttons];
        
        // Handle advanced features
        [strongSelf handleAdvancedFeatures:gamepad controller:gameController];
    };
}

- (uint32_t)buildButtonFlags:(GCExtendedGamepad *)gamepad {
    uint32_t flags = 0;
    
    // Face buttons
    if (gamepad.buttonA.pressed) flags |= [ControllerConstants aFlag];
    if (gamepad.buttonB.pressed) flags |= [ControllerConstants bFlag];
    if (gamepad.buttonX.pressed) flags |= [ControllerConstants xFlag];
    if (gamepad.buttonY.pressed) flags |= [ControllerConstants yFlag];
    
    // D-pad
    if (gamepad.dpad.up.pressed) flags |= [ControllerConstants upFlag];
    if (gamepad.dpad.down.pressed) flags |= [ControllerConstants downFlag];
    if (gamepad.dpad.left.pressed) flags |= [ControllerConstants leftFlag];
    if (gamepad.dpad.right.pressed) flags |= [ControllerConstants rightFlag];
    
    // Shoulder buttons
    if (gamepad.leftShoulder.pressed) flags |= [ControllerConstants lbFlag];
    if (gamepad.rightShoulder.pressed) flags |= [ControllerConstants rbFlag];
    
    // Thumbstick clicks
    if (gamepad.leftThumbstickButton.pressed) flags |= [ControllerConstants lsClkFlag];
    if (gamepad.rightThumbstickButton.pressed) flags |= [ControllerConstants rsClkFlag];
    
    // System buttons
    if (gamepad.buttonOptions.pressed) flags |= [ControllerConstants backFlag];
    if (gamepad.buttonMenu.pressed) flags |= [ControllerConstants playFlag];
    if (gamepad.buttonHome.pressed) flags |= [ControllerConstants specialFlag];
    
    // Extended controller features
    [self addControllerButtons:gamepad.controller toFlags:&flags];
    
    return flags;
}

- (void)addControllerButtons:(GCController *)controller toFlags:(uint32_t *)flags {
    GCPhysicalInputProfile *profile = controller.physicalInputProfile;
    
    // Xbox Series X/S controller paddles
    if (profile.buttons[GCInputXboxPaddleOne].pressed) {
        *flags |= [ControllerConstants paddle1Flag];
    }
    if (profile.buttons[GCInputXboxPaddleTwo].pressed) {
        *flags |= [ControllerConstants paddle2Flag];
    }
    if (profile.buttons[GCInputXboxPaddleThree].pressed) {
        *flags |= [ControllerConstants paddle3Flag];
    }
    if (profile.buttons[GCInputXboxPaddleFour].pressed) {
        *flags |= [ControllerConstants paddle4Flag];
    }
    
    // Share button (Xbox, PlayStation)
    if (profile.buttons[GCInputButtonShare].pressed) {
        *flags |= [ControllerConstants miscFlag];
    }
    
    // DualShock/DualSense touchpad button
    if (profile.buttons[GCInputDualShockTouchpadButton].pressed) {
        *flags |= [ControllerConstants touchpadFlag];
    }
}

- (void)handleAdvancedFeatures:(GCExtendedGamepad *)gamepad controller:(Controller *)controller {
    // Handle DualShock/DualSense touchpad
    if (gamepad.controller.physicalInputProfile.dpads[GCInputDualShockTouchpadOne]) {
        [self handleTouchpadInput:gamepad.controller.physicalInputProfile.dpads[GCInputDualShockTouchpadOne]
                       controller:controller
                            index:0];
    }
    
    if (gamepad.controller.physicalInputProfile.dpads[GCInputDualShockTouchpadTwo]) {
        [self handleTouchpadInput:gamepad.controller.physicalInputProfile.dpads[GCInputDualShockTouchpadTwo]
                       controller:controller
                            index:1];
    }
}

- (void)handleTouchpadInput:(GCControllerDirectionPad *)touchpad controller:(Controller *)controller index:(int)index {
    // Get the current touch context
    ControllerTouchContext currentContext = (index == 0) ? controller.primaryTouch : controller.secondaryTouch;
    
    // Normalize touchpad coordinates
    float normalizedX = (1.0f + touchpad.xAxis.value) * 0.5f;
    float normalizedY = 1.0f - (1.0f + touchpad.yAxis.value) * 0.5f;
    
    // Detect touch state changes
    BOOL hadTouch = (currentContext.lastX != 0 || currentContext.lastY != 0);
    BOOL hasTouch = (touchpad.xAxis.value != 0 || touchpad.yAxis.value != 0);
    
    if (hadTouch && !hasTouch) {
        // Touch up
        [GameStream sendControllerTouchEventWithControllerNumber:(uint8_t)controller.playerIndex eventType:TouchEventTypeUp pointerId:index x:normalizedX y:normalizedY pressure:1.0f];
    } else if (!hadTouch && hasTouch) {
        // Touch down
        [GameStream sendControllerTouchEventWithControllerNumber:(uint8_t)controller.playerIndex eventType:TouchEventTypeDown pointerId:index x:normalizedX y:normalizedY pressure:1.0f];
    } else if (hasTouch && (currentContext.lastX != touchpad.xAxis.value || currentContext.lastY != touchpad.yAxis.value)) {
        // Touch move
        [GameStream sendControllerTouchEventWithControllerNumber:(uint8_t)controller.playerIndex eventType:TouchEventTypeMove pointerId:index x:normalizedX y:normalizedY pressure:1.0f];
    }
    
    // Update context
    ControllerTouchContext newContext = {touchpad.xAxis.value, touchpad.yAxis.value};
    if (index == 0) {
        controller.primaryTouch = newContext;
    } else {
        controller.secondaryTouch = newContext;
    }
}

- (void)unregisterControllerCallbacks:(GCController *)controller {
    if (!controller) return;
    
    if (controller.extendedGamepad) {
        // Re-enable system gestures
        for (GCControllerElement *element in controller.physicalInputProfile.allElements) {
            element.preferredSystemGestureState = GCSystemGestureStateEnabled;
        }
        
        controller.extendedGamepad.valueChangedHandler = nil;
    }
}

#pragma mark - Haptic Feedback

- (void)rumbleController:(uint16_t)controllerNumber lowFreqMotor:(uint16_t)lowFreqMotor highFreqMotor:(uint16_t)highFreqMotor {
    Controller *controller = self.controllers[@(controllerNumber)];
    if (!controller || !controller.gamepad) return;
    
    // Validate haptic contexts exist before use
    if (controller.lowFreqMotor) {
        [controller.lowFreqMotor setMotorAmplitude:lowFreqMotor];
    }
    if (controller.highFreqMotor) {
        [controller.highFreqMotor setMotorAmplitude:highFreqMotor];
    }
}

- (void)rumbleTriggersForController:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    Controller *controller = self.controllers[@(controllerNumber)];
    if (!controller || !controller.gamepad) return;
    
    // Validate haptic contexts exist before use
    if (controller.leftTriggerMotor) {
        [controller.leftTriggerMotor setMotorAmplitude:leftTrigger];
    }
    if (controller.rightTriggerMotor) {
        [controller.rightTriggerMotor setMotorAmplitude:rightTrigger];
    }
}

#pragma mark - Motion Sensors

- (void)setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    Controller *controller = self.controllers[@(controllerNumber)];
    if (!controller || !controller.gamepad.motion) return;
    
    Log(LOG_I, @"Setting motion state for %@ controller: type=%d, rate=%dHz", 
        [self controllerTypeDescription:controller.gamepad], motionType, reportRateHz);
    
    switch (motionType) {
        case MotionTypeAccel:
            [self setupAccelerometerForController:controller reportRate:reportRateHz];
            break;
        case MotionTypeGyro:
            [self setupGyroscopeForController:controller reportRate:reportRateHz];
            break;
    }
    
    if (controller.gamepad.motion.sensorsRequireManualActivation) {
        controller.gamepad.motion.sensorsActive = (controller.accelTimer != nil || controller.gyroTimer != nil);
    }
}

- (void)setupAccelerometerForController:(Controller *)controller reportRate:(uint16_t)reportRateHz {
    [controller.accelTimer invalidate];
    controller.accelTimer = nil;
    
    if (reportRateHz > 0 && controller.gamepad.motion.hasGravityAndUserAcceleration) {
        NSTimeInterval interval = 1.0 / reportRateHz;
        controller.lastAccelSample = (GCAcceleration){0, 0, 0};
        
        __weak typeof(controller) weakController = controller;
        controller.accelTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer *timer) {
            typeof(controller) strongController = weakController;
            if (!strongController) return;
            
            GCAcceleration current = strongController.gamepad.motion.acceleration;
            GCAcceleration last = strongController.lastAccelSample;
            
            // Skip duplicate samples for efficiency
            if (memcmp(&current, &last, sizeof(GCAcceleration)) == 0) return;
            
            strongController.lastAccelSample = current;
            
            // Convert from g to m/s^2
            [GameStream sendControllerMotionEventWithControllerNumber:(uint8_t)strongController.playerIndex motionType:MotionTypeAccel
                                                                    x:(current.x * -9.80665f) y:(current.y * -9.80665f) z:(current.z * -9.80665f)];
        }];
    }
}

- (void)setupGyroscopeForController:(Controller *)controller reportRate:(uint16_t)reportRateHz {
    [controller.gyroTimer invalidate];
    controller.gyroTimer = nil;
    
    if (reportRateHz > 0 && controller.gamepad.motion.hasRotationRate) {
        NSTimeInterval interval = 1.0 / reportRateHz;
        controller.lastGyroSample = (GCRotationRate){0, 0, 0};
        
        __weak typeof(controller) weakController = controller;
        controller.gyroTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer *timer) {
            typeof(controller) strongController = weakController;
            if (!strongController) return;
            
            GCRotationRate current = strongController.gamepad.motion.rotationRate;
            GCRotationRate last = strongController.lastGyroSample;
            
            // Skip duplicate samples for efficiency
            if (memcmp(&current, &last, sizeof(GCRotationRate)) == 0) return;
            
            strongController.lastGyroSample = current;
            
            // Convert from rad/s to deg/s
            [GameStream sendControllerMotionEventWithControllerNumber:(uint8_t)strongController.playerIndex motionType:MotionTypeGyro
                                                                    x:(current.x * 57.2957795f) y:(current.z * 57.2957795f) z:(current.y * -57.2957795f)];
        }];
    }
}

- (void)setControllerLED:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    Controller *controller = self.controllers[@(controllerNumber)];
    if (!controller || !controller.gamepad.light) return;
    
    controller.gamepad.light.color = [[GCColor alloc] initWithRed:(r / 255.0f) green:(g / 255.0f) blue:(b / 255.0f)];
}

#pragma mark - Controller Initialization

- (void)initializeControllerHaptics:(Controller *)controller {
    controller.lowFreqMotor = [HapticContext createContextForLowFreqMotor:controller.gamepad];
    controller.highFreqMotor = [HapticContext createContextForHighFreqMotor:controller.gamepad];
    controller.leftTriggerMotor = [HapticContext createContextForLeftTrigger:controller.gamepad];
    controller.rightTriggerMotor = [HapticContext createContextForRightTrigger:controller.gamepad];
}

- (BOOL)reportControllerArrival:(Controller *)controller {
    if (controller.reportedArrival) return YES;
    
    uint8_t type = [ControllerConstants typeUnknown];
    uint16_t capabilities = 0;
    uint32_t supportedButtonFlags = 0;
    
    GCController *gcController = controller.gamepad;
    if (gcController) {
        [self detectControllerCapabilities:gcController
                                            type:&type
                                    capabilities:&capabilities
                             supportedButtonFlags:&supportedButtonFlags];
    }
    
    Log(LOG_I, @"Reporting %@ controller arrival: type=%d, caps=0x%X, buttons=0x%X", 
        [self controllerTypeDescription:gcController], type, capabilities, supportedButtonFlags);
    
    // Report to host
    if ([GameStream sendControllerArrivalEventWithControllerNumber:(uint8_t)controller.playerIndex activeGamepadMask:[self activeGamepadMask]
                                                              type:type supportedButtonFlags:supportedButtonFlags capabilities:capabilities] != 0) {
        return NO;
    }
    
    // Start battery monitoring
    [self initializeControllerBattery:controller];
    
    controller.reportedArrival = YES;
    return YES;
}

- (void)detectControllerCapabilities:(GCController *)controller
                                      type:(uint8_t *)type
                              capabilities:(uint16_t *)capabilities
                       supportedButtonFlags:(uint32_t *)supportedButtonFlags {
    
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    
    // Type detection
    if ([gamepad isKindOfClass:[GCXboxGamepad class]]) {
        *type = [ControllerConstants typeXbox];
    } else if ([gamepad isKindOfClass:[GCDualShockGamepad class]]) {
        *type = [ControllerConstants typePlayStation];
    } else if ([gamepad isKindOfClass:[GCDualSenseGamepad class]]) {
        *type = [ControllerConstants typePlayStation];
    } else {
        *type = [ControllerConstants typeUnknown]; // Treat all other controllers as standard MFi
    }
    
    // Detect supported buttons
    *supportedButtonFlags |= [ControllerConstants playFlag]; // Always present
    
    if (gamepad.dpad) *supportedButtonFlags |= [ControllerConstants upFlag] | [ControllerConstants downFlag] | [ControllerConstants leftFlag] | [ControllerConstants rightFlag];
    if (gamepad.leftShoulder) *supportedButtonFlags |= [ControllerConstants lbFlag];
    if (gamepad.rightShoulder) *supportedButtonFlags |= [ControllerConstants rbFlag];
    if (gamepad.buttonOptions) *supportedButtonFlags |= [ControllerConstants backFlag];
    if (gamepad.buttonHome) *supportedButtonFlags |= [ControllerConstants specialFlag];
    if (gamepad.buttonA) *supportedButtonFlags |= [ControllerConstants aFlag];
    if (gamepad.buttonB) *supportedButtonFlags |= [ControllerConstants bFlag];
    if (gamepad.buttonX) *supportedButtonFlags |= [ControllerConstants xFlag];
    if (gamepad.buttonY) *supportedButtonFlags |= [ControllerConstants yFlag];
    if (gamepad.leftThumbstickButton) *supportedButtonFlags |= [ControllerConstants lsClkFlag];
    if (gamepad.rightThumbstickButton) *supportedButtonFlags |= [ControllerConstants rsClkFlag];
    
    // Capabilities detection
    if (controller.haptics) {
        if ([controller.haptics.supportedLocalities containsObject:GCHapticsLocalityHandles]) {
            *capabilities |= [ControllerConstants capRumble];
        }
        if ([controller.haptics.supportedLocalities containsObject:GCHapticsLocalityTriggers]) {
            *capabilities |= [ControllerConstants capTriggerRumble];
        }
    }
    
    if (controller.motion) {
        if (controller.motion.hasGravityAndUserAcceleration) *capabilities |= [ControllerConstants capAccelerometer];
        if (controller.motion.hasRotationRate) *capabilities |= [ControllerConstants capGyroscope];
    }
    
    if (controller.light) *capabilities |= [ControllerConstants capRgbLed];
    if (controller.battery) *capabilities |= [ControllerConstants capBatteryState];
    
    // Touchpad support (DualShock/DualSense)
    if (controller.physicalInputProfile.dpads[GCInputDualShockTouchpadOne]) {
        *capabilities |= [ControllerConstants capTouchpad];
        *supportedButtonFlags |= [ControllerConstants touchpadFlag];
    }
}

- (void)initializeControllerBattery:(Controller *)controller {
    if (!controller.gamepad.battery) return;
    
    __weak typeof(self) weakSelf = self;
    __weak typeof(controller) weakController = controller;
    controller.batteryTimer = [NSTimer scheduledTimerWithTimeInterval:kBatteryPollingInterval repeats:YES block:^(NSTimer *timer) {
        typeof(self) strongSelf = weakSelf;
        typeof(controller) strongController = weakController;
        if (!strongSelf || !strongController) return;
        
        GCDeviceBattery *battery = strongController.gamepad.battery;
        
        if (strongController.lastBatteryState != battery.batteryState || 
            strongController.lastBatteryLevel != battery.batteryLevel) {
            
            uint8_t batteryState = [strongSelf convertBatteryState:battery.batteryState];
            uint8_t batteryLevel = (uint8_t)(battery.batteryLevel * 100);
            
            [GameStream sendControllerBatteryEventWithControllerNumber:(uint8_t)strongController.playerIndex batteryState:batteryState batteryPercentage:batteryLevel];
            
            strongController.lastBatteryState = battery.batteryState;
            strongController.lastBatteryLevel = battery.batteryLevel;
        }
    }];
    
    // Fire immediately for initial state
    [controller.batteryTimer fire];
}

- (uint8_t)convertBatteryState:(GCDeviceBatteryState)state {
    switch (state) {
        case GCDeviceBatteryStateFull: return BatteryStateFull;
        case GCDeviceBatteryStateCharging: return BatteryStateCharging;
        case GCDeviceBatteryStateDischarging: return BatteryStateDischarging;
        case GCDeviceBatteryStateUnknown:
        default: return BatteryStateUnknown;
    }
}

#pragma mark - Utility Methods

- (uint16_t)activeGamepadMask {
    return _controllerNumbers;
}

- (NSUInteger)connectedGamepadCount {
    return self.controllers.count;
}

+ (int)connectedGamepadMask {
    int mask = 0;
    int i = 0;
    
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad) {
            mask |= 1 << i++;
        }
    }
    
    return mask;
}

+ (int)connectedGamepadCount {
    int count = 0;
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad) {
            count++;
        }
    }
    return count;
}

@end

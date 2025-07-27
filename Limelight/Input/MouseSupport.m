//
//  MouseSupport.m
//  Selene
//
//  Created by Noé Barlet on 27/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import GameController;
@import GameStreamKit;

#import "MouseSupport.h"
#import "Logger.h"

// Speed divisor for mouse sensitivity
static const float kMouseSpeedDivisor = 1.25f;

@interface MouseSupport ()

@property (nonatomic, strong) id gcMouseConnectObserver;
@property (nonatomic, strong) id gcMouseDisconnectObserver;
@property (nonatomic, assign) float accumulatedDeltaX;
@property (nonatomic, assign) float accumulatedDeltaY;
@property (nonatomic, assign) float accumulatedScrollX;
@property (nonatomic, assign) float accumulatedScrollY;

@end

@implementation MouseSupport

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        // Reset accumulated deltas
        [self resetAccumulatedDeltas];
        
        Log(LOG_I, @"MouseSupport initialized");
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
}

#pragma mark - Public Methods

- (void)startMouseSupport {
    Log(LOG_I, @"Starting mouse support");
    
    [self setupBluetoothMouseSupport];
}

- (void)stopMouseSupport {
    Log(LOG_I, @"Stopping mouse support");
    
    [self cleanup];
}

- (void)cleanup {
    [self cleanupBluetoothMouseSupport];
    [self resetAccumulatedDeltas];
}

+ (BOOL)hasConnectedMouse {
    // Check for paired Bluetooth mice
    return GCMouse.mice.count > 0;
}

#pragma mark - Private Helpers

- (void)resetAccumulatedDeltas {
    _accumulatedDeltaX = 0.0f;
    _accumulatedDeltaY = 0.0f;
    _accumulatedScrollX = 0.0f;
    _accumulatedScrollY = 0.0f;
}

#pragma mark - Mouse Support

- (void)setupBluetoothMouseSupport {
    // Register for existing paired mice
    for (GCMouse *mouse in GCMouse.mice) {
        [self registerBluetoothMouseCallbacks:mouse];
    }
    
    // Setup connection observers
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
    
    __weak typeof(self) weakSelf = self;
    
    _gcMouseConnectObserver = [center addObserverForName:GCMouseDidConnectNotification
                                                  object:nil
                                                   queue:mainQueue
                                              usingBlock:^(NSNotification *note) {
        [weakSelf handleBluetoothMouseConnected:note.object];
    }];
    
    _gcMouseDisconnectObserver = [center addObserverForName:GCMouseDidDisconnectNotification
                                                     object:nil
                                                      queue:mainQueue
                                                 usingBlock:^(NSNotification *note) {
        [weakSelf handleBluetoothMouseDisconnected:note.object];
    }];
    
    Log(LOG_I, @"Bluetooth Mouse support setup complete - %lu mice detected", 
        (unsigned long)GCMouse.mice.count);
}

- (void)cleanupBluetoothMouseSupport {
    // Unregister all paired mice
    for (GCMouse *mouse in GCMouse.mice) {
        [self unregisterBluetoothMouseCallbacks:mouse];
    }
    
    // Remove observers
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_gcMouseConnectObserver) {
        [center removeObserver:_gcMouseConnectObserver];
        _gcMouseConnectObserver = nil;
    }
    if (_gcMouseDisconnectObserver) {
        [center removeObserver:_gcMouseDisconnectObserver];
        _gcMouseDisconnectObserver = nil;
    }
}

- (void)handleBluetoothMouseConnected:(GCMouse *)mouse {
    Log(LOG_I, @"Bluetooth Mouse connected");
    [self registerBluetoothMouseCallbacks:mouse];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate mousePresenceChanged];
    });
}

- (void)handleBluetoothMouseDisconnected:(GCMouse *)mouse {
    Log(LOG_I, @"Bluetooth Mouse disconnected");
    [self unregisterBluetoothMouseCallbacks:mouse];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate mousePresenceChanged];
    });
}

- (void)registerBluetoothMouseCallbacks:(GCMouse *)mouse {
    __weak typeof(self) weakSelf = self;
    
    mouse.mouseInput.mouseMovedHandler = ^(GCMouseInput *mouseInput, float deltaX, float deltaY) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        strongSelf.accumulatedDeltaX += deltaX / kMouseSpeedDivisor;
        strongSelf.accumulatedDeltaY += -deltaY / kMouseSpeedDivisor; // Inverted Y
        
        int16_t truncatedDeltaX = (int16_t)strongSelf.accumulatedDeltaX;
        int16_t truncatedDeltaY = (int16_t)strongSelf.accumulatedDeltaY;
        
        if (truncatedDeltaX != 0 || truncatedDeltaY != 0) {
            LiSendMouseMoveEvent(truncatedDeltaX, truncatedDeltaY);
            strongSelf.accumulatedDeltaX -= truncatedDeltaX;
            strongSelf.accumulatedDeltaY -= truncatedDeltaY;
        }
    };
    
    mouse.mouseInput.leftButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        LiSendMouseButtonEvent(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    };
    
    mouse.mouseInput.rightButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        LiSendMouseButtonEvent(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
    };
    
    mouse.mouseInput.middleButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        LiSendMouseButtonEvent(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, BUTTON_MIDDLE);
    };
    
    // Auxiliary buttons
    for (GCControllerButtonInput *auxButton in mouse.mouseInput.auxiliaryButtons) {
        auxButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            // TODO: Handle auxiliary buttons as needed
        };
    }
    
    // Scroll wheel
    mouse.mouseInput.scroll.xAxis.valueChangedHandler = ^(GCControllerAxisInput *axis, float value) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        strongSelf.accumulatedScrollX += value;
        int16_t scrollDelta = (int16_t)strongSelf.accumulatedScrollX;
        if (scrollDelta != 0) {
            LiSendScrollEvent(scrollDelta);
            strongSelf.accumulatedScrollX -= scrollDelta;
        }
    };
    
    mouse.mouseInput.scroll.yAxis.valueChangedHandler = ^(GCControllerAxisInput *axis, float value) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        strongSelf.accumulatedScrollY += value;
        int16_t scrollDelta = (int16_t)strongSelf.accumulatedScrollY;
        if (scrollDelta != 0) {
            LiSendScrollEvent(scrollDelta);
            strongSelf.accumulatedScrollY -= scrollDelta;
        }
    };
}

- (void)unregisterBluetoothMouseCallbacks:(GCMouse *)mouse {
    mouse.mouseInput.mouseMovedHandler = nil;
    mouse.mouseInput.leftButton.pressedChangedHandler = nil;
    mouse.mouseInput.rightButton.pressedChangedHandler = nil;
    mouse.mouseInput.middleButton.pressedChangedHandler = nil;
    
    for (GCControllerButtonInput *auxButton in mouse.mouseInput.auxiliaryButtons) {
        auxButton.pressedChangedHandler = nil;
    }
    
    mouse.mouseInput.scroll.xAxis.valueChangedHandler = nil;
    mouse.mouseInput.scroll.yAxis.valueChangedHandler = nil;
}

@end

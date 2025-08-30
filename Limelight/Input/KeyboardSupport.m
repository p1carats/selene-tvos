//
//  KeyboardSupport.m
//  Selene
//
//  Created by Noé Barlet on 27/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import GameController;
@import GameStreamKit;

#import "KeyboardSupport.h"
#import "Logger.h"

@interface KeyboardSupport ()

@property (nonatomic, strong) id gcKeyboardConnectObserver;
@property (nonatomic, strong) id gcKeyboardDisconnectObserver;

@end

@implementation KeyboardSupport

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        Log(LOG_I, @"KeyboardSupport initialized");
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
}

#pragma mark - Public Methods

- (void)startKeyboardSupport {
    Log(LOG_I, @"Starting modern GameController keyboard support");
    
    [self setupBluetoothKeyboardSupport];
    
    if (GCKeyboard.coalescedKeyboard) {
        [self registerKeyboardCallbacks:GCKeyboard.coalescedKeyboard];
    }
}

- (void)stopKeyboardSupport {
    Log(LOG_I, @"Stopping keyboard support");
    [self cleanup];
}

- (void)cleanup {
    [self cleanupBluetoothKeyboardSupport];
    if (GCKeyboard.coalescedKeyboard) {
        [self unregisterKeyboardCallbacks:GCKeyboard.coalescedKeyboard];
    }
}

+ (BOOL)hasConnectedKeyboard {
    // Check for paired Bluetooth keyboards
    return GCKeyboard.coalescedKeyboard != nil;
}

#pragma mark - Keyboard Support

- (void)setupBluetoothKeyboardSupport {
    // Setup connection observers
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
    
    __weak typeof(self) weakSelf = self;
    
    _gcKeyboardConnectObserver = [center addObserverForName:GCKeyboardDidConnectNotification
                                                     object:nil
                                                      queue:mainQueue
                                                 usingBlock:^(NSNotification *note) {
        [weakSelf handleBluetoothKeyboardConnected:note.object];
    }];
    
    _gcKeyboardDisconnectObserver = [center addObserverForName:GCKeyboardDidDisconnectNotification
                                                        object:nil
                                                         queue:mainQueue
                                                    usingBlock:^(NSNotification *note) {
        [weakSelf handleBluetoothKeyboardDisconnected:note.object];
    }];
    
    Log(LOG_I, @"Bluetooth Keyboard support setup complete - Keyboard present: %@", 
        GCKeyboard.coalescedKeyboard ? @"YES" : @"NO");
}

- (void)cleanupBluetoothKeyboardSupport {
    // Remove observers
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_gcKeyboardConnectObserver) {
        [center removeObserver:_gcKeyboardConnectObserver];
        _gcKeyboardConnectObserver = nil;
    }
    if (_gcKeyboardDisconnectObserver) {
        [center removeObserver:_gcKeyboardDisconnectObserver];
        _gcKeyboardDisconnectObserver = nil;
    }
}

- (void)handleBluetoothKeyboardConnected:(GCKeyboard *)keyboard {
    Log(LOG_I, @"Bluetooth Keyboard connected");
    
    [self registerKeyboardCallbacks:keyboard];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate keyboardPresenceChanged];
    });
}

- (void)handleBluetoothKeyboardDisconnected:(GCKeyboard *)keyboard {
    Log(LOG_I, @"Bluetooth Keyboard disconnected");
    
    [self unregisterKeyboardCallbacks:keyboard];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate keyboardPresenceChanged];
    });
}

#pragma mark - Input Handling

- (void)registerKeyboardCallbacks:(GCKeyboard *)keyboard {
    __weak typeof(self) weakSelf = self;
    
    keyboard.keyboardInput.keyChangedHandler = ^(GCKeyboardInput *keyboardInput, GCControllerButtonInput *key, GCKeyCode keyCode, BOOL pressed) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        // Simple modifier detection - check common modifier keys
        NSUInteger modifierFlags = 0;
        if (keyboardInput.buttons[@"Key_LeftShift"].isPressed || keyboardInput.buttons[@"Key_RightShift"].isPressed) {
            modifierFlags |= (1 << 1); // Shift
        }
        if (keyboardInput.buttons[@"Key_LeftControl"].isPressed || keyboardInput.buttons[@"Key_RightControl"].isPressed) {
            modifierFlags |= (1 << 2); // Control
        }
        if (keyboardInput.buttons[@"Key_LeftAlt"].isPressed || keyboardInput.buttons[@"Key_RightAlt"].isPressed) {
            modifierFlags |= (1 << 3); // Alt
        }
        if (keyboardInput.buttons[@"Key_LeftGUI"].isPressed || keyboardInput.buttons[@"Key_RightGUI"].isPressed) {
            modifierFlags |= (1 << 4); // Cmd/GUI
        }
        
        [strongSelf handleKeyEvent:keyCode pressed:pressed modifierFlags:modifierFlags];
    };
    
    Log(LOG_I, @"Modern GCKeyboard callbacks registered");
}

- (void)unregisterKeyboardCallbacks:(GCKeyboard *)keyboard {
    keyboard.keyboardInput.keyChangedHandler = nil;
    
    Log(LOG_I, @"GCKeyboard callbacks unregistered");
}

- (void)handleKeyEvent:(GCKeyCode)keyCode pressed:(BOOL)pressed modifierFlags:(NSUInteger)modifierFlags {
    // Convert modern GCKeyCode to Win32 VK code
    short win32KeyCode = [self win32KeyCodeFromGCKeyCode:keyCode];
    if (win32KeyCode == 0) {
        Log(LOG_W, @"Unhandled GCKeyCode: %ld", (long)keyCode);
        return;
    }
    
    // Convert modifier flags to legacy modifier flags
    char legacyModifierFlags = 0;
    // CapsLock (bit 0) is handled differently, don't include in modifier flags
    if (modifierFlags & (1 << 1)) { // Shift
        legacyModifierFlags |= [InputConstants modifierShift];
    }
    if (modifierFlags & (1 << 2)) { // Control
        legacyModifierFlags |= [InputConstants modifierCtrl];
    }
    if (modifierFlags & (1 << 3)) { // Alt/Option
        legacyModifierFlags |= [InputConstants modifierAlt];
    }
    if (modifierFlags & (1 << 4)) { // Cmd/GUI
        legacyModifierFlags |= [InputConstants modifierMeta];
    }
    
    // Send keyboard event
    [GameStream sendKeyboardEventWithKeyCode:0x8000 | win32KeyCode
                                   keyAction:(pressed ? [InputConstants keyActionDown] : [InputConstants keyActionUp])
                                   modifiers:legacyModifierFlags];
}

#pragma mark - GCKeyCode to Win32 VK Mapping

- (short)win32KeyCodeFromGCKeyCode:(GCKeyCode)keyCode {
    // Modern GCKeyCode to Win32 VK_* mapping
    // https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
    
    // TODO: only supports letters and numbers for now, expand GCKeyCode support later
    
    // Letters A-Z
    if (keyCode == GCKeyCodeKeyA) return 0x41;
    if (keyCode == GCKeyCodeKeyB) return 0x42;
    if (keyCode == GCKeyCodeKeyC) return 0x43;
    if (keyCode == GCKeyCodeKeyD) return 0x44;
    if (keyCode == GCKeyCodeKeyE) return 0x45;
    if (keyCode == GCKeyCodeKeyF) return 0x46;
    if (keyCode == GCKeyCodeKeyG) return 0x47;
    if (keyCode == GCKeyCodeKeyH) return 0x48;
    if (keyCode == GCKeyCodeKeyI) return 0x49;
    if (keyCode == GCKeyCodeKeyJ) return 0x4A;
    if (keyCode == GCKeyCodeKeyK) return 0x4B;
    if (keyCode == GCKeyCodeKeyL) return 0x4C;
    if (keyCode == GCKeyCodeKeyM) return 0x4D;
    if (keyCode == GCKeyCodeKeyN) return 0x4E;
    if (keyCode == GCKeyCodeKeyO) return 0x4F;
    if (keyCode == GCKeyCodeKeyP) return 0x50;
    if (keyCode == GCKeyCodeKeyQ) return 0x51;
    if (keyCode == GCKeyCodeKeyR) return 0x52;
    if (keyCode == GCKeyCodeKeyS) return 0x53;
    if (keyCode == GCKeyCodeKeyT) return 0x54;
    if (keyCode == GCKeyCodeKeyU) return 0x55;
    if (keyCode == GCKeyCodeKeyV) return 0x56;
    if (keyCode == GCKeyCodeKeyW) return 0x57;
    if (keyCode == GCKeyCodeKeyX) return 0x58;
    if (keyCode == GCKeyCodeKeyY) return 0x59;
    if (keyCode == GCKeyCodeKeyZ) return 0x5A;
    
    // Numbers 0-9
    if (keyCode == GCKeyCodeOne) return 0x31;
    if (keyCode == GCKeyCodeTwo) return 0x32;
    if (keyCode == GCKeyCodeThree) return 0x33;
    if (keyCode == GCKeyCodeFour) return 0x34;
    if (keyCode == GCKeyCodeFive) return 0x35;
    if (keyCode == GCKeyCodeSix) return 0x36;
    if (keyCode == GCKeyCodeSeven) return 0x37;
    if (keyCode == GCKeyCodeEight) return 0x38;
    if (keyCode == GCKeyCodeNine) return 0x39;
    if (keyCode == GCKeyCodeZero) return 0x30;
    
    // Unknown key
    return 0;
}

@end

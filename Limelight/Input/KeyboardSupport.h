//
//  KeyboardSupport.h
//  Moonlight
//
//  Created by Diego Waxemberg on 8/25/18.
//  Copyright © 2018 Moonlight Game Streaming Project. All rights reserved.
//

@import Foundation;
@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface KeyboardSupport : NSObject

struct KeyEvent {
    u_short keycode;
    u_short modifierKeycode;
    u_char modifier;
};

+ (BOOL)sendKeyEventForPress:(UIPress*)press down:(BOOL)down;
+ (BOOL)sendKeyEvent:(UIKey*)key down:(BOOL)down;
+ (struct KeyEvent) translateKeyEvent:(unichar) inputChar withModifierFlags:(UIKeyModifierFlags)modifierFlags;

@end

NS_ASSUME_NONNULL_END

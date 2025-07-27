//
//  KeyboardSupport.h
//  Selene
//
//  Created by Noé Barlet on 27/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

// Delegate protocol for keyboard presence notifications
@protocol KeyboardSupportDelegate <NSObject>

- (void)keyboardPresenceChanged;

@end

@interface KeyboardSupport : NSObject

@property (nonatomic, weak) id<KeyboardSupportDelegate> delegate;

// Initialization
- (instancetype)init;

// Control methods
- (void)startKeyboardSupport;
- (void)stopKeyboardSupport;
- (void)cleanup;

// Status checking
+ (BOOL)hasConnectedKeyboard;

@end

NS_ASSUME_NONNULL_END

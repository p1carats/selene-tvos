//
//  MouseSupport.h
//  Selene
//
//  Created by Noé Barlet on 27/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

// Delegate protocol for mouse presence notifications
@protocol MouseSupportDelegate <NSObject>

- (void)mousePresenceChanged;

@end

@interface MouseSupport : NSObject

@property (nonatomic, weak) id<MouseSupportDelegate> delegate;

// Initialization
- (instancetype)init;

// Control methods
- (void)startMouseSupport;
- (void)stopMouseSupport;
- (void)cleanup;

// Status checking
+ (BOOL)hasConnectedMouse;

@end

NS_ASSUME_NONNULL_END

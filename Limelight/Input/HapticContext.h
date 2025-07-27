//
//  HapticContext.h
//  Selene
//
//  Created by Noé Barlet on 27/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;
@import CoreHaptics;
@import GameController;

NS_ASSUME_NONNULL_BEGIN

@interface HapticContext : NSObject

// Core functionality
- (void)setMotorAmplitude:(uint16_t)amplitude;
- (void)cleanup;

// Factory methods for different haptic types
+ (nullable HapticContext *)createContextForHighFreqMotor:(GCController *)gamepad;
+ (nullable HapticContext *)createContextForLowFreqMotor:(GCController *)gamepad;
+ (nullable HapticContext *)createContextForLeftTrigger:(GCController *)gamepad;
+ (nullable HapticContext *)createContextForRightTrigger:(GCController *)gamepad;

// Convenience methods
+ (nullable HapticContext *)createContextForGamepad:(GCController *)gamepad
                                           locality:(GCHapticsLocality)locality;

// Batch operations
- (void)setMotorAmplitudeSmooth:(uint16_t)amplitude duration:(NSTimeInterval)duration;
- (void)stopWithFadeOut:(NSTimeInterval)fadeOutTime;

@end

NS_ASSUME_NONNULL_END

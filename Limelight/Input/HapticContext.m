//
//  HapticContext.m
//  Selene
//
//  Created by Noé Barlet on 27/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import CoreHaptics;
@import GameController;

#import "HapticContext.h"
#import "Logger.h"

@implementation HapticContext {
    GCControllerPlayerIndex _playerIndex;
    CHHapticEngine *_hapticEngine;
    id<CHHapticPatternPlayer> _hapticPlayer;
    BOOL _isPlaying;
    uint16_t _currentAmplitude;
    NSLock *_hapticLock;
}

- (instancetype)initWithGamepad:(GCController *)gamepad locality:(GCHapticsLocality)locality {
    self = [super init];
    if (self) {
        if (!gamepad.haptics) {
            Log(LOG_W, @"Controller %ld does not support haptics", (long)gamepad.playerIndex);
            return nil;
        }
        
        if (![gamepad.haptics.supportedLocalities containsObject:locality]) {
            Log(LOG_W, @"Controller %ld does not support haptic locality: %@", (long)gamepad.playerIndex, locality);
            return nil;
        }
        
        _playerIndex = gamepad.playerIndex;
        _hapticLock = [[NSLock alloc] init];
        
        if (![self initializeHapticEngine:gamepad locality:locality]) {
            return nil;
        }
    }
    return self;
}

- (BOOL)initializeHapticEngine:(GCController *)gamepad locality:(GCHapticsLocality)locality {
    _hapticEngine = [gamepad.haptics createEngineWithLocality:locality];
    if (!_hapticEngine) {
        Log(LOG_W, @"Controller %ld: Failed to create haptic engine", (long)_playerIndex);
        return NO;
    }
    
    NSError *error;
    if (![_hapticEngine startAndReturnError:&error]) {
        Log(LOG_W, @"Controller %ld: Haptic engine failed to start: %@", (long)_playerIndex, error);
        return NO;
    }
    
    [self setupHapticEngineCallbacks];
    return YES;
}

- (void)setupHapticEngineCallbacks {
    __weak typeof(self) weakSelf = self;
    
    _hapticEngine.stoppedHandler = ^(CHHapticEngineStoppedReason stoppedReason) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        Log(LOG_W, @"Controller %ld: Haptic engine stopped: %ld", (long)strongSelf->_playerIndex, (long)stoppedReason);
        
        [strongSelf->_hapticLock lock];
        strongSelf->_hapticPlayer = nil;
        strongSelf->_hapticEngine = nil;
        strongSelf->_isPlaying = NO;
        [strongSelf->_hapticLock unlock];
    };
    
    _hapticEngine.resetHandler = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        Log(LOG_W, @"Controller %ld: Haptic engine reset", (long)strongSelf->_playerIndex);
        
        [strongSelf->_hapticLock lock];
        strongSelf->_hapticPlayer = nil;
        strongSelf->_isPlaying = NO;
        [strongSelf->_hapticEngine startAndReturnError:nil];
        [strongSelf->_hapticLock unlock];
    };
}

- (void)cleanup {
    [_hapticLock lock];
    
    if (_hapticPlayer) {
        [_hapticPlayer cancelAndReturnError:nil];
        _hapticPlayer = nil;
    }
    if (_hapticEngine) {
        [_hapticEngine stopWithCompletionHandler:nil];
        _hapticEngine = nil;
    }
    _isPlaying = NO;
    
    [_hapticLock unlock];
}

- (void)setMotorAmplitude:(uint16_t)amplitude {
    if (_currentAmplitude == amplitude) {
        return; // Skip if no change
    }
    _currentAmplitude = amplitude;
    
    [self setMotorAmplitudeInternal:amplitude];
}

- (void)setMotorAmplitudeInternal:(uint16_t)amplitude {
    [_hapticLock lock];
    
    if (!_hapticEngine) {
        [_hapticLock unlock];
        return;
    }
    
    NSError *error;
    
    // Stop the effect if amplitude is 0
    if (amplitude == 0) {
        if (_isPlaying && _hapticPlayer) {
            [_hapticPlayer stopAtTime:0 error:&error];
            _isPlaying = NO;
        }
        [_hapticLock unlock];
        return;
    }
    
    // Create player if needed
    if (!_hapticPlayer) {
        if (![self createHapticPlayerLocked]) {
            [_hapticLock unlock];
            return;
        }
    }
    
    // Update intensity immediately
    float normalizedAmplitude = amplitude / 65535.0f;
    CHHapticDynamicParameter *intensityParameter = [[CHHapticDynamicParameter alloc] 
        initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl 
        value:normalizedAmplitude 
        relativeTime:0];
    
    [_hapticPlayer sendParameters:@[intensityParameter] atTime:CHHapticTimeImmediate error:&error];
    if (error) {
        Log(LOG_W, @"Controller %ld: Haptic parameter update failed: %@", (long)_playerIndex, error);
        [_hapticLock unlock];
        return;
    }
    
    // Start playback if not already playing
    if (!_isPlaying) {
        [_hapticPlayer startAtTime:0 error:&error];
        if (error) {
            _hapticPlayer = nil;
            _isPlaying = NO; // Ensure consistent state
            Log(LOG_W, @"Controller %ld: Haptic playback start failed: %@", (long)_playerIndex, error);
            [_hapticLock unlock];
            return;
        }
        _isPlaying = YES;
    }
    
    [_hapticLock unlock];
}

- (BOOL)createHapticPlayerLocked {
    // Called while _hapticLock is already held
    NSError *error;
    
    // Create continuous haptic event with initial intensity of 1.0
    CHHapticEventParameter *intensityParameter = [[CHHapticEventParameter alloc] 
        initWithParameterID:CHHapticEventParameterIDHapticIntensity 
        value:1.0f];
    
    CHHapticEvent *hapticEvent = [[CHHapticEvent alloc] 
        initWithEventType:CHHapticEventTypeHapticContinuous 
        parameters:@[intensityParameter] 
        relativeTime:0 
        duration:GCHapticDurationInfinite];
    
    CHHapticPattern *hapticPattern = [[CHHapticPattern alloc] 
        initWithEvents:@[hapticEvent] 
        parameters:@[] 
        error:&error];
    
    if (error) {
        Log(LOG_W, @"Controller %ld: Haptic pattern creation failed: %@", (long)_playerIndex, error);
        return NO;
    }
    
    _hapticPlayer = [_hapticEngine createPlayerWithPattern:hapticPattern error:&error];
    if (error) {
        Log(LOG_W, @"Controller %ld: Haptic player creation failed: %@", (long)_playerIndex, error);
        return NO;
    }
    
    return YES;
}

- (BOOL)createHapticPlayer {
    // Public method that acquires lock
    [_hapticLock lock];
    BOOL result = [self createHapticPlayerLocked];
    [_hapticLock unlock];
    return result;
}

- (void)setMotorAmplitudeSmooth:(uint16_t)amplitude duration:(NSTimeInterval)duration {
    [_hapticLock lock];
    
    if (!_hapticEngine || !_hapticPlayer) {
        [_hapticLock unlock];
        return;
    }
    
    NSError *error;
    float normalizedAmplitude = amplitude / 65535.0f;
    
    CHHapticDynamicParameter *intensityParameter = [[CHHapticDynamicParameter alloc] 
        initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl 
        value:normalizedAmplitude 
        relativeTime:duration];
    
    [_hapticPlayer sendParameters:@[intensityParameter] atTime:CHHapticTimeImmediate error:&error];
    if (error) {
        Log(LOG_W, @"Controller %ld: Smooth haptic update failed: %@", (long)_playerIndex, error);
    }
    
    [_hapticLock unlock];
}

- (void)stopWithFadeOut:(NSTimeInterval)fadeOutTime {
    [_hapticLock lock];
    
    if (_isPlaying && _hapticPlayer) {
        NSError *error;
        CHHapticDynamicParameter *intensityParameter = [[CHHapticDynamicParameter alloc] 
            initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl 
            value:0.0f 
            relativeTime:fadeOutTime];
        
        [_hapticPlayer sendParameters:@[intensityParameter] atTime:CHHapticTimeImmediate error:&error];
        
        // Use weak reference to avoid retain cycle and check object validity
        __weak typeof(self) weakSelf = self;
        [NSTimer scheduledTimerWithTimeInterval:fadeOutTime repeats:NO block:^(NSTimer *timer) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return; // Object was deallocated
            
            [strongSelf->_hapticLock lock];
            if (strongSelf->_hapticPlayer) {
                [strongSelf->_hapticPlayer stopAtTime:0 error:nil];
                strongSelf->_isPlaying = NO;
            }
            [strongSelf->_hapticLock unlock];
        }];
    }
    
    [_hapticLock unlock];
}

// Factory methods
+ (nullable HapticContext *)createContextForGamepad:(GCController *)gamepad locality:(GCHapticsLocality)locality {
    return [[HapticContext alloc] initWithGamepad:gamepad locality:locality];
}

+ (nullable HapticContext *)createContextForHighFreqMotor:(GCController *)gamepad {
    return [HapticContext createContextForGamepad:gamepad locality:GCHapticsLocalityRightHandle];
}

+ (nullable HapticContext *)createContextForLowFreqMotor:(GCController *)gamepad {
    return [HapticContext createContextForGamepad:gamepad locality:GCHapticsLocalityLeftHandle];
}

+ (nullable HapticContext *)createContextForLeftTrigger:(GCController *)gamepad {
    return [HapticContext createContextForGamepad:gamepad locality:GCHapticsLocalityLeftTrigger];
}

+ (nullable HapticContext *)createContextForRightTrigger:(GCController *)gamepad {
    return [HapticContext createContextForGamepad:gamepad locality:GCHapticsLocalityRightTrigger];
}

- (void)dealloc {
    [self cleanup];
}

@end

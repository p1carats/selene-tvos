//
//  AudioDecoderRenderer.h
//  Selene
//
//  Created by Noé Barlet on 28/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@class OpusMultistreamConfiguration;

@interface AudioDecoderRenderer : NSObject

- (instancetype)init;

- (int)setupWithAudioConfiguration:(int)audioConfiguration
                        opusConfig:(OpusMultistreamConfiguration*)opusConfig
                             flags:(int)flags;

- (void)cleanup;

- (void)decodeAndPlaySample:(int8_t*)sampleData length:(int)sampleLength;

@end

NS_ASSUME_NONNULL_END

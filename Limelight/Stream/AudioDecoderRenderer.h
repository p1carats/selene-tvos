//
//  AudioDecoderRenderer.h
//  Selene
//
//  Created by Noé Barlet on 28/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;
@import GameStreamKit;

NS_ASSUME_NONNULL_BEGIN

@interface AudioDecoderRenderer : NSObject

- (instancetype)init;

- (int)setupWithAudioConfiguration:(int)audioConfiguration
                        opusConfig:(POPUS_MULTISTREAM_CONFIGURATION)opusConfig
                           context:(void*)context
                             flags:(int)flags;

- (void)cleanup;

- (void)decodeAndPlaySample:(char*)sampleData length:(int)sampleLength;

@end

NS_ASSUME_NONNULL_END

//
//  AudioDecoderRenderer.m
//  Selene
//
//  Created by Noé Barlet on 28/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import AVFoundation;
@import os.lock;

#import "AudioDecoderRenderer.h"
#import "Logger.h"

#include "opus_multistream.h"

@implementation AudioDecoderRenderer {
    OpusMSDecoder* _opusDecoder;
    AVAudioEngine* _audioEngine;
    AVAudioPlayerNode* _playerNode;
    AVAudioFormat* _audioFormat;
    NSMutableArray* _audioBufferQueue;
    os_unfair_lock _audioBufferLock;
    OPUS_MULTISTREAM_CONFIGURATION _audioConfig;
    NSMutableData* _audioBuffer;
    int _audioFrameSize;
    BOOL _isCleaningUp;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _audioBufferLock = OS_UNFAIR_LOCK_INIT;
        _isCleaningUp = NO;
    }
    return self;
}

- (int)setupWithAudioConfiguration:(int)audioConfiguration
                        opusConfig:(POPUS_MULTISTREAM_CONFIGURATION)opusConfig
                           context:(void*)context
                             flags:(int)flags {
    int err;
    NSError* error = nil;
    
    // Initialize audio session
    AVAudioSession* session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryPlayback
                         mode:AVAudioSessionModeDefault
                      options:AVAudioSessionCategoryOptionMixWithOthers
                        error:&error]) {
        Log(LOG_E, @"Failed to set audio session category: %@", error.localizedDescription);
        return -1;
    }
        
    if (![session setActive:YES error:&error]) {
        Log(LOG_E, @"Failed to activate audio session: %@", error.localizedDescription);
        return -1;
    }
    
    // Create audio engine and player node
    _audioEngine = [[AVAudioEngine alloc] init];
    _playerNode = [[AVAudioPlayerNode alloc] init];
    
    // Support full multi-channel audio (stereo, 5.1, 7.1)
    double sampleRate = opusConfig->sampleRate;
    AVAudioChannelCount channelCount = (AVAudioChannelCount)opusConfig->channelCount;
    
    Log(LOG_I, @"Initializing audio with %d channels at %g Hz", channelCount, sampleRate);
    
    // Create proper channel layout
    AVAudioChannelLayout* channelLayout;
    if (channelCount == 2) {
        // Stereo
        channelLayout = [AVAudioChannelLayout layoutWithLayoutTag:kAudioChannelLayoutTag_Stereo];
    } else if (channelCount == 6) {
        // 5.1 surround / LPCM 7.1
        channelLayout = [AVAudioChannelLayout layoutWithLayoutTag:kAudioChannelLayoutTag_MPEG_5_1_A];
    } else if (channelCount == 8) {
        // 7.1 surround / LPCM 7.1
        channelLayout = [AVAudioChannelLayout layoutWithLayoutTag:kAudioChannelLayoutTag_MPEG_7_1_A];
    } else {
        Log(LOG_E, @"Unknown channel layout");
        [self cleanup];
        return -1;
    }
    
    _audioFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate
                                                            channelLayout:channelLayout];
    
    if (_audioFormat == nil) {
        Log(LOG_E, @"Failed to create audio format");
        [self cleanup];
        return -1;
    }
    
    // Attach and connect nodes with the multi-channel format
    [_audioEngine attachNode:_playerNode];
    [_audioEngine connect:_playerNode to:_audioEngine.mainMixerNode format:_audioFormat];
    
    // Start audio engine
    if (![_audioEngine startAndReturnError:&error]) {
        Log(LOG_E, @"Failed to start audio engine: %@", error.localizedDescription);
        [self cleanup];
        return -1;
    }
    
    _audioConfig = *opusConfig;
    _audioFrameSize = opusConfig->samplesPerFrame * sizeof(float) * opusConfig->channelCount;
    _audioBuffer = [NSMutableData dataWithLength:_audioFrameSize];
    if (_audioBuffer == nil || _audioBuffer.length != _audioFrameSize) {
        Log(LOG_E, @"Failed to allocate audio frame buffer");
        [self cleanup];
        return -1;
    }
    
    // Initialize buffer queue
    _audioBufferQueue = [[NSMutableArray alloc] init];
    
    _opusDecoder = opus_multistream_decoder_create(opusConfig->sampleRate,
                                                  opusConfig->channelCount,
                                                  opusConfig->streams,
                                                  opusConfig->coupledStreams,
                                                  opusConfig->mapping,
                                                  &err);
    if (_opusDecoder == NULL) {
        Log(LOG_E, @"Failed to create Opus decoder");
        [self cleanup];
        return -1;
    }
    
    [_playerNode play];
    
    return 0;
}

- (void)cleanup {
    // Set cleanup flag first to prevent race conditions
    os_unfair_lock_lock(&_audioBufferLock);
    _isCleaningUp = YES;
    os_unfair_lock_unlock(&_audioBufferLock);
    
    if (_playerNode != nil) {
        [_playerNode stop];
        _playerNode = nil;
    }
    
    if (_audioEngine != nil) {
        [_audioEngine stop];
        _audioEngine = nil;
    }
    
    if (_opusDecoder != NULL) {
        opus_multistream_decoder_destroy(_opusDecoder);
        _opusDecoder = NULL;
    }
    
    if (_audioBufferQueue != nil) {
        os_unfair_lock_lock(&_audioBufferLock);
        [_audioBufferQueue removeAllObjects];
        _audioBufferQueue = nil;
        os_unfair_lock_unlock(&_audioBufferLock);
    }
    
    if (_audioBuffer != nil) {
        _audioBuffer = nil;
    }
    
    _audioFormat = nil;
    
    // Deactivate audio session
    NSError* error = nil;
    AVAudioSession* session = [AVAudioSession sharedInstance];
    if (![session setActive:NO error:&error]) {
        Log(LOG_W, @"Failed to deactivate audio session: %@", error.localizedDescription);
    }
}

- (void)decodeAndPlaySample:(char*)sampleData length:(int)sampleLength {
    int decodeLen;
    
    // Check if we're cleaning up
    os_unfair_lock_lock(&_audioBufferLock);
    BOOL cleaningUp = _isCleaningUp;
    os_unfair_lock_unlock(&_audioBufferLock);
    
    if (cleaningUp) {
        return;
    }
    
    // Don't queue if there's already more than 30 ms of audio data waiting in queue
    if (LiGetPendingAudioDuration() > 30) {
        return;
    }

    float* outputBuffer = (float*)_audioBuffer.mutableBytes;

    decodeLen = opus_multistream_decode_float(_opusDecoder,
                                              (unsigned char*)sampleData,
                                              sampleLength,
                                              outputBuffer,
                                              _audioConfig.samplesPerFrame,
                                              0);
    if (decodeLen > 0) {
        // Provide backpressure on the queue to ensure too many frames don't build up
        os_unfair_lock_lock(&_audioBufferLock);
        NSUInteger queueSize = _audioBufferQueue.count;
        os_unfair_lock_unlock(&_audioBufferLock);
                
        while (queueSize > 10) {
            [NSThread sleepForTimeInterval:0.001f];
            os_unfair_lock_lock(&_audioBufferLock);
            queueSize = _audioBufferQueue.count;
            os_unfair_lock_unlock(&_audioBufferLock);
        }
        
        // Create AVAudioPCMBuffer with the multi-channel format
        AVAudioPCMBuffer* pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_audioFormat
                                                                    frameCapacity:decodeLen];
        
        if (pcmBuffer != nil) {
            pcmBuffer.frameLength = decodeLen;
            
            float* const* destChannels = pcmBuffer.floatChannelData;
            
            // Direct channel mapping for all configurations (stereo, 5.1, 7.1)
            // Opus decoder outputs interleaved multi-channel data
            // AVAudioPCMBuffer expects non-interleaved (planar) channel data
            for (int ch = 0; ch < _audioFormat.channelCount; ch++) {
                for (int i = 0; i < decodeLen; i++) {
                    destChannels[ch][i] = outputBuffer[i * _audioConfig.channelCount + ch];
                }
            }
            
            // Queue buffer
            os_unfair_lock_lock(&_audioBufferLock);
            [_audioBufferQueue addObject:pcmBuffer];
            os_unfair_lock_unlock(&_audioBufferLock);
            
            // Schedule buffer for playback
            [self scheduleNextBuffer];
        } else {
            Log(LOG_E, @"Failed to create audio buffer");
        }
    }
}

- (void)scheduleNextBuffer {
    AVAudioPCMBuffer* buffer = nil;
    
    os_unfair_lock_lock(&_audioBufferLock);
    if (_isCleaningUp || _audioBufferQueue == nil) {
        os_unfair_lock_unlock(&_audioBufferLock);
        return;
    }
    
    if (_audioBufferQueue.count > 0) {
        buffer = _audioBufferQueue.firstObject;
        [_audioBufferQueue removeObjectAtIndex:0];
    }
    os_unfair_lock_unlock(&_audioBufferLock);
    
    if (buffer != nil && _playerNode != nil) {
        [_playerNode scheduleBuffer:buffer completionHandler:^{
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self scheduleNextBuffer];
            });
        }];
    }
}

@end

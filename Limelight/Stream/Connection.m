//
//  Connection.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/19/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

@import AVFoundation;
@import GameStreamKit;
@import os.lock;
@import VideoToolbox;
@import UIKit;

#import "Connection.h"
#import "Utils.h"
#import "Logger.h"
#import "BandwidthTracker.h"
#import "StreamConfiguration.h"
#import "VideoDecoderRenderer.h"

#include "opus_multistream.h"

@implementation Connection {
    SERVER_INFORMATION _serverInfo;
    STREAM_CONFIGURATION _streamConfig;
    CONNECTION_LISTENER_CALLBACKS _clCallbacks;
    DECODER_RENDERER_CALLBACKS _drCallbacks;
    AUDIO_RENDERER_CALLBACKS _arCallbacks;
    char _hostString[256];
    char _appVersionString[32];
    char _gfeVersionString[32];
    char _rtspSessionUrl[128];
}

static NSLock* initLock;
static OpusMSDecoder* opusDecoder;
static id<ConnectionCallbacks> _callbacks;
static int lastFrameNumber;
static int activeVideoFormat;
static VideoStats currentVideoStats;
static VideoStats lastVideoStats;
static NSLock* videoStatsLock;

static AVAudioEngine* audioEngine;
static AVAudioPlayerNode* playerNode;
static AVAudioFormat* audioFormat;
static NSMutableArray* audioBufferQueue;
static os_unfair_lock audioBufferLock = OS_UNFAIR_LOCK_INIT;
static OPUS_MULTISTREAM_CONFIGURATION audioConfig;
static void* audioBuffer;
static int audioFrameSize;

static VideoDecoderRenderer* renderer;

static BandwidthTracker *bwTracker;

int DrDecoderSetup(int videoFormat, int width, int height, int redrawRate, void* context, int drFlags)
{
    [renderer setupWithVideoFormat:videoFormat width:width height:height frameRate:redrawRate];
    lastFrameNumber = 0;
    activeVideoFormat = videoFormat;
    Log(LOG_I, @"Active video format: 0x%x", activeVideoFormat);
    currentVideoStats = (VideoStats){0};
    lastVideoStats = (VideoStats){0};
    bwTracker = [[BandwidthTracker alloc] initWithWindowSeconds:10 bucketIntervalMs:250];
    return 0;
}

void DrCleanup(void)
{
    [renderer cleanup];
}

-(BandwidthTracker *) getBwTracker
{
    return bwTracker;
}

-(BOOL) getVideoStats:(VideoStats*)stats
{
    // We return lastVideoStats because it is a complete 1 second window
    [videoStatsLock lock];
    if (lastVideoStats.endTime != 0) {
        *stats = lastVideoStats;
        [videoStatsLock unlock];

        // Pull in the separately-collected renderer stats
        [renderer getAllStats:stats];

        return YES;
    }
    [videoStatsLock unlock];
    return NO;
}

-(NSString*) getActiveCodecName
{
    switch (activeVideoFormat)
    {
        case VIDEO_FORMAT_H264:
            return @"H.264";
        case VIDEO_FORMAT_H264_HIGH8_444:
            return @"H.264 4:4:4";
        case VIDEO_FORMAT_H265:
            return @"HEVC";
        case VIDEO_FORMAT_H265_REXT8_444:
            return @"HEVC 4:4:4";
        case VIDEO_FORMAT_H265_MAIN10:
            if (LiGetCurrentHostDisplayHdrMode()) {
                return @"HEVC Main 10 HDR";
            }
            else {
                return @"HEVC Main 10 SDR";
            }
        case VIDEO_FORMAT_H265_REXT10_444:
            if (LiGetCurrentHostDisplayHdrMode()) {
                return @"HEVC Main 10 HDR 4:4:4";
            }
            else {
                return @"HEVC Main 10 SDR 4:4:4";
            }
        default:
            return @"UNKNOWN";
    }
}

int DrSubmitDecodeUnit(PDECODE_UNIT decodeUnit)
{
    int offset = 0;
    int ret;
    CFTimeInterval decodeStartTime = CACurrentMediaTime();

    unsigned char* data = (unsigned char*) malloc(decodeUnit->fullLength);
    if (data == NULL) {
        // A frame was lost due to OOM condition
        return DR_NEED_IDR;
    }
    
    CFTimeInterval now = CACurrentMediaTime();
    if (!lastFrameNumber) {
        currentVideoStats.startTime = now;
        lastFrameNumber = decodeUnit->frameNumber;
    }
    else {
        // Flip stats roughly every second
        if (now - currentVideoStats.startTime >= 1.0f) {
            currentVideoStats.endTime = now;
            
            [videoStatsLock lock];
            lastVideoStats = currentVideoStats;
            [videoStatsLock unlock];
            
            currentVideoStats = (VideoStats){0};
            currentVideoStats.startTime = now;
        }
        
        // Any frame number greater than m_LastFrameNumber + 1 represents a dropped frame
        int droppedFrames = decodeUnit->frameNumber - (lastFrameNumber + 1);
        if (droppedFrames > 0) {
            currentVideoStats.networkDroppedFrames += droppedFrames;
            currentVideoStats.totalFrames += droppedFrames;

            Log(LOG_W, @"Network dropped %d frame(s): %d - %d", droppedFrames, lastFrameNumber + 1, decodeUnit->frameNumber - 1);
        }
        lastFrameNumber = decodeUnit->frameNumber;
    }
    
    if (decodeUnit->frameHostProcessingLatency != 0) {
        if (currentVideoStats.minHostProcessingLatency == 0 || decodeUnit->frameHostProcessingLatency < currentVideoStats.minHostProcessingLatency) {
            currentVideoStats.minHostProcessingLatency = decodeUnit->frameHostProcessingLatency;
        }
        
        if (decodeUnit->frameHostProcessingLatency > currentVideoStats.maxHostProcessingLatency) {
            currentVideoStats.maxHostProcessingLatency = decodeUnit->frameHostProcessingLatency;
        }
        
        currentVideoStats.framesWithHostProcessingLatency++;
        currentVideoStats.totalHostProcessingLatency += decodeUnit->frameHostProcessingLatency;
    }
    
    currentVideoStats.receivedFrames++;
    currentVideoStats.totalFrames++;

    [bwTracker addBytes:decodeUnit->fullLength];

    PLENTRY entry = decodeUnit->bufferList;
    while (entry != NULL) {
        // Submit parameter set NALUs directly since no copy is required by the decoder
        if (entry->bufferType != BUFFER_TYPE_PICDATA) {
            ret = [renderer submitDecodeBuffer:(unsigned char*)entry->data
                                        length:entry->length
                                    bufferType:entry->bufferType
                                    decodeUnit:decodeUnit
                               decodeStartTime:decodeStartTime];
            if (ret != DR_OK) {
                free(data);
                return ret;
            }
        }
        else {
            memcpy(&data[offset], entry->data, entry->length);
            offset += entry->length;
        }

        entry = entry->next;
    }

    // This function will take our picture data buffer
    return [renderer submitDecodeBuffer:data
                                 length:offset
                             bufferType:BUFFER_TYPE_PICDATA
                             decodeUnit:decodeUnit
                        decodeStartTime:decodeStartTime];
}

int ArInit(int audioConfiguration, POPUS_MULTISTREAM_CONFIGURATION opusConfig, void* context, int flags)
{
    int err;
    NSError* error = nil;
    
    // Initialize audio session
    AVAudioSession* session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error]) {
        Log(LOG_E, @"Failed to set audio session category: %@", error.localizedDescription);
        return -1;
    }
        
    if (![session setActive:YES error:&error]) {
        Log(LOG_E, @"Failed to activate audio session: %@", error.localizedDescription);
        return -1;
    }
    
    // Create audio engine and player node
    audioEngine = [[AVAudioEngine alloc] init];
    playerNode = [[AVAudioPlayerNode alloc] init];
    
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
        ArCleanup();
        return -1;
    }
    
    audioFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate
                                                            channelLayout:channelLayout];
    
    if (audioFormat == nil) {
        Log(LOG_E, @"Failed to create audio format");
        ArCleanup();
        return -1;
    }
    
    // Attach and connect nodes with the multi-channel format
    [audioEngine attachNode:playerNode];
    [audioEngine connect:playerNode to:audioEngine.mainMixerNode format:audioFormat];
    
    // Start audio engine
    if (![audioEngine startAndReturnError:&error]) {
        Log(LOG_E, @"Failed to start audio engine: %@", error.localizedDescription);
        ArCleanup();
        return -1;
    }
    
    audioConfig = *opusConfig;
    audioFrameSize = opusConfig->samplesPerFrame * sizeof(float) * opusConfig->channelCount;
    audioBuffer = malloc(audioFrameSize);
    if (audioBuffer == NULL) {
        Log(LOG_E, @"Failed to allocate audio frame buffer");
        ArCleanup();
        return -1;
    }
    
    // Initialize buffer queue
    audioBufferQueue = [[NSMutableArray alloc] init];
    
    opusDecoder = opus_multistream_decoder_create(opusConfig->sampleRate,
                                                  opusConfig->channelCount,
                                                  opusConfig->streams,
                                                  opusConfig->coupledStreams,
                                                  opusConfig->mapping,
                                                  &err);
    if (opusDecoder == NULL) {
        Log(LOG_E, @"Failed to create Opus decoder");
        ArCleanup();
        return -1;
    }
    
    [playerNode play];
    
    return 0;
}

void ArCleanup(void)
{
    if (opusDecoder != NULL) {
        opus_multistream_decoder_destroy(opusDecoder);
        opusDecoder = NULL;
    }
    
    if (playerNode != nil) {
        [playerNode stop];
        playerNode = nil;
    }
    
    if (audioEngine != nil) {
        [audioEngine stop];
        audioEngine = nil;
    }
    
    if (audioBufferQueue != nil) {
        os_unfair_lock_lock(&audioBufferLock);
        [audioBufferQueue removeAllObjects];
        os_unfair_lock_unlock(&audioBufferLock);
        audioBufferQueue = nil;
    }
    
    if (audioBuffer != NULL) {
        free(audioBuffer);
        audioBuffer = NULL;
    }
    
    audioFormat = nil;
}

void ArDecodeAndPlaySample(char* sampleData, int sampleLength)
{
    int decodeLen;
    
    // Don't queue if there's already more than 30 ms of audio data waiting in queue
    if (LiGetPendingAudioDuration() > 30) {
        return;
    }

    decodeLen = opus_multistream_decode_float(opusDecoder,
                                              (unsigned char*)sampleData,
                                              sampleLength,
                                              (float*)audioBuffer,
                                              audioConfig.samplesPerFrame,
                                              0);
    if (decodeLen > 0) {
        // Provide backpressure on the queue to ensure too many frames don't build up
        os_unfair_lock_lock(&audioBufferLock);
        NSUInteger queueSize = audioBufferQueue.count;
        os_unfair_lock_unlock(&audioBufferLock);
                
        while (queueSize > 10) {
            [NSThread sleepForTimeInterval:0.001f];
            os_unfair_lock_lock(&audioBufferLock);
            queueSize = audioBufferQueue.count;
            os_unfair_lock_unlock(&audioBufferLock);
        }
        
        // Create AVAudioPCMBuffer with the multi-channel format
        AVAudioPCMBuffer* pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audioFormat
                                                                    frameCapacity:decodeLen];
        
        if (pcmBuffer != nil) {
            pcmBuffer.frameLength = decodeLen;
            
            float* sourceData = (float*)audioBuffer;
            float* const* destChannels = pcmBuffer.floatChannelData;
            
            // Direct channel mapping for all configurations (stereo, 5.1, 7.1)
            // Opus decoder outputs interleaved multi-channel data
            // AVAudioPCMBuffer expects non-interleaved (planar) channel data
            for (int ch = 0; ch < audioFormat.channelCount; ch++) {
                for (int i = 0; i < decodeLen; i++) {
                    destChannels[ch][i] = sourceData[i * audioConfig.channelCount + ch];
                }
            }
            
            // Queue buffer
            os_unfair_lock_lock(&audioBufferLock);
            [audioBufferQueue addObject:pcmBuffer];
            os_unfair_lock_unlock(&audioBufferLock);
            
            // Schedule buffer for playback
            scheduleNextBuffer();
        } else {
            Log(LOG_E, @"Failed to create audio buffer");
        }
    }
}

void scheduleNextBuffer(void) {
    AVAudioPCMBuffer* buffer = nil;
    
    os_unfair_lock_lock(&audioBufferLock);
    if (audioBufferQueue.count > 0) {
        buffer = audioBufferQueue.firstObject;
        [audioBufferQueue removeObjectAtIndex:0];
    }
    os_unfair_lock_unlock(&audioBufferLock);
    
    if (buffer != nil) {
        [playerNode scheduleBuffer:buffer completionHandler:^{
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                scheduleNextBuffer();
            });
        }];
    }
}

void ClStageStarting(int stage)
{
    [_callbacks stageStarting:LiGetStageName(stage)];
}

void ClStageComplete(int stage)
{
    [_callbacks stageComplete:LiGetStageName(stage)];
}

void ClStageFailed(int stage, int errorCode)
{
    [_callbacks stageFailed:LiGetStageName(stage) withError:errorCode portTestFlags:LiGetPortFlagsFromStage(stage)];
}

void ClConnectionStarted(void)
{
    [_callbacks connectionStarted];
}

void ClConnectionTerminated(int errorCode)
{
    [_callbacks connectionTerminated: errorCode];
}

void ClLogMessage(const char* format, ...)
{
    va_list va;
    va_start(va, format);
    vfprintf(stderr, format, va);
    va_end(va);
}

void ClRumble(unsigned short controllerNumber, unsigned short lowFreqMotor, unsigned short highFreqMotor)
{
    [_callbacks rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

void ClConnectionStatusUpdate(int status)
{
    [_callbacks connectionStatusUpdate:status];
}

void ClSetHdrMode(bool enabled)
{
    [renderer setHdrMode:enabled];
    [_callbacks setHdrMode:enabled];
}

void ClRumbleTriggers(uint16_t controllerNumber, uint16_t leftTriggerMotor, uint16_t rightTriggerMotor)
{
    [_callbacks rumbleTriggers:controllerNumber leftTrigger:leftTriggerMotor rightTrigger:rightTriggerMotor];
}

void ClSetMotionEventState(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz)
{
    [_callbacks setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

void ClSetControllerLED(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b)
{
    [_callbacks setControllerLed:controllerNumber r:r g:g b:b];
}

-(void) terminate
{
    // Interrupt any action blocking LiStartConnection(). This is
    // thread-safe and done outside initLock on purpose, since we
    // won't be able to acquire it if LiStartConnection is in
    // progress.
    LiInterruptConnection();
    
    // We dispatch this async to get out because this can be invoked
    // on a thread inside common and we don't want to deadlock. It also avoids
    // blocking on the caller's thread waiting to acquire initLock.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [initLock lock];
        LiStopConnection();
        [initLock unlock];
    });
}

-(instancetype) initWithConfig:(StreamConfiguration*)config renderer:(VideoDecoderRenderer*)myRenderer connectionCallbacks:(id<ConnectionCallbacks>)callbacks
{
    self = [super init];

    // Use a lock to ensure that only one thread is initializing
    // or deinitializing a connection at a time.
    if (initLock == nil) {
        initLock = [[NSLock alloc] init];
    }
    
    if (videoStatsLock == nil) {
        videoStatsLock = [[NSLock alloc] init];
    }
    
    NSString *rawAddress = [Utils addressPortStringToAddress:config.host];
    strncpy(_hostString,
            [rawAddress cStringUsingEncoding:NSUTF8StringEncoding],
            sizeof(_hostString) - 1);
    strncpy(_appVersionString,
            [config.appVersion cStringUsingEncoding:NSUTF8StringEncoding],
            sizeof(_appVersionString) - 1);
    if (config.gfeVersion != nil) {
        strncpy(_gfeVersionString,
                [config.gfeVersion cStringUsingEncoding:NSUTF8StringEncoding],
                sizeof(_gfeVersionString) - 1);
    }
    if (config.rtspSessionUrl != nil) {
        strncpy(_rtspSessionUrl,
                [config.rtspSessionUrl cStringUsingEncoding:NSUTF8StringEncoding],
                sizeof(_rtspSessionUrl) - 1);
    }

    LiInitializeServerInformation(&_serverInfo);
    _serverInfo.address = _hostString;
    _serverInfo.serverInfoAppVersion = _appVersionString;
    if (config.gfeVersion != nil) {
        _serverInfo.serverInfoGfeVersion = _gfeVersionString;
    }
    if (config.rtspSessionUrl != nil) {
        _serverInfo.rtspSessionUrl = _rtspSessionUrl;
    }
    _serverInfo.serverCodecModeSupport = config.serverCodecModeSupport;

    renderer = myRenderer;
    _callbacks = callbacks;

    // Check for low power mode which limits framerate to 60
    if (config.frameRate > 60 && [[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
        Log(LOG_W, @"Limiting stream to 60fps because device is in low power mode");
        config.frameRate = 60;
    }

    // Lower to 90fps on Vision Pro
    NSInteger deviceFps = UIScreen.mainScreen.maximumFramesPerSecond;
    if (deviceFps < config.frameRate) {
        Log(LOG_W, @"Limiting stream to %dfps due to max refresh rate", deviceFps);
        config.frameRate = (int)deviceFps;
    }

    LiInitializeStreamConfiguration(&_streamConfig);
    _streamConfig.width = config.width;
    _streamConfig.height = config.height;
    _streamConfig.fps = config.frameRate;
    _streamConfig.bitrate = config.bitRate;
    _streamConfig.supportedVideoFormats = config.supportedVideoFormats;
    _streamConfig.audioConfiguration = config.audioConfiguration;

    // Since we require iOS 12 or above, we're guaranteed to be running
    // on a 64-bit device with ARMv8 crypto instructions, so we don't
    // need to check for that here.
    _streamConfig.encryptionFlags = ENCFLG_ALL;
    
    if ([Utils isActiveNetworkVPN]) {
        // Force remote streaming mode when a VPN is connected
        _streamConfig.streamingRemotely = STREAM_CFG_REMOTE;
        _streamConfig.packetSize = 1024;
    }
    else {
        // Detect remote streaming automatically based on the IP address of the target
        _streamConfig.streamingRemotely = STREAM_CFG_AUTO;
        _streamConfig.packetSize = 1392;
    }

    memcpy(_streamConfig.remoteInputAesKey, [config.riKey bytes], [config.riKey length]);
    memset(_streamConfig.remoteInputAesIv, 0, 16);
    int riKeyId = htonl(config.riKeyId);
    memcpy(_streamConfig.remoteInputAesIv, &riKeyId, sizeof(riKeyId));

    LiInitializeVideoCallbacks(&_drCallbacks);
    _drCallbacks.setup = DrDecoderSetup;
    _drCallbacks.cleanup = DrCleanup;
    _drCallbacks.submitDecodeUnit = DrSubmitDecodeUnit;
    _drCallbacks.capabilities = CAPABILITY_DIRECT_SUBMIT |
                                CAPABILITY_REFERENCE_FRAME_INVALIDATION_HEVC;

    LiInitializeAudioCallbacks(&_arCallbacks);
    _arCallbacks.init = ArInit;
    _arCallbacks.cleanup = ArCleanup;
    _arCallbacks.decodeAndPlaySample = ArDecodeAndPlaySample;
    _arCallbacks.capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION;

    LiInitializeConnectionCallbacks(&_clCallbacks);
    _clCallbacks.stageStarting = ClStageStarting;
    _clCallbacks.stageComplete = ClStageComplete;
    _clCallbacks.stageFailed = ClStageFailed;
    _clCallbacks.connectionStarted = ClConnectionStarted;
    _clCallbacks.connectionTerminated = ClConnectionTerminated;
#ifdef DEBUG
    _clCallbacks.logMessage = ClLogMessage;
#endif
    _clCallbacks.rumble = ClRumble;
    _clCallbacks.connectionStatusUpdate = ClConnectionStatusUpdate;
    _clCallbacks.setHdrMode = ClSetHdrMode;
    _clCallbacks.rumbleTriggers = ClRumbleTriggers;
    _clCallbacks.setMotionEventState = ClSetMotionEventState;
    _clCallbacks.setControllerLED = ClSetControllerLED;

    return self;
}

-(void) main
{
    [initLock lock];
    LiStartConnection(&_serverInfo,
                      &_streamConfig,
                      &_clCallbacks,
                      &_drCallbacks,
                      &_arCallbacks,
                      NULL, 0,
                      NULL, 0);
    [initLock unlock];
}

@end

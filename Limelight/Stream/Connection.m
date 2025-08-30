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
#import "ConnectionCallbacks.h"
#import "Utils.h"
#import "Logger.h"
#import "BandwidthTracker.h"
#import "StreamConfiguration.h"
#import "AudioDecoderRenderer.h"
#import "VideoDecoderRenderer.h"

@implementation Connection {
    GameServerInformation* _serverInfo;
    GameStreamConfiguration* _streamConfig;
    NSString* _hostString;
    NSString* _appVersionString;
    NSString* _gfeVersionString;
    NSString* _rtspSessionUrl;
}

static NSLock* initLock;
static id<ConnectionCallbacks> _callbacks;
static int lastFrameNumber;
static int activeVideoFormat;
static VideoStats currentVideoStats;
static VideoStats lastVideoStats;
static NSLock* videoStatsLock;

static AudioDecoderRenderer* audioRenderer;
static VideoDecoderRenderer* renderer;

static BandwidthTracker *bwTracker;

// Initialize static variables once
+ (void)initialize {
    if (self == [Connection class]) {
        initLock = [[NSLock alloc] init];
        videoStatsLock = [[NSLock alloc] init];
    }
}

- (int)setupDecoderWithVideoFormat:(int)videoFormat width:(int)width height:(int)height redrawRate:(int32_t)redrawRate flags:(int)flags {
    [renderer setupWithVideoFormat:videoFormat width:width height:height frameRate:redrawRate];
    lastFrameNumber = 0;
    activeVideoFormat = videoFormat;
    Log(LOG_I, @"Active video format: 0x%x", activeVideoFormat);
    currentVideoStats = (VideoStats){0};
    lastVideoStats = (VideoStats){0};
    bwTracker = [[BandwidthTracker alloc] initWithWindowSeconds:10 bucketIntervalMs:250];
    return 0;
}

- (void)cleanupDecoder {
    [renderer cleanup];
}

- (BandwidthTracker*)getBwTracker {
    return bwTracker;
}

- (BOOL)getVideoStats:(VideoStats*)stats {
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

- (NSString*)getActiveCodecName {
    if (activeVideoFormat == StreamVideoFormat.h264) {
        return @"H.264";
    }
    else if (activeVideoFormat == StreamVideoFormat.h265) {
        return @"HEVC";
    }
    else if (activeVideoFormat == StreamVideoFormat.h265Rext8_444) {
        return @"HEVC 4:4:4";
    }
    else if (activeVideoFormat == StreamVideoFormat.h265Main10) {
        if ([GameStream getCurrentHostDisplayHdrMode]) {
            return @"HEVC Main 10 HDR";
        }
        else {
            return @"HEVC Main 10 SDR";
        }
    }
    else if (activeVideoFormat == StreamVideoFormat.h265Rext10_444) {
        if ([GameStream getCurrentHostDisplayHdrMode]) {
            return @"HEVC Main 10 HDR 4:4:4";
        }
        else {
            return @"HEVC Main 10 SDR 4:4:4";
        }
    }
    else {
        return @"UNKNOWN";
    }
}

- (int)submitDecodeUnit:(StreamDecodeUnit*)decodeUnit {
    // Early validation
    if (decodeUnit == NULL || decodeUnit.fullLength <= 0) {
        return DecoderRendererStatusNeedIdr;
    }
    
    int offset = 0;
    int ret;
    CFTimeInterval decodeStartTime = CACurrentMediaTime();
    
    unsigned char* data = (unsigned char*) malloc(decodeUnit.fullLength);
    if (data == NULL) {
        // A frame was lost due to OOM condition
        return DecoderRendererStatusNeedIdr;
    }
    
    CFTimeInterval now = CACurrentMediaTime();
    if (!lastFrameNumber) {
        currentVideoStats.startTime = now;
        lastFrameNumber = decodeUnit.frameNumber;
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
        int droppedFrames = decodeUnit.frameNumber - (lastFrameNumber + 1);
        if (droppedFrames > 0) {
            currentVideoStats.networkDroppedFrames += droppedFrames;
            currentVideoStats.totalFrames += droppedFrames;
            
            Log(LOG_W, @"Network dropped %d frame(s): %d - %d", droppedFrames, lastFrameNumber + 1, decodeUnit.frameNumber - 1);
        }
        lastFrameNumber = decodeUnit.frameNumber;
    }
    
    if (decodeUnit.frameHostProcessingLatency != 0) {
        if (currentVideoStats.minHostProcessingLatency == 0 || decodeUnit.frameHostProcessingLatency < currentVideoStats.minHostProcessingLatency) {
            currentVideoStats.minHostProcessingLatency = decodeUnit.frameHostProcessingLatency;
        }
        
        if (decodeUnit.frameHostProcessingLatency > currentVideoStats.maxHostProcessingLatency) {
            currentVideoStats.maxHostProcessingLatency = decodeUnit.frameHostProcessingLatency;
        }
        
        currentVideoStats.framesWithHostProcessingLatency++;
        currentVideoStats.totalHostProcessingLatency += decodeUnit.frameHostProcessingLatency;
    }
    
    currentVideoStats.receivedFrames++;
    currentVideoStats.totalFrames++;
    
    [bwTracker addBytes:decodeUnit.fullLength];
    
    for (StreamBufferEntry *entry in decodeUnit.bufferList) {
        // Submit parameter set NALUs directly since no copy is required by the decoder
        if (entry.bufferType != StreamBufferTypePictureData) {
            ret = [renderer submitDecodeBuffer:(unsigned char*)entry.data.bytes
                                        length:(int)entry.data.length
                                    bufferType:entry.bufferType
                                    decodeUnit:decodeUnit
                               decodeStartTime:decodeStartTime];
            if (ret != DecoderRendererStatusOk) {
                free(data);
                return ret;
            }
        }
        else {
            memcpy(&data[offset], entry.data.bytes, entry.data.length);
            offset += entry.data.length;
        }
    }
    
    // This function will take our picture data buffer
    return [renderer submitDecodeBuffer:data
                                 length:offset
                             bufferType:StreamBufferTypePictureData
                             decodeUnit:decodeUnit
                        decodeStartTime:decodeStartTime];
}

- (int)initializeRendererWithAudioConfiguration:(int)audioConfiguration opusConfig:(OpusMultistreamConfiguration*)opusConfig flags:(int)flags {
    return [audioRenderer setupWithAudioConfiguration:audioConfiguration
                                           opusConfig:opusConfig
                                                flags:flags];
}

- (void)cleanupRenderer {
    [audioRenderer cleanup];
}

- (void)decodeAndPlaySampleWithData:(int8_t*)sampleData length:(int)sampleLength {
    [audioRenderer decodeAndPlaySample:sampleData length:sampleLength];
}

- (void)stageStarting:(int)stage {
    const char* stageName = [GameStream getStageNameFor:stage].UTF8String;
    [_callbacks stageStarting:stageName];
}

- (void)stageComplete:(int)stage {
    const char* stageName = [GameStream getStageNameFor:stage].UTF8String;
    [_callbacks stageComplete:stageName];
}

- (void)stageFailed:(int)stage errorCode:(int)errorCode {
    const char* stageName = [GameStream getStageNameFor:stage].UTF8String;
    int portTestFlags = [GameStream getPortFlagsFromStage:stage];
    [_callbacks stageFailed:stageName withError:errorCode portTestFlags:portTestFlags];
}

- (void)connectionStarted {
    [_callbacks connectionStarted];
}

- (void)connectionTerminatedWithErrorCode:(int)errorCode {
    [_callbacks connectionTerminated: errorCode];
}

- (void)rumbleWithControllerNumber:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    [_callbacks rumbleController:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

- (void)connectionStatusUpdate:(int)status {
    [_callbacks connectionStatusUpdate:status];
}

- (void)setHdrModeWithEnabled:(BOOL)enabled {
    [renderer setHdrMode:enabled];
    [_callbacks setHdrMode:enabled];
}

- (void)rumbleTriggersWithControllerNumber:(uint16_t)controllerNumber leftTriggerMotor:(uint16_t)leftTriggerMotor rightTriggerMotor:(uint16_t)rightTriggerMotor {
    [_callbacks rumbleTriggersForController:controllerNumber leftTrigger:leftTriggerMotor rightTrigger:rightTriggerMotor];
}

- (void)setMotionEventStateWithControllerNumber:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    [_callbacks setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

- (void)setControllerLEDWithControllerNumber:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    [_callbacks setControllerLED:controllerNumber r:r g:g b:b];
}

-(void) terminate
{
    // Interrupt any action blocking LiStartConnection(). This is
    // thread-safe and done outside initLock on purpose, since we
    // won't be able to acquire it if LiStartConnection is in
    // progress.
    [GameStream interruptConnection];
    
    // Clean up audio renderer
    [audioRenderer cleanup];
    
    // We dispatch this async to get out because this can be invoked
    // on a thread inside common and we don't want to deadlock. It also avoids
    // blocking on the caller's thread waiting to acquire initLock.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [initLock lock];
        [GameStream stopConnection];
        [initLock unlock];
    });
}

- (instancetype)initWithConfig:(StreamConfiguration*)config renderer:(VideoDecoderRenderer*)myRenderer connectionCallbacks:(id<ConnectionCallbacks>)callbacks {
    self = [super init];
        
    NSString *rawAddress = [Utils addressPortStringToAddress:config.host];
    _hostString = [rawAddress copy];
    _appVersionString = [config.appVersion copy];
    _gfeVersionString = config.gfeVersion.length ? [config.gfeVersion copy] : nil;
    _rtspSessionUrl = config.rtspSessionUrl.length ? [config.rtspSessionUrl copy] : nil;
    
    _serverInfo = [[GameServerInformation alloc] initWithAddress:_hostString
                                            serverInfoAppVersion:_appVersionString
                                            serverInfoGfeVersion:_gfeVersionString
                                                  rtspSessionUrl:_rtspSessionUrl
                                          serverCodecModeSupport:config.serverCodecModeSupport];

    renderer = myRenderer;
    audioRenderer = [[AudioDecoderRenderer alloc] init];
    _callbacks = callbacks;

    _streamConfig = [[GameStreamConfiguration alloc] init];
    _streamConfig.width = config.width;
    _streamConfig.height = config.height;
    _streamConfig.fps = config.frameRate;
    _streamConfig.bitrate = config.bitRate;
    _streamConfig.supportedVideoFormats = config.supportedVideoFormats;
    _streamConfig.audioConfiguration = config.audioConfiguration;

    // Since we require iOS 12 or above, we're guaranteed to be running
    // on a 64-bit device with ARMv8 crypto instructions, so we don't
    // need to check for that here.
    _streamConfig.encryptionFlags = EncryptionFlags.all;
    
    if ([Utils isActiveNetworkVPN]) {
        // Force remote streaming mode when a VPN is connected
        _streamConfig.streamingRemotely = StreamModeRemote;
        _streamConfig.packetSize = 1024;
    }
    else {
        // Detect remote streaming automatically based on the IP address of the target
        _streamConfig.streamingRemotely = StreamModeAuto;
        _streamConfig.packetSize = 1392;
    }

    _streamConfig.remoteInputAesKey = config.riKey;
    NSMutableData *ivData = [NSMutableData dataWithLength:16];
    memset(ivData.mutableBytes, 0, 16);
    int riKeyId = htonl(config.riKeyId);
    memcpy(ivData.mutableBytes, &riKeyId, sizeof(riKeyId));
    _streamConfig.remoteInputAesIv = ivData;
    
    return self;
}

- (void)main {
    [initLock lock];
    [GameStream startConnectionWithServerInfo:_serverInfo
                                 streamConfig:_streamConfig
                          connectionCallbacks:self
                               videoCallbacks:self
                            videoCapabilities:RendererCapabilities.directSubmit | RendererCapabilities.referenceFrameInvalidationHevc
                               audioCallbacks:self
                            audioCapabilities:RendererCapabilities.supportsArbitraryAudioDuration];
    [initLock unlock];
}

@end

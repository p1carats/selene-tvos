//
//  TemporarySettings.h
//  Moonlight
//
//  Created by Cameron Gutman on 12/1/15.
//  Copyright © 2015 Moonlight Stream. All rights reserved.
//

@import Foundation;

#import "Settings+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

@interface TemporarySettings : NSObject

@property (nonatomic, strong) Settings * parent;

@property (nonatomic, strong) NSNumber * bitrate;
@property (nonatomic, strong) NSNumber * framerate;
@property (nonatomic, strong) NSNumber * height;
@property (nonatomic, strong) NSNumber * width;
@property (nonatomic, strong) NSNumber * audioConfig;
@property (nonatomic, strong) NSString * uniqueId;
@property (nonatomic) enum {
    CODEC_PREF_AUTO,
    CODEC_PREF_H264,
    CODEC_PREF_HEVC,
} preferredCodec;
@property (nonatomic, strong) NSNumber * frameQueueSize;
@property (nonatomic) BOOL multiController;
@property (nonatomic) BOOL swapABXYButtons;
@property (nonatomic) BOOL playAudioOnPC;
@property (nonatomic) BOOL optimizeGames;
@property (nonatomic) BOOL enableHdr;
@property (nonatomic) BOOL btMouseSupport;
@property (nonatomic) BOOL statsOverlay;
@property (nonatomic) BOOL enableGraphs;
@property (nonatomic, strong) NSNumber * graphOpacity;
@property (nonatomic, strong) NSNumber * renderingBackend;

- (instancetype) initFromSettings:(Settings*)settings;

@end

NS_ASSUME_NONNULL_END

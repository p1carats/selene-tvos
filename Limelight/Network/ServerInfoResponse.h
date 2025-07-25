//
//  ServerInfoResponse.h
//  Moonlight
//
//  Created by Diego Waxemberg on 2/1/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

@import Foundation;

#import "HttpResponse.h"

#define TAG_HOSTNAME @"hostname"
#define TAG_EXTERNAL_IP @"ExternalIP"
#define TAG_HTTPS_PORT @"HttpsPort"
#define TAG_LOCAL_IP @"LocalIP"
#define TAG_UNIQUE_ID @"uniqueid"
#define TAG_MAC_ADDRESS @"mac"
#define TAG_PAIR_STATUS @"PairStatus"
#define TAG_STATE @"state"
#define TAG_CURRENT_GAME @"currentgame"
#define TAG_EXTERNAL_PORT @"ExternalPort" // Sunshine extension

NS_ASSUME_NONNULL_BEGIN

@class TemporaryHost;

@interface ServerInfoResponse : HttpResponse <Response>

- (void) populateWithData:(NSData *)data;
- (void) populateHost:(TemporaryHost*)host;

@end

NS_ASSUME_NONNULL_END

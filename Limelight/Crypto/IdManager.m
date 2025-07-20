//
//  CertificateGenerator.h
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Security;

#import "IdManager.h"
#import "DataManager.h"
#import "Logger.h"

@implementation IdManager

+ (NSString*) getUniqueId {
    DataManager* dataMan = [[DataManager alloc] init];

    NSString* uniqueId = [dataMan getUniqueId];
    if (uniqueId == nil) {
        uniqueId = [IdManager generateUniqueId];
        [dataMan updateUniqueId:uniqueId];
        Log(LOG_I, @"No UUID found. Generated new UUID: %@", uniqueId);
    }
    
    return uniqueId;
}

+ (NSString*) generateUniqueId {
    UInt64 uuidLong;
    (void)SecRandomCopyBytes(kSecRandomDefault, sizeof(uuidLong), (uint8_t*)&uuidLong);
    return [NSString stringWithFormat:@"%016llx", uuidLong];
}

@end

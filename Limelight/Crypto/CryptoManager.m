//
//  CertificateGenerator.h
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import CommonCrypto;

#import "CryptoManager.h"
#import "Logger.h"

@implementation CryptoManager

- (NSData*) createAESKeyFromSaltSHA1:(NSData*)saltedPIN {
    return [[self SHA1HashData:saltedPIN] subdataWithRange:NSMakeRange(0, 16)];
}

- (NSData*) createAESKeyFromSaltSHA256:(NSData*)saltedPIN {
    return [[self SHA256HashData:saltedPIN] subdataWithRange:NSMakeRange(0, 16)];
}

- (NSData*) SHA1HashData:(NSData*)data {
    unsigned char sha1[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1([data bytes], (CC_LONG)[data length], sha1);
    NSData* bytes = [NSData dataWithBytes:sha1 length:sizeof(sha1)];
    return bytes;
}

- (NSData*) SHA256HashData:(NSData*)data {
    unsigned char sha256[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], sha256);
    NSData* bytes = [NSData dataWithBytes:sha256 length:sizeof(sha256)];
    return bytes;
}

- (NSData*) aesEncrypt:(NSData*)data withKey:(NSData*)key {
    NSMutableData* ciphertext = [NSMutableData dataWithLength:[data length]];
    size_t dataOutMoved = 0;
    CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt,
                                          kCCAlgorithmAES,
                                          kCCOptionECBMode,
                                          [key bytes],
                                          [key length],
                                          NULL, // No IV for ECB mode
                                          [data bytes],
                                          [data length],
                                          [ciphertext mutableBytes],
                                          [ciphertext length],
                                          &dataOutMoved);
    
    if (cryptStatus != kCCSuccess) {
        Log(LOG_E, @"Encryption failed with status: %d", cryptStatus);
        return nil;
    }
    
    [ciphertext setLength:dataOutMoved];
    return ciphertext;
}

- (NSData*) aesDecrypt:(NSData*)data withKey:(NSData*)key {
    NSMutableData* plaintext = [NSMutableData dataWithLength:[data length]];
    size_t dataOutMoved = 0;
    
    CCCryptorStatus cryptStatus = CCCrypt(kCCDecrypt,
                                          kCCAlgorithmAES,
                                          kCCOptionECBMode,
                                          [key bytes],
                                          [key length],
                                          NULL, // No IV for ECB mode
                                          [data bytes],
                                          [data length],
                                          [plaintext mutableBytes],
                                          [plaintext length],
                                          &dataOutMoved);
    
    if (cryptStatus != kCCSuccess) {
        Log(LOG_E, @"Decryption failed with status: %d", cryptStatus);
        return nil;
    }
    
    [plaintext setLength:dataOutMoved];
    return plaintext;
}

@end

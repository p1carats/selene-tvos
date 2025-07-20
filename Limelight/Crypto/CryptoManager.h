//
//  CryptoManager.h
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@interface CryptoManager : NSObject

// SHA operations
- (NSData*) SHA1HashData:(NSData*)data;
- (NSData*) SHA256HashData:(NSData*)data;

// Key derivation
- (NSData*) createAESKeyFromSaltSHA1:(NSData*)saltedPIN;
- (NSData*) createAESKeyFromSaltSHA256:(NSData*)saltedPIN;

// AES encryption/decryption
- (NSData*) aesEncrypt:(NSData*)data withKey:(NSData*)key;
- (NSData*) aesDecrypt:(NSData*)data withKey:(NSData*)key;

@end

NS_ASSUME_NONNULL_END

//
//  CertificateManager.h
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@interface CertificateManager : NSObject

// Certificate file operations
+ (NSData*) readCertFromFile;
+ (NSData*) readKeyFromFile;
+ (NSData*) readP12FromFile;
+ (void) generateKeyPairUsingSSL;

// Certificate operations
+ (NSData*) getSignatureFromCert:(NSData*)cert;
+ (NSData*) pemToDer:(NSData*)pemCertBytes;

// Digital signature operations
- (bool) verifySignature:(NSData *)data withSignature:(NSData*)signature andCert:(NSData*)cert;
- (NSData*) signData:(NSData*)data withKey:(NSData*)key;

@end

NS_ASSUME_NONNULL_END

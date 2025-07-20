//
//  CertificateSecret.m
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Security;

#import "CertificateSecret.h"

@implementation CertificateSecret

+ (NSString *)certificatePassword {
    static NSString * const kKeychainPasswordKey = @"SeleneCertificatePassword";

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"SeleneCryptoStore",
        (__bridge id)kSecAttrAccount: kKeychainPasswordKey,
        (__bridge id)kSecReturnData: @YES
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result) {
        NSData *data = (__bridge_transfer NSData *)result;
        NSString *existing = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (existing.length > 0) return existing;
    }

    NSString *generated = [CertificateSecret generateHexPasswordWithLength:16];
    NSData *passwordData = [generated dataUsingEncoding:NSUTF8StringEncoding];
    
    NSDictionary *addQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"SeleneCryptoStore",
        (__bridge id)kSecAttrAccount: kKeychainPasswordKey,
        (__bridge id)kSecValueData: passwordData
    };
    SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);

    return generated;
}

+ (NSString *)generateHexPasswordWithLength:(NSUInteger)byteCount {
    uint8_t buffer[byteCount];
    if (SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer) != errSecSuccess) {
        return nil;
    }

    NSMutableString *hex = [NSMutableString stringWithCapacity:byteCount * 2];
    for (NSUInteger i = 0; i < byteCount; i++) {
        [hex appendFormat:@"%02x", buffer[i]];
    }

    return hex;
}

@end

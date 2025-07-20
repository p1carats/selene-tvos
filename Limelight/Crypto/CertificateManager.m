//
//  CertificateManager.m
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import Security;

@import OpenSSL.sha;
@import OpenSSL.x509;
@import OpenSSL.pem;
@import OpenSSL.evp;

#import "CertificateManager.h"
#import "CertificateGenerator.h"
#import "Logger.h"

@implementation CertificateManager

static NSData* key = nil;
static NSData* cert = nil;
static NSData* p12 = nil;

+ (NSData*) readCertFromFile {
    if (cert == nil) {
        cert = [CertificateManager readCryptoObject:@"client.crt"];
    }
    return cert;
}

+ (NSData*) readKeyFromFile {
    if (key == nil) {
        key = [CertificateManager readCryptoObject:@"client.key"];
    }
    return key;
}

+ (NSData*) readP12FromFile {
    if (p12 == nil) {
        p12 = [CertificateManager readCryptoObject:@"client.p12"];
    }
    return p12;
}

+ (void) generateKeyPairUsingSSL {
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        if (![CertificateManager keyPairExists]) {
            Log(LOG_I, @"Generating Certificate... ");
            NSDictionary* certKeyPair = [CertificateGenerator generateCertKeyPair];
            if (!certKeyPair) {
                Log(LOG_E, @"Failed to generate certificate key pair");
                return;
            }
            
            NSData* certData = certKeyPair[@"certificate"];
            NSData* p12Data = certKeyPair[@"p12"];
            NSData* keyData = certKeyPair[@"privateKey"];
            
            [CertificateManager writeCryptoObject:@"client.crt" data:certData];
            [CertificateManager writeCryptoObject:@"client.p12" data:p12Data];
            [CertificateManager writeCryptoObject:@"client.key" data:keyData];
            
            Log(LOG_I, @"Certificate created");
        }
    });
}

+ (NSData *)getSignatureFromCert:(NSData *)cert {
    BIO* bio = BIO_new_mem_buf([cert bytes], (int)[cert length]);
    X509* x509 = PEM_read_bio_X509(bio, NULL, NULL, NULL);
    BIO_free(bio);
    
    if (!x509) {
        Log(LOG_E, @"Unable to parse certificate in memory!");
        return NULL;
    }
    
    const ASN1_BIT_STRING *asnSignature;
    X509_get0_signature(&asnSignature, NULL, x509);
    
    NSData* sig = [NSData dataWithBytes:asnSignature->data length:asnSignature->length];
    
    X509_free(x509);
    
    return sig;
}

+ (NSData*) pemToDer:(NSData*)pemCertBytes {
    X509* x509;
    
    BIO* bio = BIO_new_mem_buf([pemCertBytes bytes], (int)[pemCertBytes length]);
    x509 = PEM_read_bio_X509(bio, NULL, NULL, NULL);
    BIO_free(bio);
    
    bio = BIO_new(BIO_s_mem());
    i2d_X509_bio(bio, x509);
    X509_free(x509);

    BUF_MEM* mem;
    BIO_get_mem_ptr(bio, &mem);
    
    NSData* ret = [[NSData alloc] initWithBytes:mem->data length:mem->length];
    BIO_free(bio);
    
    return ret;
}

- (bool) verifySignature:(NSData *)data withSignature:(NSData*)signature andCert:(NSData*)cert {
    X509* x509;
    BIO* bio = BIO_new_mem_buf([cert bytes], (int)[cert length]);
    x509 = PEM_read_bio_X509(bio, NULL, NULL, NULL);
    
    BIO_free(bio);
    
    if (!x509) {
        Log(LOG_E, @"Unable to parse certificate in memory");
        return NULL;
    }
    
    EVP_PKEY* pubKey = X509_get_pubkey(x509);
    EVP_MD_CTX *mdctx = NULL;
    mdctx = EVP_MD_CTX_new();
    EVP_DigestVerifyInit(mdctx, NULL, EVP_sha256(), NULL, pubKey);
    EVP_DigestVerifyUpdate(mdctx, [data bytes], [data length]);
    int result = EVP_DigestVerifyFinal(mdctx, (unsigned char*)[signature bytes], [signature length]);
    
    X509_free(x509);
    EVP_PKEY_free(pubKey);
    EVP_MD_CTX_free(mdctx);
    
    return result > 0;
}

- (NSData *)signData:(NSData *)data withKey:(NSData *)key {
    BIO* bio = BIO_new_mem_buf([key bytes], (int)[key length]);
    
    EVP_PKEY* pkey;
    pkey = PEM_read_bio_PrivateKey(bio, NULL, NULL, NULL);
    
    BIO_free(bio);
    
    if (!pkey) {
        Log(LOG_E, @"Unable to parse private key in memory!");
        return NULL;
    }
    
    EVP_MD_CTX *mdctx = NULL;
    mdctx = EVP_MD_CTX_new();
    EVP_DigestSignInit(mdctx, NULL, EVP_sha256(), NULL, pkey);
    EVP_DigestSignUpdate(mdctx, [data bytes], [data length]);
    size_t slen;
    EVP_DigestSignFinal(mdctx, NULL, &slen);
    unsigned char* signature = malloc(slen);
    int result = EVP_DigestSignFinal(mdctx, signature, &slen);
    
    EVP_PKEY_free(pkey);
    EVP_MD_CTX_free(mdctx);
    
    if (result <= 0) {
        free(signature);
        return NULL;
    }
    
    NSData* signedData = [NSData dataWithBytes:signature length:slen];
    free(signature);
    
    return signedData;
}

+ (NSData*) readCryptoObject:(NSString*)item {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"SeleneCryptoStore",
        (__bridge id)kSecAttrAccount: item,
        (__bridge id)kSecReturnData: @YES
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result) {
        return (__bridge_transfer NSData *)result;
    }
    
    return nil;
}

+ (void) writeCryptoObject:(NSString*)item data:(NSData*)data {
    // First try to update existing item
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"SeleneCryptoStore",
        (__bridge id)kSecAttrAccount: item
    };
    
    NSDictionary *attributes = @{
        (__bridge id)kSecValueData: data
    };
    
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
    
    if (status == errSecItemNotFound) {
        // Item doesn't exist, add it
        NSDictionary *addQuery = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: @"SeleneCryptoStore",
            (__bridge id)kSecAttrAccount: item,
            (__bridge id)kSecValueData: data
        };
        SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    }
}

+ (bool) keyPairExists {
    bool keyFileExists = [CertificateManager readCryptoObject:@"client.key"] != nil;
    bool p12FileExists = [CertificateManager readCryptoObject:@"client.p12"] != nil;
    bool certFileExists = [CertificateManager readCryptoObject:@"client.crt"] != nil;
    
    return keyFileExists && p12FileExists && certFileExists;
}

@end

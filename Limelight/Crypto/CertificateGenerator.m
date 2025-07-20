//
//  CertificateGenerator.m
//  Selene
//
//  Created by Noé Barlet on 20/07/2025.
//  Copyright © 2025 Selene Game Streaming Project. All rights reserved.
//

@import OpenSSL.evp;
@import OpenSSL.pem;
@import OpenSSL.rsa;
@import OpenSSL.x509;
@import OpenSSL.pkcs12;

#import "CertificateGenerator.h"
#import "CertificateSecret.h"
#import "Logger.h"

static const NSInteger kDefaultKeyBits = 2048;
static const NSInteger kDefaultSerial = 0;
static const NSInteger kDefaultValidityYears = 20;
static NSString* const kDefaultName = @"GameStream";
static NSString* const kDefaultSubject = @"NVIDIA GameStream Client";

// Legacy C private struct still used internally by mkcert
typedef struct CertKeyPair {
    X509 *x509;
    EVP_PKEY *pkey;
    PKCS12 *p12;
} CertKeyPair;

@implementation CertificateGenerator

#pragma mark - New public methods

+ (NSDictionary*)generateCertKeyPair {
    CertKeyPair certKeyPair = [self generateInternalCertKeyPair];
    
    if (!certKeyPair.x509 || !certKeyPair.pkey || !certKeyPair.p12) {
        Log(LOG_E, @"Failed to generate certificate key pair");
        [self freeCertKeyPair:certKeyPair];
        return nil;
    }
    
    // Convert to NSData objects
    NSData* certData = [self getCertDataFromCertKeyPair:&certKeyPair];
    NSData* keyData = [self getKeyDataFromCertKeyPair:&certKeyPair];
    NSData* p12Data = [self getP12DataFromCertKeyPair:&certKeyPair];
    
    // Clean up OpenSSL structures
    [self freeCertKeyPair:certKeyPair];

    if (!certData || !keyData || !p12Data) {
        Log(LOG_E, @"Failed to convert certificate data");
        return nil;
    }
    
    return @{
        @"certificate": certData,
        @"privateKey": keyData,
        @"p12": p12Data
    };
}

#pragma mark - Private methods (from legacy C implementation)

+ (void)mkcert:(X509**)x509p  andKey:(EVP_PKEY**)pkeyp  withBits:(int)bits  serial:(int)serial  years:(int)years {
    X509* cert = X509_new();
    
    EVP_PKEY_CTX* ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, NULL);
    EVP_PKEY_keygen_init(ctx);
    EVP_PKEY_CTX_set_rsa_keygen_bits(ctx, bits);

    // pk must be initialized on input
    EVP_PKEY* pk = NULL;
    EVP_PKEY_keygen(ctx, &pk);

    EVP_PKEY_CTX_free(ctx);
    
    X509_set_version(cert, 2);
    ASN1_INTEGER_set(X509_get_serialNumber(cert), serial);
    ASN1_TIME* before = ASN1_STRING_dup(X509_get0_notBefore(cert));
    ASN1_TIME* after = ASN1_STRING_dup(X509_get0_notAfter(cert));

    X509_gmtime_adj(before, 0);
    X509_gmtime_adj(after, 60 * 60 * 24 * 365 * years);

    X509_set1_notBefore(cert, before);
    X509_set1_notAfter(cert, after);

    ASN1_STRING_free(before);
    ASN1_STRING_free(after);

    X509_set_pubkey(cert, pk);

    X509_NAME* name = X509_get_subject_name(cert);
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,
                               (const unsigned char*)[kDefaultSubject UTF8String],
                               -1, -1, 0);
    X509_set_issuer_name(cert, name);

    X509_sign(cert, pk, EVP_sha256());
    
    *x509p = cert;
    *pkeyp = pk;
}

+ (CertKeyPair) generateInternalCertKeyPair {
    X509 *x509 = NULL;
    EVP_PKEY *pkey = NULL;
    PKCS12 *p12 = NULL;
    
    [self mkcert:&x509 andKey:&pkey withBits:(int)kDefaultKeyBits serial:(int)kDefaultSerial years:(int)kDefaultValidityYears];
    
    const char* pass = [[CertificateSecret certificatePassword] UTF8String];
    const char* name = [kDefaultName UTF8String];
    p12 = PKCS12_create(pass,
                        name,
                        pkey,
                        x509,
                        NULL,
                        NID_pbe_WithSHA1And3_Key_TripleDES_CBC,
                        -1, // disable certificate encryption
                        2048,
                        -1, // disable the automatic MAC
                        0);
    // MAC it ourselves with SHA1 since iOS refuses to load anything else.
    PKCS12_set_mac(p12, pass, -1, NULL, 0, 1, EVP_sha1());
    
    if (p12 == NULL) {
        Log(LOG_E, @"Error generating a valid PKCS12 certificate.");
    }
    
    return (CertKeyPair){x509, pkey, p12};
}

+ (void)freeCertKeyPair:(CertKeyPair)certKeyPair {
    if (certKeyPair.x509) X509_free(certKeyPair.x509);
    if (certKeyPair.pkey) EVP_PKEY_free(certKeyPair.pkey);
    if (certKeyPair.p12) PKCS12_free(certKeyPair.p12);
}

+ (NSData*)getCertDataFromCertKeyPair:(CertKeyPair*)certKeyPair {
    BIO* bio = BIO_new(BIO_s_mem());
    PEM_write_bio_X509(bio, certKeyPair->x509);
    
    BUF_MEM* mem;
    BIO_get_mem_ptr(bio, &mem);
    NSData* data = [NSData dataWithBytes:mem->data length:mem->length];
    BIO_free(bio);
    return data;
}

+ (NSData*)getKeyDataFromCertKeyPair:(CertKeyPair*)certKeyPair {
    BIO* bio = BIO_new(BIO_s_mem());
    PEM_write_bio_PrivateKey_traditional(bio, certKeyPair->pkey, NULL, NULL, 0, NULL, NULL);
    
    BUF_MEM* mem;
    BIO_get_mem_ptr(bio, &mem);
    NSData* data = [NSData dataWithBytes:mem->data length:mem->length];
    BIO_free(bio);
    return data;
}

+ (NSData*)getP12DataFromCertKeyPair:(CertKeyPair*)certKeyPair {
    BIO* bio = BIO_new(BIO_s_mem());
    i2d_PKCS12_bio(bio, certKeyPair->p12);
    
    BUF_MEM* mem;
    BIO_get_mem_ptr(bio, &mem);
    NSData* data = [NSData dataWithBytes:mem->data length:mem->length];
    BIO_free(bio);
    return data;
}

@end

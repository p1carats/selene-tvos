
#include "mkcert.h"

#include <stdio.h>
#include <stdlib.h>

#include <openssl/evp.h>
#include <openssl/pem.h>
#include <OpenSSL/provider.h>
#include <OpenSSL/rsa.h>
#include <openssl/x509.h>
#include <OpenSSL/rand.h>

static const int NUM_BITS = 2048;
static const int SERIAL = 0;
static const int NUM_YEARS = 20;

void mkcert(X509 **x509p, EVP_PKEY **pkeyp, int bits, int serial, int years) {
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
                               (const unsigned char*)"NVIDIA GameStream Client",
                               -1, -1, 0);
    X509_set_issuer_name(cert, name);

    X509_sign(cert, pk, EVP_sha256());
    
    *x509p = cert;
    *pkeyp = pk;
}

struct CertKeyPair generateCertKeyPair(void) {
    X509 *x509 = NULL;
    EVP_PKEY *pkey = NULL;
    PKCS12 *p12 = NULL;
    
    mkcert(&x509, &pkey, NUM_BITS, SERIAL, NUM_YEARS);
    
    char* pass = "limelight";
    p12 = PKCS12_create(pass,
                        "GameStream",
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
        printf("Error generating a valid PKCS12 certificate.\n");
    }
    
    return (CertKeyPair){x509, pkey, p12};
}

void freeCertKeyPair(struct CertKeyPair certKeyPair) {
    X509_free(certKeyPair.x509);
    EVP_PKEY_free(certKeyPair.pkey);
    PKCS12_free(certKeyPair.p12);
}

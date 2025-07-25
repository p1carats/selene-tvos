//
//  PairManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import Dispatch;
@import UIKit;

#import "PairManager.h"
#import "CertificateManager.h"
#import "CryptoManager.h"
#import "Utils.h"
#import "HttpRequest.h"
#import "ServerInfoResponse.h"
#import "HttpManager.h"
#import "Logger.h"

@implementation PairManager {
    HttpManager* _httpManager;
    NSData* _clientCert;
    id<PairCallback> _callback;
}

- (instancetype) initWithManager:(HttpManager*)httpManager clientCert:(NSData*)clientCert callback:(id<PairCallback>)callback {
    self = [super init];
    _httpManager = httpManager;
    _clientCert = clientCert;
    _callback = callback;
    return self;
}

- (void) main {
    // We have to call startPairing before calling any other _callback functions
    NSString* PIN = [self generatePIN];
    [_callback startPairing:PIN];
    
    ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
    [_httpManager executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[_httpManager newServerInfoRequest:false]
                                               fallbackError:401 fallbackRequest:[_httpManager newHttpServerInfoRequest]]];
    if ([serverInfoResp isStatusOk]) {
        if (![[serverInfoResp getStringTag:@"PairStatus"] isEqual:@"1"]) {
            NSString* appversion = [serverInfoResp getStringTag:@"appversion"];
            if (appversion == nil) {
                [_callback pairFailed:@"Missing XML element"];
                return;
            }            
            [self initiatePairWithPin:PIN forServerMajorVersion:[[appversion substringToIndex:1] intValue] withState:[serverInfoResp getStringTag:@"state"]];
        } else {
            [_callback alreadyPaired];
        }
    }
    else {
        [_callback pairFailed:serverInfoResp.statusMessage];
    }
}

- (void) finishPairing:(UIBackgroundTaskIdentifier)bgId
           forResponse:(HttpResponse*)resp
     withFallbackError:(NSString*)errorMsg {
    [_httpManager executeRequestSynchronously:[HttpRequest requestWithUrlRequest:[_httpManager newUnpairRequest]]];
    
    if (bgId != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:bgId];
    }
    
    if (![resp isStatusOk]) {
        // Use the response error if the request failed
        errorMsg = resp.statusMessage;
    }
    
    [_callback pairFailed:errorMsg];
}

- (void) finishPairing:(UIBackgroundTaskIdentifier)bgId withSuccess:(NSData*)derCertBytes {
    if (bgId != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:bgId];
    }
    
    [_callback pairSuccessful:derCertBytes];
}

// All codepaths must call finishPairing exactly once before returning!
- (void) initiatePairWithPin:(NSString*)PIN forServerMajorVersion:(int)serverMajorVersion withState:(NSString*)state {
    Log(LOG_I, @"Pairing with generation %d server in state %@", serverMajorVersion, state);
    
    // Start a background task to help prevent the app from being killed
    // while pairing is in progress.
    UIBackgroundTaskIdentifier bgId = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"Pairing PC" expirationHandler:^{
        Log(LOG_W, @"Background pairing time has expired!");
    }];
    
    NSData* salt = [Utils randomBytes:16];
    NSData* saltedPIN = [self concatData:salt with:[PIN dataUsingEncoding:NSUTF8StringEncoding]];

    Log(LOG_I, @"PIN: %@, salt %@", PIN, salt);
    
    HttpResponse* pairResp = [[HttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[HttpRequest requestForResponse:pairResp withUrlRequest:[_httpManager newPairRequest:salt clientCert:_clientCert]]];
    if (![self verifyResponseStatus:pairResp]) {
        // GFE does not allow pairing while a server is busy, but Sunshine does. We give it a try and display the busy error if it fails.
        if ([state hasSuffix:@"_SERVER_BUSY"]) {
            [self finishPairing:bgId forResponse:pairResp withFallbackError:@"You cannot pair while a previous session is still running on the host PC. Quit any running games or reboot the host PC, then try pairing again."];
        }
        else {
            [self finishPairing:bgId forResponse:pairResp withFallbackError:@"Pairing was declined by the target."];
        }
        return;
    }
    
    NSString* plainCert = [pairResp getStringTag:@"plaincert"];
    if ([plainCert length] == 0) {
        [self finishPairing:bgId forResponse:pairResp withFallbackError:@"Another pairing attempt is already in progress."];
        return;
    }
    
    // Pin the cert for TLS usage on this host
    NSData* derCertBytes = [CertificateManager pemToDer:[Utils hexToBytes:plainCert]];
    [_httpManager setServerCert:derCertBytes];
    
    CryptoManager* cryptoMan = [[CryptoManager alloc] init];
    CertificateManager* certMan = [[CertificateManager alloc] init];
    NSData* aesKey;
    
    // Gen 7 servers use SHA256 to get the key
    int hashLength;
    if (serverMajorVersion >= 7) {
        aesKey = [cryptoMan createAESKeyFromSaltSHA256:saltedPIN];
        hashLength = 32;
    }
    else {
        aesKey = [cryptoMan createAESKeyFromSaltSHA1:saltedPIN];
        hashLength = 20;
    }
    
    NSData* randomChallenge = [Utils randomBytes:16];
    NSData* encryptedChallenge = [cryptoMan aesEncrypt:randomChallenge withKey:aesKey];
    
    HttpResponse* challengeResp = [[HttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[HttpRequest requestForResponse:challengeResp withUrlRequest:[_httpManager newChallengeRequest:encryptedChallenge]]];
    if (![self verifyResponseStatus:challengeResp]) {
        [self finishPairing:bgId forResponse:challengeResp withFallbackError:@"Pairing stage #2 failed"];
        return;
    }
    
    NSData* encServerChallengeResp = [Utils hexToBytes:[challengeResp getStringTag:@"challengeresponse"]];
    NSData* decServerChallengeResp = [cryptoMan aesDecrypt:encServerChallengeResp withKey:aesKey];
    
    NSData* serverResponse = [decServerChallengeResp subdataWithRange:NSMakeRange(0, hashLength)];
    NSData* serverChallenge = [decServerChallengeResp subdataWithRange:NSMakeRange(hashLength, 16)];
    
    NSData* clientSecret = [Utils randomBytes:16];
    NSData* challengeRespHashInput = [self concatData:[self concatData:serverChallenge with:[CertificateManager getSignatureFromCert:_clientCert]] with:clientSecret];
    NSData* challengeRespHash;
    if (serverMajorVersion >= 7) {
        challengeRespHash = [cryptoMan SHA256HashData: challengeRespHashInput];
    }
    else {
        challengeRespHash = [cryptoMan SHA1HashData: challengeRespHashInput];
    }
    
    assert([challengeRespHash length] <= 32);
    NSMutableData* paddedHash = [NSMutableData dataWithData:challengeRespHash];
    [paddedHash setLength:32];
    
    NSData* challengeRespEncrypted = [cryptoMan aesEncrypt:paddedHash withKey:aesKey];
    
    HttpResponse* secretResp = [[HttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[HttpRequest requestForResponse:secretResp withUrlRequest:[_httpManager newChallengeRespRequest:challengeRespEncrypted]]];
    if (![self verifyResponseStatus:secretResp]) {
        [self finishPairing:bgId forResponse:secretResp withFallbackError:@"Pairing stage #3 failed"];
        return;
    }
    
    NSData* serverSecretResp = [Utils hexToBytes:[secretResp getStringTag:@"pairingsecret"]];
    NSData* serverSecret = [serverSecretResp subdataWithRange:NSMakeRange(0, 16)];
    NSData* serverSignature = [serverSecretResp subdataWithRange:NSMakeRange(16, serverSecretResp.length - 16)];
    
    if (![certMan verifySignature:serverSecret withSignature:serverSignature andCert:[Utils hexToBytes:plainCert]]) {
        [self finishPairing:bgId forResponse:secretResp withFallbackError:@"Server certificate invalid"];
        return;
    }
    
    NSData* serverChallengeRespHashInput = [self concatData:[self concatData:randomChallenge with:[CertificateManager getSignatureFromCert:[Utils hexToBytes:plainCert]]] with:serverSecret];
    NSData* serverChallengeRespHash;
    if (serverMajorVersion >= 7) {
        serverChallengeRespHash = [cryptoMan SHA256HashData: serverChallengeRespHashInput];
    }
    else {
        serverChallengeRespHash = [cryptoMan SHA1HashData: serverChallengeRespHashInput];
    }
    if (![serverChallengeRespHash isEqual:serverResponse]) {
        [self finishPairing:bgId forResponse:secretResp withFallbackError:@"Incorrect PIN"];
        return;
    }
    
    NSData* clientPairingSecret = [self concatData:clientSecret with:[certMan signData:clientSecret withKey:[CertificateManager readKeyFromFile]]];
    HttpResponse* clientSecretResp = [[HttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[HttpRequest requestForResponse:clientSecretResp withUrlRequest:[_httpManager newClientSecretRespRequest:[Utils bytesToHex:clientPairingSecret]]]];
    if (![self verifyResponseStatus:clientSecretResp]) {
        [self finishPairing:bgId forResponse:clientSecretResp withFallbackError:@"Pairing stage #4 failed"];
        return;
    }
    
    HttpResponse* clientPairChallengeResp = [[HttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[HttpRequest requestForResponse:clientPairChallengeResp withUrlRequest:[_httpManager newPairChallenge]]];
    if (![self verifyResponseStatus:clientPairChallengeResp]) {
        [self finishPairing:bgId forResponse:clientPairChallengeResp withFallbackError:@"Pairing stage #5 failed"];
        return;
    }
    
    [self finishPairing:bgId withSuccess:derCertBytes];
}

// Caller calls finishPairing for us on failure
- (BOOL) verifyResponseStatus:(HttpResponse*)resp {
    if (![resp isStatusOk]) {
        return false;
    } else {
        NSInteger pairedStatus;
        
        if (![resp getIntTag:@"paired" value:&pairedStatus]) {
            return false;
        }
        
        return pairedStatus == 1;
    }
}

- (NSData*) concatData:(NSData*)data with:(NSData*)moreData {
    NSMutableData* concatData = [[NSMutableData alloc] initWithData:data];
    [concatData appendData:moreData];
    return concatData;
}

- (NSString*) generatePIN {
    NSString* PIN = [NSString stringWithFormat:@"%d%d%d%d",
                     arc4random_uniform(10), arc4random_uniform(10),
                     arc4random_uniform(10), arc4random_uniform(10)];
    return PIN;
}

@end

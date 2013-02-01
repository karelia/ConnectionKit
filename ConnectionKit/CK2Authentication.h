//
//  CK2Authentication.h
//  Connection
//
//  Created by Mike on 18/12/2012.
//
//

#import <Foundation/Foundation.h>


#pragma mark SSH Host Fingerprint

@interface NSURLProtectionSpace (CK2SSHHostFingerprint)

// These methods create a protection space with CK2AuthenticationMethodSSHHostFingerprint. (Other NSURLProtectionSpace APIs ignore the auth method and change it to NSURLAuthenticationDefault
+ (NSURLProtectionSpace *)ck2_SSHHostFingerprintProtectionSpaceWithHost:(NSString *)host match:(enum curl_khmatch)match;

- (int)ck2_SSHKnownHostsMatch;

extern NSString * const CK2AuthenticationMethodSSHHostFingerprint;

@end


@interface NSURLCredential (CK2SSHHostFingerprint)

// NSURLCredentialPersistencePermanent indicates new keys should be added to the known_hosts file
+ (NSURLCredential *)ck2_credentialForKnownHostWithPersistence:(NSURLCredentialPersistence)persistence;

@end


#pragma mark SSH Public Key Auth

@interface NSURLCredential (CK2SSHPublicKey)

// Authenticate using particular public & private key files
// On OS X, libssh2 generally uses the OpenSSL encryption library, so public key URL may be nil
+ (NSURLCredential *)ck2_credentialWithUser:(NSString *)user
                               publicKeyURL:(NSURL *)publicKey
                              privateKeyURL:(NSURL *)privateKey;

@end

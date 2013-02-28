//
//  CK2Authentication.h
//  Connection
//
//  Created by Mike on 18/12/2012.
//
//

#import <Foundation/Foundation.h>


#pragma mark SSH Host Fingerprint

typedef NS_ENUM(NSInteger, CK2KnownHostMatch) {
    CK2KnownHostMatchOK,
    CK2KnownHostMatchMismatch,
    CK2KnownHostMatchMissing,
};

@interface NSURLProtectionSpace (CK2SSHHostFingerprint)

// These methods create a protection space with CK2AuthenticationMethodSSHHostFingerprint. (Other NSURLProtectionSpace APIs ignore the auth method and change it to NSURLAuthenticationDefault
+ (NSURLProtectionSpace *)ck2_protectionSpaceWithHost:(NSString *)host knownHostMatch:(CK2KnownHostMatch)match;

- (CK2KnownHostMatch)ck2_knownHostMatch;

extern NSString * const CK2AuthenticationMethodHostFingerprint;

@end


@interface NSURLCredential (CK2SSHHostFingerprint)

// NSURLCredentialPersistencePermanent indicates new keys should be added to the known_hosts file
+ (NSURLCredential *)ck2_credentialForKnownHostWithPersistence:(NSURLCredentialPersistence)persistence;

@end


#pragma mark SSH Public Key Auth

@interface NSURLCredential (CK2SSHPublicKey)

// Authenticate using particular public & private key files
// On OS X, libssh2 generally uses the OpenSSL encryption library, so public key URL may be nil
// Some private keys are encrypted with a passphrase. If so, must pass in that password. Persistence specifies whether to store it in the keychain or not
+ (NSURLCredential *)ck2_credentialWithUser:(NSString *)user
                               publicKeyURL:(NSURL *)publicKey
                              privateKeyURL:(NSURL *)privateKey
                                   password:(NSString *)passphrase
                                persistence:(NSURLCredentialPersistence)persistence;

@end

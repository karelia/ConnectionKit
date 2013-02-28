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

/// \param [in] publicKey is the location of the public key file. If using OpenSSL (usually the case on OS X), pass nil here to have the public key automatically derived from the private key
/// \param [in] privateKey is the location of the private key file. Pass nil to use SSH-Agent instead (not available when sandboxed)
/// \param [in] passphrase is used to decrypt a passphrase-protected private key file.
/// \param [in] persistence specifies whether to store passphrase in the keychain or not.
/// \returns the credential.
+ (NSURLCredential *)ck2_credentialWithUser:(NSString *)user
                               publicKeyURL:(NSURL *)publicKey
                              privateKeyURL:(NSURL *)privateKey
                                   password:(NSString *)passphrase
                                persistence:(NSURLCredentialPersistence)persistence;

@end

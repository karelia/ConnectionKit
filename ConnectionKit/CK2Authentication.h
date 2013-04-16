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

/**
 The result of ConnectionKit checking the host's fingerprint against a local known_hosts file.
 
 Upon connecting to an SSH server, ConnectionKit compares its host fingerprint
 against the contents of the local known_hosts file. An authentication challenge
 is then issued to the delegate asking it how it would like to handle the result
 of that check. This method encapsulates that result:
 
 - `CK2KnownHostMatchOK` — the server and known_hosts match.
 - `CK2KnownHostMatchMissing` — the server appears not to have been connected to before, as no entry for it is present in known_hosts.
 - `CK2KnownHostMatchMismatch` — the server's fingerprint is different to that in the known_hosts file. It is likely the server has been compromised, modified, or replaced

 @return One of the CK2KnownHostMatch enum. 0 for auth methods other than CK2AuthenticationMethodHostFingerprint.
 */
- (CK2KnownHostMatch)ck2_knownHostMatch;

/**
 @const CK2AuthenticationMethodHostFingerprint
 @abstract The authentication method used by SSH connections for checking a host's fingerprint
 */
extern NSString * const CK2AuthenticationMethodHostFingerprint;

@end


@interface NSURLCredential (CK2SSHHostFingerprint)

/**
 Constructs a credential to encapsulate the outcome of evaluating an SSH server's
 host fingerprint.
 
 @param persistence indicates whether new keys should be added to the known_hosts file
 @return the credential
 */
+ (NSURLCredential *)ck2_credentialForKnownHostWithPersistence:(NSURLCredentialPersistence)persistence;

@end


#pragma mark SSH Public Key Auth

@interface NSURLCredential (CK2SSHPublicKey)

/**
 Constructs a credential to encapsulate the use of public key authentication
 
 @param user to log in as
 @param publicKey is the location of the public key file. If using OpenSSL (usually the case on OS X), pass nil here to have the public key automatically derived from the private key
 @param privateKey is the location of the private key file. Pass nil to use SSH-Agent instead (note: fails when sandboxed)
 @param passphrase is used to decrypt a passphrase-protected private key file
 @param persistence specifies whether to store passphrase in the keychain or not
 @return the credential
 */
+ (NSURLCredential *)ck2_credentialWithUser:(NSString *)user
                               publicKeyURL:(NSURL *)publicKey
                              privateKeyURL:(NSURL *)privateKey
                                   password:(NSString *)passphrase
                                persistence:(NSURLCredentialPersistence)persistence;

@end

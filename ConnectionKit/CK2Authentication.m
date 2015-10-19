//
//  CK2Authentication.m
//  Connection
//
//  Created by Mike on 18/12/2012.
//
//

#import "CK2Authentication.h"

#import <CURLHandle/CURLTransfer.h>


#pragma mark SSH Host Fingerprint

@interface CK2SSHHostFingerprintProtectionSpace : NSURLProtectionSpace
{
    CK2KnownHostMatch   _match;
    NSData              *_publicKey;
    CK2KnownHostType    _publicKeyType;
}
@end


@implementation CK2SSHHostFingerprintProtectionSpace

- initWithHost:(NSString *)host match:(enum curl_khmatch)match publicKey:(NSData *)key type:(CK2KnownHostType)keyType;
{
    if (self = [self initWithHost:host port:0 protocol:@"ssh" realm:nil authenticationMethod:CK2AuthenticationMethodHostFingerprint])
    {
        _match = match;
        _publicKey = [key copy];
        _publicKeyType = keyType;
    }
    return self;
}

- (void)dealloc;
{
    [_publicKey release];
    [super dealloc];
}

// Force it to return correct thing
- (NSString *)authenticationMethod; { return CK2AuthenticationMethodHostFingerprint; }
- (NSString *)protocol; { return @"ssh"; }

- (CK2KnownHostMatch)ck2_knownHostMatch; { return _match; }
- (NSData *)ck2_serverPublicKey; { return _publicKey; }
- (CK2KnownHostType)ck2_serverKnownHostType; { return _publicKeyType; }

// Make sure super doesn't create an actual copy
- (id)copyWithZone:(NSZone *)zone; { return [self retain]; }

@end


@implementation NSURLProtectionSpace (CK2SSHHostFingerprint)

- (CK2KnownHostMatch)ck2_knownHostMatch; { return 0; }
- (NSData *)ck2_serverPublicKey; { return nil; }
- (CK2KnownHostType)ck2_serverKnownHostType; { return CK2KnownHostTypeUnknown; }

NSString * const CK2AuthenticationMethodHostFingerprint = @"CK2AuthenticationMethodHostFingerprint";

+ (NSURLProtectionSpace *)ck2_protectionSpaceWithHost:(NSString *)host knownHostMatch:(CK2KnownHostMatch)match publicKey:(NSData *)key type:(CK2KnownHostType)keyType;
{
    return [[[CK2SSHHostFingerprintProtectionSpace alloc] initWithHost:host match:match publicKey:key type:keyType] autorelease];
}

@end


@implementation NSURLCredential (CK2SSHHostFingerprint)

+ (NSURLCredential *)ck2_credentialForKnownHostWithPersistence:(NSURLCredentialPersistence)persistence;
{
    return [self credentialWithUser:@"" password:@"" persistence:persistence];
}

@end


#pragma mark -


@interface NSURLCredential (SFTPWrapperSuppliedMethods)

+ (NSURLCredential *)ck2_credentialWithUser:(NSString *)user
                               publicKeyURL:(NSURL *)publicKey
                              privateKeyURL:(NSURL *)privateKey;

- (NSURLCredential *)ck2_credentialWithPassword:(NSString *)password persistence:(NSURLCredentialPersistence)persistence;

@end


@implementation NSURLCredential (CK2SSHPublicKey)

+ (NSURLCredential *)ck2_credentialWithUser:(NSString *)user
                               publicKeyURL:(NSURL *)publicKey
                              privateKeyURL:(NSURL *)privateKey
                                   password:(NSString *)password
                                persistence:(NSURLCredentialPersistence)persistence;
{
    NSURLCredential *result = [self ck2_credentialWithUser:user publicKeyURL:publicKey privateKeyURL:privateKey];
    result = [result ck2_credentialWithPassword:password persistence:persistence];
    return result;
}

@end

//
//  CK2Authentication.m
//  Connection
//
//  Created by Mike on 18/12/2012.
//
//

#import "CK2Authentication.h"

#import <CURLHandle/CURLHandle.h>


#pragma mark SSH Host Fingerprint

@interface CK2SSHHostFingerprintProtectionSpace : NSURLProtectionSpace
{
    CK2KnownHostMatch   _match;
}
@end


@implementation CK2SSHHostFingerprintProtectionSpace

- initWithHost:(NSString *)host match:(enum curl_khmatch)match;
{
    if (self = [self initWithHost:host port:0 protocol:@"ssh" realm:nil authenticationMethod:CK2AuthenticationMethodHostFingerprint])
    {
        _match = match;
    }
    return self;
}

// Force it to return correct thing
- (NSString *)authenticationMethod; { return CK2AuthenticationMethodHostFingerprint; }
- (NSString *)protocol; { return @"ssh"; }

- (enum curl_khmatch)ck2_knownHostMatch; { return _match; }

// Make sure super doesn't create an actual copy
- (id)copyWithZone:(NSZone *)zone; { return [self retain]; }

@end


@implementation NSURLProtectionSpace (CK2SSHHostFingerprint)

+ (NSURLProtectionSpace *)ck2_protectionSpaceWithHost:(NSString *)host knownHostMatch:(CK2KnownHostMatch)match;
{
    return [[[CK2SSHHostFingerprintProtectionSpace alloc] initWithHost:host match:match] autorelease];
}

- (CK2KnownHostMatch)ck2_knownHostMatch; { return 0; }

NSString * const CK2AuthenticationMethodHostFingerprint = @"CK2AuthenticationMethodHostFingerprint";

@end


@implementation NSURLCredential (CK2SSHHostFingerprint)

+ (NSURLCredential *)ck2_credentialForKnownHostWithPersistence:(NSURLCredentialPersistence)persistence;
{
    return [self credentialWithUser:nil password:nil persistence:persistence];
}

@end

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
    enum curl_khmatch   _match;
}
@end


@implementation CK2SSHHostFingerprintProtectionSpace

- initWithHost:(NSString *)host match:(enum curl_khmatch)match;
{
    if (self = [self initWithHost:host port:0 protocol:@"ssh" realm:nil authenticationMethod:CK2AuthenticationMethodSSHHostFingerprint])
    {
        _match = match;
    }
    return self;
}

// Force it to return correct thing
- (NSString *)authenticationMethod; { return CK2AuthenticationMethodSSHHostFingerprint; }
- (NSString *)protocol; { return @"ssh"; }

- (enum curl_khmatch)ck2_SSHKnownHostsMatch; { return _match; }

// Make sure super doesn't create an actual copy
- (id)copyWithZone:(NSZone *)zone; { return [self retain]; }

@end


@implementation NSURLProtectionSpace (CK2SSHHostFingerprint)

+ (NSURLProtectionSpace *)ck2_SSHHostFingerprintProtectionSpaceWithHost:(NSString *)host match:(enum curl_khmatch)match;
{
    return [[[CK2SSHHostFingerprintProtectionSpace alloc] initWithHost:host match:match] autorelease];
}

- (enum curl_khmatch)ck2_SSHKnownHostsMatch; { return 0; }

NSString * const CK2AuthenticationMethodSSHHostFingerprint = @"CK2AuthenticationMethodSSHHostFingerprint";

@end


@implementation NSURLCredential (CK2SSHHostFingerprint)

+ (NSURLCredential *)ck2_credentialForKnownHostWithPersistence:(NSURLCredentialPersistence)persistence;
{
    return [self credentialWithUser:nil password:nil persistence:persistence];
}

@end

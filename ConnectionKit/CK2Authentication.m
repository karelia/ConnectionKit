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

+ (NSURLProtectionSpace *)ck2_SSHHostFingerprintProtectionSpaceWithHost:(NSString *)host;
{
    return [[[CK2SSHHostFingerprintProtectionSpace alloc] initWithHost:host port:0 protocol:@"ssh" realm:nil authenticationMethod:CK2AuthenticationMethodSSHHostFingerprint] autorelease];
}

- (enum curl_khmatch)ck2_SSHKnownHostsMatch; { return 0; }

NSString * const CK2AuthenticationMethodSSHHostFingerprint = @"CK2AuthenticationMethodSSHHostFingerprint";

@end


@interface CK2SSHKnownHostsFile : NSURLCredential
{
  @private
    NSURL *_knownHostsFileURL;
}
@end

@implementation CK2SSHKnownHostsFile

- (id)initWithSSHKnownHostsFileURL:(NSURL *)knownHosts persistence:(NSURLCredentialPersistence)persistence;
{
    if (self = [self initWithUser:nil password:nil persistence:persistence])
    {
        _knownHostsFileURL = [knownHosts copy];
    }
    return self;
}

- (BOOL)ck2_isSSHHostFingerprintCredential { return YES; }
- (NSURL *)ck2_SSHKnownHostsFileURL; { return _knownHostsFileURL; }

// Make sure super doesn't create an actual copy
- (id)copyWithZone:(NSZone *)zone; { return [self retain]; }

- (void)encodeWithCoder:(NSCoder *)aCoder;
{
    [super encodeWithCoder:aCoder];
    [aCoder encodeObject:[self ck2_SSHKnownHostsFileURL] forKey:@"ck2_SSHKnownHostsFileURL"];
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    if (self = [super initWithCoder:aDecoder])
    {
        _knownHostsFileURL = [[aDecoder decodeObjectForKey:@"ck2_SSHKnownHostsFileURL"] retain];
    }
    return self;
}

@end


@implementation NSURLCredential (CK2SSHHostFingerprint)

+ (NSURLCredential *)ck2_credentialWithSSHKnownHostsFileURL:(NSURL *)knownHosts persistence:(NSURLCredentialPersistence)persistence;
{
    return [[[CK2SSHKnownHostsFile alloc] initWithSSHKnownHostsFileURL:knownHosts persistence:persistence] autorelease];
}

- (BOOL)ck2_isSSHHostFingerprintCredential; { return NO; }
- (NSURL *)ck2_SSHKnownHostsFileURL; { return nil; }

@end
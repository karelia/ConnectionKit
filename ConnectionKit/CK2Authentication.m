//
//  CK2Authentication.m
//  Connection
//
//  Created by Mike on 18/12/2012.
//
//

#import "CK2Authentication.h"


#pragma mark SSH Host Fingerprint

@interface CK2SSHHostFingerprintProtectionSpace : NSURLProtectionSpace
@end


@implementation CK2SSHHostFingerprintProtectionSpace

// Force it to return correct thing
- (NSString *)authenticationMethod; { return CK2AuthenticationMethodSSHHostFingerprint; }

// Make sure super doesn't create an actual copy
- (id)copyWithZone:(NSZone *)zone; { return [self retain]; }

@end


@implementation NSURLProtectionSpace (CK2SSHHostFingerprint)

+ (NSURLProtectionSpace *)ck2_SSHHostFingerprintProtectionSpaceWithHost:(NSString *)host;
{
    return [[[CK2SSHHostFingerprintProtectionSpace alloc] initWithHost:host port:0 protocol:nil realm:nil authenticationMethod:CK2AuthenticationMethodSSHHostFingerprint] autorelease];
}

NSString * const CK2AuthenticationMethodSSHHostFingerprint = @"CK2AuthenticationMethodSSHHostFingerprint";

@end


@interface CK2SSHKnownHostsFile : NSURLCredential
{
  @private
    NSURL *_knownHostsFileURL;
}
@end

@implementation CK2SSHKnownHostsFile

- (id)initWithSSHKnownHostsFileURL:(NSURL *)knownHosts;
{
    if (self = [self init])
    {
        _knownHostsFileURL = [knownHosts copy];
    }
    return self;
}

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

+ (NSURLCredential *)ck2_credentialWithSSHKnownHostsFileURL:(NSURL *)knownHosts;
{
    return [[[CK2SSHKnownHostsFile alloc] initWithSSHKnownHostsFileURL:knownHosts] autorelease];
}

- (NSURL *)ck2_SSHKnownHostsFileURL; { return nil; }

@end
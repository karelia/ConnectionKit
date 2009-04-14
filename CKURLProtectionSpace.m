//
//  CKURLProtectionSpace.m
//  Connection
//
//  Created by Mike on 18/12/2008.
//  Copyright 2008 Karelia Software. All rights reserved.
//

#import "CKURLProtectionSpace.h"


@implementation CKURLProtectionSpace

- (id)initWithHost:(NSString *)host port:(int)port protocol:(NSString *)protocol realm:(NSString *)realm authenticationMethod:(NSString *)authenticationMethod;
{
    if (self = [super initWithHost:host port:port protocol:protocol realm:realm authenticationMethod:authenticationMethod])
    {
        _protocol = [protocol copy];
    }
    
    return self;
}

- (void)dealloc
{
    [_protocol release];
    [super dealloc];
}

- (NSString *)protocol { return _protocol; }

/*	NSURLProtectionSpace is immutable. Returning self retained ensures the protocol can't change beneath us.
 */
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }

@end

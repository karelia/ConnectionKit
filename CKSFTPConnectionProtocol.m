//
//  CKSFTPConnectionProtocol.m
//  Connection
//
//  Created by Mike on 24/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKSFTPConnectionProtocol.h"

#import "CKConnectionRequest.h"


@implementation CKSFTPConnectionProtocol

@end


#pragma mark -
#pragma mark CKConnectionRequest


@implementation CKConnectionRequest (CKSFTPConnectionRequest)

- (NSString *)SFTPPublicKeyPath { return [self propertyForKey:@"CKSFTPPublicKeyPath"]; }

@end

@implementation CKMutableConnectionRequest (CKSFTPConnectionRequest)

- (void)setSFTPPublicKeyPath:(NSString *)path
{
    [self setProperty:path forKey:@"CKSFTPPublicKeyPath"];
}

@end
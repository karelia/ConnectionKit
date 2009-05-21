//
//  CKSFTPConnectionProtocol.m
//  Connection
//
//  Created by Mike on 24/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKSFTPConnectionProtocol.h"


@implementation CKSFTPConnectionProtocol

@end


#pragma mark -


@implementation NSURLRequest (CKSFTPURLRequest)

- (NSString *)SFTPPublicKeyPath;
{
    return [NSURLProtocol propertyForKey:@"CKSFTPPublicKeyPath" inRequest:self];
}

@end


@implementation NSMutableURLRequest (CKMutableSFTPURLRequest)

- (void)setSFTPPublicKeyPath:(NSString *)path;
{
    [NSURLProtocol setProperty:path forKey:@"CKSFTPPublicKeyPath" inRequest:self];
}

@end
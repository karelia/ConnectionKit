//
//  NSURLRequest.m
//  Connection
//
//  Created by Mike on 13/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKConnectionRequest.h"


@implementation NSURLRequest (ConnectionKitAdditions)

- (NSString *)FTPDataConnectionType
{
    return [NSURLProtocol propertyForKey:@"CKFTPDataConnectionType" inRequest:self];
}

- (NSString *)SFTPPublicKeyPath;
{
    return [NSURLProtocol propertyForKey:@"CKSFTPPublicKeyPath" inRequest:self];
}

@end


@implementation NSMutableURLRequest (ConnectionKitAdditions)

- (void)setFTPDataConnectionType:(NSString *)type
{
    [NSURLProtocol setProperty:type forKey:@"CKFTPDataConnectionType" inRequest:self];
}

- (void)setSFTPPublicKeyPath:(NSString *)path;
{
    [NSURLProtocol setProperty:path forKey:@"CKSFTPPublicKeyPath" inRequest:self];
}

@end
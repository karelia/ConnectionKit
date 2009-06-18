//
//  CKFTPConnectionProtocol.m
//  Connection
//
//  Created by Mike on 24/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFTPProtocol.h"


@implementation CKFTPProtocol

@end


#pragma mark -


@implementation NSURLRequest (CKFTPURLRequest)

- (NSString *)FTPDataConnectionType
{
    return [NSURLProtocol propertyForKey:@"CKFTPDataConnectionType" inRequest:self];
}

@end

@implementation NSMutableURLRequest (CKMutableFTPURLRequest)

- (void)setFTPDataConnectionType:(NSString *)type
{
    [NSURLProtocol setProperty:type forKey:@"CKFTPDataConnectionType" inRequest:self];
}

@end
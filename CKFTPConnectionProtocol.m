//
//  CKFTPConnectionProtocol.m
//  Connection
//
//  Created by Mike on 24/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFTPConnectionProtocol.h"

#import "CKConnectionRequest.h"


@implementation CKFTPConnectionProtocol

@end


#pragma mark -


@implementation CKConnectionRequest (CKFTPConnectionRequest)

- (NSString *)FTPDataConnectionType { return [self propertyForKey:@"CKFTPDataConnectionType"]; }

@end

@implementation CKMutableConnectionRequest (CKFTPConnectionRequest)

- (void)setFTPDataConnectionType:(NSString *)type
{
    [self setProperty:type forKey:@"CKFTPDataConnectionType"];
}

@end



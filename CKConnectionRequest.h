//
//  NSURLRequest.h
//  Connection
//
//  Created by Mike on 13/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//


//  The equivalent of NSURLRequest when creating a CKConnection.


#import <Foundation/Foundation.h>



@interface NSURLRequest (ConnectionKitAdditions)

// nil signifies the usual fallback chain of connection types
- (NSString *)FTPDataConnectionType;

- (NSString *)SFTPPublicKeyPath;

@end


@interface NSMutableURLRequest (ConnectionKitAdditions)
- (void)setFTPDataConnectionType:(NSString *)type;
- (void)setSFTPPublicKeyPath:(NSString *)path;
@end
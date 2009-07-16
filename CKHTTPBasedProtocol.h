//
//  CKHTTPBasedProtocol.h
//  ConnectionKit
//
//  Created by Mike on 14/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFSProtocol.h"


//  WebDAV and S3 share much in common; they both follow a REST-like HTTP protocol. This class is a nice convenience to provide the code they share


@interface CKHTTPBasedProtocol : CKFSProtocol
@end


@interface CKHTTPBasedProtocol (SubclassToImplement)
- (void)startOperationWithRequest:(NSURLRequest *)request;
@end
//
//  CK_FileTransferClient.h
//  ConnectionKit
//
//  Created by Mike on 15/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFileTransferConnection+Private.h"

#import "CKFSProtocol.h"


//  CK_FileTransferClient manages the threaded interaction with a CKFSProtocol
//  subclass. It generally just forwards the methods onto the host CKConnection object on the main
//  thread.
//
//  The classes are retained something like this:
//  
//  Connection -> Protocol -> Client
//             ------------->
@interface CK_FileTransferClient : NSObject <CKFSProtocolClient>
{
    CKFileTransferConnection    *_connectionThreadProxy;
    CKFSProtocol                *_protocol;
}

- (id)initWithConnection:(CKFileTransferConnection *)connection;

- (void)startWithRequest:(NSURLRequest *)request;
- (CKFSProtocol *)protocol;

@end


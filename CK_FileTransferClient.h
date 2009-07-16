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
@interface CK_FileTransferClient : NSObject <CKFileTransferProtocolClient>
{
    CKFileTransferConnection            *_connection;   // Weak ref
    CKFSProtocol    *_protocol;     // Weak ref
    
    id  _threadProxy;
}

- (id)initWithConnection:(CKFileTransferConnection *)connection;
- (CKFileTransferConnection *)connection;

- (CKFSProtocol *)connectionProtocol;
- (void)setConnectionProtocol:(CKFSProtocol *)protocol; // Single-use method

@end


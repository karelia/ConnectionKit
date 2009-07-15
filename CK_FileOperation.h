//
//  CKFileOperation.h
//  ConnectionKit
//
//  Created by Mike on 15/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CK_AsyncOperation.h"

#import "CKFileRequest.h"
#import "CKFileTransferConnection.h"


@interface CK_FileOperation : CK_AsyncOperation
{
    id <NSObject>               _identifier;
    CKFileRequest               *_request;
    CKFileTransferConnection    *_connection;   // weak ref
}

- (id)initWithIdentifier:(id <NSObject>)identifier
                 request:(CKFileRequest *)request
              connection:(CKFileTransferConnection *)connection;

@property(nonatomic, retain, readonly) id identifier;
@property(nonatomic, copy, readonly) CKFileRequest *request;
@property(nonatomic, assign, readonly) CKFileTransferConnection *connection;

@end

//
//  CKConnection+Private.h
//  Connection
//
//  Created by Mike on 24/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFileTransferConnection.h"
#import "CKFSProtocol.h"


typedef enum {
    CKConnectionStatusNotOpen,
    CKConnectionStatusOpening,
    CKConnectionStatusOpen,
    CKConnectionStatusClosed,
} CKConnectionStatus;


@interface CKFileTransferConnection (Private)
- (id)delegate;
- (CKConnectionStatus)status;

- (CK_FileOperation *)currentOperation;
- (void)CK_operationDidBegin:(CK_FileOperation *)operation;

@end


@interface CKFileTransferConnection (ProtocolClient) <CKFSProtocolClient>
@end




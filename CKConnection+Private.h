//
//  CKConnection+Private.h
//  Connection
//
//  Created by Mike on 24/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKConnection.h"
#import "CKConnectionProtocol.h"


typedef enum {
    CKConnectionStatusNotOpen,
    CKConnectionStatusOpening,
    CKConnectionStatusOpen,
    CKConnectionStatusClosed,
} CKConnectionStatus;


@class CKConnectionOperation;


@interface CKConnection (Private)
- (id)delegate;
- (CKConnectionStatus)status;

- (CKConnectionOperation *)currentOperation;
- (void)setCurrentOperation:(CKConnectionOperation *)operation;
@end


@interface CKConnection (ProtocolClient) <CKConnectionProtocolClient>
@end


@class RunLoopForwarder;


//  CKConnectionProtocolClient manages the threaded interaction with a CKConnectionProtocol
//  subclass. It generally just forwards the methods onto the host CKConnection object on the main
//  thread.
//
//  The classes are retained something like this:
//  
//  Connection -> Protocol -> Client
//             ------------->
@interface CKConnectionProtocolClient : NSObject <CKConnectionProtocolClient>
{
    CKConnection            *_connection;   // Weak ref
    CKConnectionProtocol    *_protocol;     // Weak ref
    
    RunLoopForwarder    *_threadProxy;
}

- (id)initWithConnection:(CKConnection *)connection;
- (CKConnection *)connection;

- (CKConnectionProtocol *)connectionProtocol;
- (void)setConnectionProtocol:(CKConnectionProtocol *)protocol; // Single-use method
                     
@end


typedef enum {
    CKConnectionOperationUpload,
    CKConnectionOperationDownload,
    CKConnectionOperationDirectoryListing,
    CKConnectionOperationCreateDirectory,
    CKConnectionOperationMove,
    CKConnectionOperationSetPermissions,
    CKConnectionOperationDelete,
} CKConnectionOperationType;


@interface CKConnectionOperation : NSObject
{
    id <NSObject>               _identifier;
    CKConnectionOperationType   _operationType;
    NSString                    *_path;
    
    CKConnectionOperation   *_mainOperation;
    NSData                  *_data;
    BOOL                    _recursive;
    NSString                *_destinationPath;
    unsigned long           _permissions;
}

- (id)initUploadOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)path data:(NSData *)data;
- (id)initDownloadOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)path;
- (id)initDirectoryListingOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)path;
- (id)initCreateDirectoryOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)path recursive:(BOOL)recursive mainOperation:(CKConnectionOperation *)mainOperation;
- (id)initMoveOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)fromPath destinationPath:(NSString *)toPath;
- (id)initSetPermissionsOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)path permissions:(unsigned long)permissions;
- (id)initDeleteOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)path;

- (id)identifier;
- (CKConnectionOperationType)operationType;
- (NSString *)path;

- (CKConnectionOperation *)mainOperation;
- (NSData *)data;
- (BOOL)isRecursive;
- (NSString *)destinationPath;
- (unsigned long)permissions;

@end

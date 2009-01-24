//
//  CKConnectionOperation.h
//  Marvel
//
//  Created by Mike on 19/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

//  CKConnectionOperation is a class internal to CKConnection designed to encapsulate an individual
//  operation.

#import <Foundation/Foundation.h>


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

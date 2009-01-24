//
//  CKConnectionOperation.m
//  Marvel
//
//  Created by Mike on 19/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKConnectionOperation.h"


@implementation CKConnectionOperation

- (id)initWithIdentifier:(id <NSObject>)identifier type:(CKConnectionOperationType)type path:(NSString *)path
{
    NSParameterAssert(path);
    NSParameterAssert([path isAbsolutePath]);
    
    [super init];
    
    _identifier = (identifier) ? [identifier retain] : [[NSObject alloc] init];
    _operationType = type;
    
    // We standardize paths so they never have a trailing slash
    if ([path hasSuffix:@"/"]) path = [path substringToIndex:([path length] - 1)];
    _path = [path copy];
    
    return self;
}

- (id)initUploadOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)path data:(NSData *)data
{
    [self initWithIdentifier:identifier type:CKConnectionOperationUpload path:path];
    _data = [data copy];
    return self;
}

- (id)initDownloadOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)path
{
    [self initWithIdentifier:identifier type:CKConnectionOperationDownload path:path];
    
    return self;
}

- (id)initDirectoryListingOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)path
{
    [self initWithIdentifier:identifier type:CKConnectionOperationDirectoryListing path:path];
    
    return self;
}

/*  This is one of the reasons CKConnectionOperation is private. It's rather ugly. When recursively
 *  creating directories, a series of CKConnectionOperation objects are created identifying the
 *  current operation and the main operation that they originate from.
 */
- (id)initCreateDirectoryOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)path recursive:(BOOL)recursive mainOperation:(CKConnectionOperation *)mainOperation;
{
    [self initWithIdentifier:identifier type:CKConnectionOperationCreateDirectory path:path];
    _recursive = recursive;
    _mainOperation = [mainOperation retain];
    return self;
}

- (id)initMoveOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)fromPath destinationPath:(NSString *)toPath
{
    [self initWithIdentifier:identifier type:CKConnectionOperationMove path:fromPath];
    _destinationPath = [toPath copy];
    return self;
}

- (id)initSetPermissionsOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)path permissions:(unsigned long)permissions
{
    [self initWithIdentifier:identifier type:CKConnectionOperationSetPermissions path:path];
    _permissions = permissions;
    return self;
}

- (id)initDeleteOperationWithIdentifier:(id <NSObject>)identifier path:(NSString *)path
{
    [self initWithIdentifier:identifier type:CKConnectionOperationDelete path:path];
    
    return self;
}

- (void)dealloc
{
    [_identifier release];
    [_path release];
    [_mainOperation release];
    [_data release];
    [_destinationPath release];
    
    [super dealloc];
}

- (id)identifier { return _identifier; }

- (CKConnectionOperationType)operationType { return _operationType; }

- (NSString *)path { return _path; }

- (CKConnectionOperation *)mainOperation { return _mainOperation; }

- (NSData *)data { return _data; }

- (BOOL)isRecursive { return _recursive; }

- (NSString *)destinationPath { return _destinationPath; }

- (unsigned long)permissions { return _permissions; }

@end

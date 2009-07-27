//
//  S3MacFUSE_Filesystem.h
//  ConnectionKit
//
//  Created by Mike on 22/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//
// Filesystem operations.
//


#import "CKFSProtocol.h"


// The core set of file system operations. This class will serve as the delegate
// for GMUserFileSystemFilesystem. For more details, see the section on 
// GMUserFileSystemOperations found in the documentation at:
// http://macfuse.googlecode.com/svn/trunk/core/sdk-objc/Documentation/index.html


@class CKFSItemInfo;


@interface CKAmazonS3FS : CKFSProtocol <CKReadWriteFS>
{
    NSURLCredential *_credential;
}

- (id)initWithCredential:(NSURLCredential *)credential;

@end



@interface CKAmazonS3FS (UnderlyingOperations)

- (CKFSItemInfo *)serviceInfo:(NSError **)outError;

- (BOOL)createBucket:(NSString *)bucket error:(NSError **)outError;
- (CKFSItemInfo *)infoForBucket:(NSString *)bucket
                         prefix:(NSString *)prefix
                      delimiter:(NSString *)delimiter
                          error:(NSError **)outError;

- (BOOL)createDirectoryObjectAtPath:(NSString *)path error:(NSError **)outError;
// getObject
- (CKFSItemInfo *)infoForObjectForKey:(NSString *)key
                          inBucket:(NSString *)bucket
                             error:(NSError **)outError;

- (BOOL)deleteItemAtPath:(NSString *)path error:(NSError **)outError;

@end


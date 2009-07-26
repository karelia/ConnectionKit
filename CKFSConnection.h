//
//  CKFSConnection.h
//  ConnectionKit
//
//  Created by Mike on 26/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

/*  Should be fairly obvious what most of these do, just like the NSFileManager equivalents. Two big differences:
 *      1)  Some methods use CKFSItemInfo. This is a more informative wrapper around both a file attribute dictionary & directory contents. Allows you to uitilise the connection more efficiently
 *      2)  Any use of a path refers to the path on the server (that's all we have access to). URLs are for local-ish operations.
 *
 *  Also take note that all operations are synchronous, so you probably won't want to call them on the main thread.
 */

#import <Cocoa/Cocoa.h>



@class CKFSItemInfo;

@interface CKFSConnection : NSObject
{
    id  _protocol;
}

// Temporary initializer till we have a better system in place
- (id)initWithCredential:(NSURLCredential *)credential;


#pragma mark Creating an Item

- (BOOL)createDirectoryAtPath:(NSString *)remotePath
  withIntermediateDirectories:(BOOL)createIntermediates
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)error;

- (BOOL)createFileAtPath:(NSString *)remotePath
                contents:(NSData *)contents
              attributes:(NSDictionary *)attributes
                   error:(NSError **)outError;


#pragma mark Getting and Comparing File Contents

// Perhaps we should have some of way to return any attributes of the file we find out (e.g. type)
- (NSData *)contentsOfFileAtPath:(NSString *)remotePath
                           error:(NSError **)outError;


#pragma mark Discovering Directory Contents

- (CKFSItemInfo *)contentsOfDirectoryAtPath:(NSString *)remotePath
                                      error:(NSError **)outError;

@end

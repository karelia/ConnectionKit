//
//  CKFSProtocol.h
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CKFileTransferConnection.h"
#import "CKFileRequest.h"


@class CKFSItemInfo;


@protocol CKReadOnlyFS <NSObject>

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path
                                userData:(id)userData
                                   error:(NSError **)error;

@optional

// These two are an optional, improved version of the required methods. Allow returning more information.
- (CKFSItemInfo *)loadContentsOfDirectoryAtPath:(NSString *)path error:(NSError **)outError;
- (CKFSItemInfo *)loadAttributesOfItemAtPath:(NSString *)path
                                    userData:(id)userData
                                       error:(NSError **)outError;

- (NSDictionary *)attributesOfFileSystemForPath:(NSString *)path
                                          error:(NSError **)error;

// MUST implement either -contentsAtPath: or the other three methods
- (NSData *)contentsAtPath:(NSString *)path;

- (BOOL)openFileAtPath:(NSString *)path 
                  mode:(int)mode
              userData:(id *)userData
                 error:(NSError **)error;
- (void)releaseFileAtPath:(NSString *)path userData:(id)userData;
- (int)readFileAtPath:(NSString *)path 
             userData:(id)userData
               buffer:(char *)buffer 
                 size:(size_t)size 
               offset:(off_t)offset
                error:(NSError **)error;

@end


@protocol CKReadWriteFS <CKReadOnlyFS>

- (BOOL)createDirectoryAtPath:(NSString *)path 
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)error;

- (BOOL)createFileAtPath:(NSString *)path 
              attributes:(NSDictionary *)attributes
                userData:(id *)userData
                   error:(NSError **)error;
- (BOOL)openFileAtPath:(NSString *)path 
                  mode:(int)mode
              userData:(id *)userData
                 error:(NSError **)error;

- (void)releaseFileAtPath:(NSString *)path userData:(id)userData;

- (int)writeFileAtPath:(NSString *)path 
              userData:(id)userData
                buffer:(const char *)buffer
                  size:(size_t)size 
                offset:(off_t)offset
                 error:(NSError **)error;

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;

@optional

- (BOOL)setAttributes:(NSDictionary *)attributes 
         ofItemAtPath:(NSString *)path
             userData:(id)userData
                error:(NSError **)error;

- (BOOL)exchangeDataOfItemAtPath:(NSString *)path1
                  withItemAtPath:(NSString *)path2
                           error:(NSError **)error;

- (BOOL)moveItemAtPath:(NSString *)source 
                toPath:(NSString *)destination
                 error:(NSError **)error;

- (BOOL)removeDirectoryAtPath:(NSString *)path error:(NSError **)error;

@end


#pragma mark -


/*  An abstract implementation of the CKReadOnlyFS. Provides protocol registration (+registerClass: etc.) and implements placeholders for all of the required methods.
 *  You will generally want to subclass it to provide a concrete implementation, one that also conforms to CKReadWriteFS.
 */

@protocol CKFSProtocolClient;
@interface CKFSProtocol : NSObject <CKReadOnlyFS>
{
  @private
    NSURLRequest            *_request;
    id <CKFSProtocolClient> _client;
}

#pragma mark Protocol registration

// FIXME: Make protocol class handling threadsafe
/*!
 @method registerClass:
 @param protocolClass The subclass of CKFSProtocol to register
 @result YES if the registration is successful, NO otherwise. The only failure condition is if
 protocolClass is not a subclass of CKFSProtocol.
 @discussion This method is only safe to use on the main thread.
 */
+ (BOOL)registerClass:(Class <CKReadOnlyFS>)protocolClass;

+ (Class)classForRequest:(NSURLRequest *)request;

// Return YES if the request is valid for your subclass to handle
+ (BOOL)canInitWithRequest:(NSURLRequest *)request;




#pragma mark Extensible request properties

+ (id)propertyForKey:(NSString *)key inRequest:(CKFileRequest *)request;
+ (void)setProperty:(id)value forKey:(NSString *)key inRequest:(CKMutableFileRequest *)request;
+ (void)removePropertyForKey:(NSString *)key inRequest:(CKMutableFileRequest *)request;

@end


#pragma mark -


@protocol CKFSProtocolClient <NSObject>

// Calling any of these methods at an inappropriate time will result in an exception

- (void)FSProtocol:(CKFSProtocol *)protocol didOpenConnectionWithCurrentDirectoryPath:(NSString *)path;
- (void)FSProtocol:(CKFSProtocol *)protocol didFailWithError:(NSError *)error;
- (void)FSProtocol:(CKFSProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

// Handling operation completion and cancellation
- (void)FSProtocol:(CKFSProtocol *)protocol operation:(NSOperation *)operation didFailWithError:(NSError *)error;
- (void)FSProtocol:(CKFSProtocol *)protocol operation:(NSOperation *)operation didDownloadData:(NSData *)data;
- (void)FSProtocol:(CKFSProtocol *)protocol operation:(NSOperation *)operation didUploadDataOfLength:(NSUInteger)length;

// Operation may be nil to signify the receipt of properties outside of performing an operation
- (void)FSProtocol:(CKFSProtocol *)protocol operation:(NSOperation *)operation didReceiveProperties:(CKFSItemInfo *)fileInfo ofItemAtPath:(NSString *)path;


- (void)FSProtocol:(CKFSProtocol *)protocol appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript;
- (void)FSProtocol:(CKFSProtocol *)protocol
                appendFormat:(NSString *)formatString
                toTranscript:(CKTranscriptType)transcript, ...;

@end


#pragma mark -


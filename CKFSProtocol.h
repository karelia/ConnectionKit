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
@protocol CKFSProtocolClient;


#pragma mark -


@protocol CKReadOnlyFS
@optional

// MUST implement either of these two
- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;
- (CKFSItemInfo *)loadContentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;

// MUST implement either of these two
- (NSDictionary *)attributesOfItemAtPath:(NSString *)path
                                userData:(id)userData
                                   error:(NSError **)error;
- (CKFSItemInfo *)loadAttributesOfItemAtPath:(NSString *)path
                                    userData:(id)userData
                                       error:(NSError **)error;

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


@interface CKFSProtocol : NSObject <CKReadOnlyFS>
{
  @private
    NSURLRequest             *_request;
    id <CKFSProtocolClient> _client;
}

#pragma mark Protocol registration

// FIXME: Make protcol class handling threadsafe
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


#pragma mark Protocol basics
// You shouldn't generally need to override these methods. They just create a protocol object and
// hang on to its properties
- (id)initWithRequest:(NSURLRequest *)request client:(id <CKFSProtocolClient>)client;
@property(nonatomic, readonly) NSURLRequest *request;
@property(nonatomic, readonly) id <CKFSProtocolClient> client;


#pragma mark Overall Connection
/*!
 @method startConnection
 @abstract Starts the connection.
 @discussion Protocols like SFTP and FTP use this to contact the host and log in. You should provide
 feedback to -client. Once a -protocol:didStartConnectionAtPath: message is sent, the connection
 system will start to provide you with operations to perform.
 */
- (void)startConnection;

/*!
 @method stopConnection
 @abstract Stops the connection.
 @discussion When this method is called, your subclass should immediately stop any in-progress
 operations and close the connection. This could be in response to a cancel request, so your code
 should be able to handle this call mid-operation.
 */
- (void)stopConnection;


#pragma mark File operations

/*  You are responsible for returning an NSOperation subclass that the client will set going when ready. If your protocol does not support the request, return nil; the client can then try a different variation of the request or fail the operation.
 *  NOTE: The returned object is implicitly retained, the sender is responsible for releasing it (with either release or autorelease).
 */
//- (NSOperation *)newOperationWithRequest:(CKFileRequest *)request client:(id <CKFSOperationProtocolClient>)client;

// You should override these methods to immediately perform the operation asynchronously. You should
// inform the client when the operation has finished, or if it failed. The connection system will
// not make another request until one of those messages has been received.
// Uploads and downloads use specialised client methods to keep the connection system informed of
// progress. Similarly, listing the contents of a directory is a special case where you should use
// -protocol:didFetchContentsOfDirectory: instead of -protocolCurrentOperationDidFinish:


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


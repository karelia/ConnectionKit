//
//  CKConnectionProtocol.h
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CKConnection.h"


@class CKConnectionRequest;
@protocol CKConnectionProtocolClient;


@interface CKConnectionProtocol : NSObject
{
@private
    CKConnectionRequest             *_request;
    id <CKConnectionProtocolClient> _client;
}

#pragma mark Protocol registration
/*!
 @method registerClass:
 @param protocolClass The subclass of CKConnectionProtocol to register
 @result YES if the registration is successful, NO otherwise. The only failure condition is if
 protocolClass is not a subclass of CKConnectionProtocol.
 @discussion This method is only safe to use on the main thread.
 */
+ (BOOL)registerClass:(Class)protocolClass;

+ (Class)classForRequest:(CKConnectionRequest *)request;

// Return YES if the request is valid for your subclass to handle
+ (BOOL)canInitWithConnectionRequest:(CKConnectionRequest *)request;


#pragma mark Protocol basics
// You shouldn't generally need to override these methods. They just create a protocol object and
// hang on to its properties
- (id)initWithRequest:(CKConnectionRequest *)request client:(id <CKConnectionProtocolClient>)client;
- (CKConnectionRequest *)request;
- (id <CKConnectionProtocolClient>)client;


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
// You should override these methods to immediately perform the operation asynchronously. You should
// inform the client when the operation has finished, or if it failed. The connection system will
// not make another request until one of those messages has been received.
// Uploads and downloads use specialised client methods to keep the connection system informed of
// progress. Similarly, listing the contents of a directory is a special case where you should use
// -protocol:didFetchContentsOfDirectory: instead of -protocolCurrentOperationDidFinish:

- (void)downloadContentsOfFileAtPath:(NSString *)remotePath;
- (void)uploadData:(NSData *)data toPath:(NSString *)path;

- (void)fetchContentsOfDirectoryAtPath:(NSString *)path;
- (void)createDirectoryAtPath:(NSString *)path;
- (void)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath;
- (void)setPermissions:(unsigned long)posixPermissions ofItemAtPath:(NSString *)path;
- (void)deleteItemAtPath:(NSString *)path;

/*!
 @method stopCurrentOperation
 @abstract Requests the protocol stop the current operation as soon as possible
 @discussion When this method is called, your subclass should immediately stop the current operation.
 Thus could be in response to a cancel request, so your code should be able to handle this call
 mid-operation.
 */
- (void)stopCurrentOperation;

@end


@protocol CKConnectionProtocolClient <NSObject>

// Calling any of these methods at an inappropriate time will result in an exception

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didOpenConnectionWithCurrentDirectoryPath:(NSString *)path;
- (void)connectionProtocol:(CKConnectionProtocol *)protocol didFailWithError:(NSError *)error;
- (void)connectionProtocol:(CKConnectionProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)connectionProtocol:(CKConnectionProtocol *)protocol didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

- (void)connectionProtocolDidFinishCurrentOperation:(CKConnectionProtocol *)protocol;
- (void)connectionProtocol:(CKConnectionProtocol *)protocol currentOperationDidFailWithError:(NSError *)error;
- (void)connectionProtocol:(CKConnectionProtocol *)protocol didDownloadData:(NSData *)data;
- (void)connectionProtocol:(CKConnectionProtocol *)protocol didUploadDataOfLength:(NSUInteger)length;
- (void)connectionProtocol:(CKConnectionProtocol *)protocol didLoadContentsOfDirectory:(NSArray *)contents;

- (void)connectionProtocol:(CKConnectionProtocol *)protocol appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript;
- (void)connectionProtocol:(CKConnectionProtocol *)protocol appendFormat:(NSString *)formatString toTranscript:(CKTranscriptType)transcript, ...;

@end


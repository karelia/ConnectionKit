//
//  CKFileTransferProtocol.h
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CKFileTransferConnection.h"


@class NSURLRequest;
@protocol CKFileTransferProtocolClient;


@interface CKFileTransferProtocol : NSObject
{
@private
    NSURLRequest             *_request;
    id <CKFileTransferProtocolClient> _client;
}

#pragma mark Protocol registration
/*!
 @method registerClass:
 @param protocolClass The subclass of CKFileTransferProtocol to register
 @result YES if the registration is successful, NO otherwise. The only failure condition is if
 protocolClass is not a subclass of CKFileTransferProtocol.
 @discussion This method is only safe to use on the main thread.
 */
+ (BOOL)registerClass:(Class)protocolClass;

+ (Class)classForRequest:(NSURLRequest *)request;

// Return YES if the request is valid for your subclass to handle
+ (BOOL)canInitWithRequest:(NSURLRequest *)request;


#pragma mark Protocol basics
// You shouldn't generally need to override these methods. They just create a protocol object and
// hang on to its properties
- (id)initWithRequest:(NSURLRequest *)request client:(id <CKFileTransferProtocolClient>)client;
@property(nonatomic, readonly) NSURLRequest *request;
@property(nonatomic, readonly) id <CKFileTransferProtocolClient> client;


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


@protocol CKFileTransferProtocolClient <NSObject>

// Calling any of these methods at an inappropriate time will result in an exception

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didOpenConnectionWithCurrentDirectoryPath:(NSString *)path;
- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didFailWithError:(NSError *)error;
- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

- (void)fileTransferProtocolDidFinishCurrentOperation:(CKFileTransferProtocol *)protocol;
- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol currentOperationDidFailWithError:(NSError *)error;
- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didDownloadData:(NSData *)data;
- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didUploadDataOfLength:(NSUInteger)length;
- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didLoadContentsOfDirectory:(NSArray *)contents;

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript;
- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol
                appendFormat:(NSString *)formatString
                toTranscript:(CKTranscriptType)transcript, ...;

@end


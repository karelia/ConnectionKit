//
//  CKConnection.h
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef enum {
	CKTranscriptSent,
	CKTranscriptReceived,
	CKTranscriptData,
} CKTranscriptType;


@class NSURLRequest, CKConnectionProtocol;
@protocol CKConnectionDelegate, CKConnectionProtocolClient;
    

@interface CKConnection : NSObject
{
@private
    NSURLRequest                *_request;
    id <CKConnectionDelegate>   _delegate;;
    NSString                    *_name;
    
    // Protocol
    CKConnectionProtocol            *_protocol;
    id <CKConnectionProtocolClient> _client;
    int                             _status;
    
    // Operation queue
    id              _currentOperation;
    NSMutableArray  *_queue;
    
}

+ (CKConnection *)connectionWithRequest:(NSURLRequest *)request delegate:(id <CKConnectionDelegate>)delegate;
- (id)initWithRequest:(NSURLRequest *)request delegate:(id <CKConnectionDelegate>)delegate;

- (NSURLRequest *)request;

- (void)cancel; // ceases delegate messages and forces the connection to stop as soon as possible

// Operations
- (id)uploadData:(NSData *)data toPath:(NSString *)path identifier:(id <NSObject>)identifier;
- (id)downloadContentsOfPath:(NSString *)path identifier:(id <NSObject>)identifier;
- (id)listContentsOfDirectoryAtPath:(NSString *)path identifier:(id <NSObject>)identifier;
- (id)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates identifier:(id <NSObject>)identifier;
- (id)moveItemAtPath:(NSString *)sourcePath toPath:(NSString *)destinationPath identifier:(id <NSObject>)identifier;
- (id)setPermissions:(unsigned long)posixPermissions ofItemAtPath:(NSString *)path identifier:(id <NSObject>)identifier;
- (id)deleteItemAtPath:(NSString *)path identifier:(id <NSObject>)identifier;

@end


@interface CKConnection (Queue)
//- (void)removeAllQueuedOperations;
@end


#pragma mark -


@protocol CKConnectionDelegate

- (void)connection:(CKConnection *)connection didFailWithError:(NSError *)error;

- (void)connection:(CKConnection *)connection operationDidBegin:(id)identifier;

/*!
 @method connection:operationDidFinish:
 @param connection The connection sending the message
 @param identifier The identifier of the operation that finished
 @discussion CKConnection will not start the next operation until this method returns to give you a chance to e.g. modify the queue in response.
 */
- (void)connection:(CKConnection *)connection operationDidFinish:(id)identifier;

/*!
 @method connection:operation:didFailWithError:
 @param connection The connection sending the message.
 @param identifier The identifier of the operation that failed.
 @param error The reason the operation failed.
 @discussion CKConnection will not start the next operation until this method returns to give you a chance to e.g. modify the queue in response.
 */
- (void)connection:(CKConnection *)connection operation:(id)identifier didFailWithError:(NSError *)error;

@optional
/*!
 @method connection:didOpenAtPath:
 @abstract Informs the delegate that the connection is open and ready to start processing operations.
 @param connection The connection sending the message.
 @param path The initial working directory if the protocol supports such a concept (e.g. FTP, SFTP). May well be nil for other protocols (e.g. WebDAV).
 @discussion At this point, the connection has verified the server is of a suitable type. Authentication will probably have been applied if needed, but this is not guaranteed (it is up to the server), and you may well be asked to authenticate again. Note that ConnectionKit only supports operations with absolute paths, so if your application needs to support the concept of a working directory, make sure to resolve paths relative to the one supplied here.
 */
- (void)connection:(CKConnection *)connection didOpenWithCurrentDirectoryPath:(NSString *)path;
- (void)connection:(CKConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)connection:(CKConnection *)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

- (void)connection:(CKConnection *)connection download:(id)identifier didReceiveData:(NSData *)data;
- (void)connection:(CKConnection *)connection upload:(id)identifier didSendDataOfLength:(NSUInteger)dataLength;
- (void)connection:(CKConnection *)connection directoryListing:(id)identifier didReceiveContents:(NSArray *)contents;

- (void)connection:(CKConnection *)connection appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript;

@end


#pragma mark -


@interface NSURLRequest (CKFTPURLRequest)
- (NSString *)FTPDataConnectionType;    // nil signifies the usual fallback chain of connection types
@end

@interface NSURLRequest (CKSFTPURLRequest)
- (NSString *)SFTPPublicKeyPath;
@end

@interface NSMutableURLRequest (CKMutableFTPURLRequest)
- (void)setFTPDataConnectionType:(NSString *)type;
@end

@interface NSMutableURLRequest (CKMutableSFTPURLRequest)
- (void)setSFTPPublicKeyPath:(NSString *)path;
@end

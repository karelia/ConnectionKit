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


@class NSURLRequest, CKFileTransferProtocol;
@protocol CKFileTransferConnectionDelegate, CKFileTransferProtocolClient;
    

@interface CKFileTransferConnection : NSObject
{
@private
    NSURLRequest                *_request;
    id <CKFileTransferConnectionDelegate>   _delegate;;
    NSString                    *_name;
    
    // Protocol
    CKFileTransferProtocol            *_protocol;
    id <CKFileTransferProtocolClient> _client;
    int                             _status;
    
    // Operation queue
    id              _currentOperation;
    NSMutableArray  *_queue;
    
}

+ (CKFileTransferConnection *)connectionWithRequest:(NSURLRequest *)request
                                           delegate:(id <CKFileTransferConnectionDelegate>)delegate;
- (id)initWithRequest:(NSURLRequest *)request delegate:(id <CKFileTransferConnectionDelegate>)delegate;

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


@interface CKFileTransferConnection (Queue)
//- (void)removeAllQueuedOperations;
@end


#pragma mark -


@protocol CKFileTransferConnectionDelegate

- (void)fileTransferConnection:(CKFileTransferConnection *)connection
              didFailWithError:(NSError *)error;

/*!
 @method connection:operationDidFinish:
 @param connection The connection sending the message
 @param identifier The identifier of the operation that finished
 @discussion CKConnection will not start the next operation until this method returns to give you a chance to e.g. modify the queue in response.
 */
- (void)fileTransferConnection:(CKFileTransferConnection *)connection
            operationDidFinish:(id)identifier;

/*!
 @method connection:operation:didFailWithError:
 @param connection The connection sending the message.
 @param identifier The identifier of the operation that failed.
 @param error The reason the operation failed.
 @discussion CKConnection will not start the next operation until this method returns to give you a chance to e.g. modify the queue in response.
 */
- (void)fileTransferConnection:(CKFileTransferConnection *)connection
                     operation:(id)identifier
              didFailWithError:(NSError *)error;

@optional

/*!
 @method connection:didOpenAtPath:
 @abstract Informs the delegate that the connection is open and ready to start processing operations.
 @param connection The connection sending the message.
 @param path The initial working directory if the protocol supports such a concept (e.g. FTP, SFTP). May well be nil for other protocols (e.g. WebDAV).
 @discussion At this point, the connection has verified the server is of a suitable type. Authentication will probably have been applied if needed, but this is not guaranteed (it is up to the server), and you may well be asked to authenticate again. Note that ConnectionKit only supports operations with absolute paths, so if your application needs to support the concept of a working directory, make sure to resolve paths relative to the one supplied here.
 */
- (void)fileTransferConnection:(CKFileTransferConnection *)connection
    didOpenWithCurrentDirectoryPath:(NSString *)path;

- (void)fileTransferConnection:(CKFileTransferConnection *)connection
    didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)fileTransferConnection:(CKFileTransferConnection *)connection
    didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

- (void)fileTransferConnection:(CKFileTransferConnection *)connection
             operationDidBegin:(id)identifier;

- (void)fileTransferConnection:(CKFileTransferConnection *)connection
                      download:(id)identifier
                didReceiveData:(NSData *)data;

- (void)fileTransferConnection:(CKFileTransferConnection *)connection
                        upload:(id)identifier
           didSendDataOfLength:(NSUInteger)dataLength;

- (void)fileTransferConnection:(CKFileTransferConnection *)connection
              directoryListing:(id)identifier
            didReceiveContents:(NSArray *)contents;

- (void)fileTransferConnection:(CKFileTransferConnection *)connection
                  appendString:(NSString *)string
                  toTranscript:(CKTranscriptType)transcript;

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

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

typedef enum {
    CKConnectionStatusNotOpen,
    CKConnectionStatusOpening,
    CKConnectionStatusOpen,
    CKConnectionStatusClosed,
} CKConnectionStatus;


@class CKConnectionRequest, CKConnectionProtocol;
    

@interface CKConnection : NSObject
{
@private
    CKConnectionRequest *_request;
    id                  _delegate;
    NSString            *_name;
    
    // Protocol
    CKConnectionProtocol    *_protocol;
    CKConnectionStatus       _status;
    
    // Operation queue
    id              _currentOperation;
    NSMutableArray  *_queue;
    
}

+ (CKConnection *)connectionWithConnectionRequest:(CKConnectionRequest *)request delegate:(id)delegate;
- (id)initWithConnectionRequest:(CKConnectionRequest *)request delegate:(id)delegate;

- (CKConnectionRequest *)connectionRequest;

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


@interface NSObject (CKConnectionDelegate)

- (void)connection:(CKConnection *)connection didOpenAtPath:(NSString *)path;
- (void)connection:(CKConnection *)connection didFailWithError:(NSError *)error;

- (void)connection:(CKConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)connection:(CKConnection *)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

- (void)connection:(CKConnection *)connection operationDidBegin:(id)identifier;

/*!
 @method connection:operationDidFinish:
 @param connection The connection sending the message
 @param identifier The identifier of the operation that finished
 @discussion CKConnection will not start the next operation until this method returns to give you
 a chance to e.g. modify the queue in response.
 */
- (void)connection:(CKConnection *)connection operationDidFinish:(id)identifier;

/*!
 @method connection:operation:didFailWithError:
 @param connection The connection sending the message.
 @param identifier The identifier of the operation that failed.
 @param error The reason the operation failed.
 @discussion CKConnection will not start the next operation until this method returns to give you
 a chance to e.g. modify the queue in response.
 */
- (void)connection:(CKConnection *)connection operation:(id)identifier didFailWithError:(NSError *)error;

- (void)connection:(CKConnection *)connection download:(id)identifier didReceiveData:(NSData *)data;
- (void)connection:(CKConnection *)connection upload:(id)identifier didSendDataOfLength:(NSUInteger)dataLength;
- (void)connection:(CKConnection *)connection directoryListing:(id)identifier didReceiveContents:(NSArray *)contents;

- (void)connection:(CKConnection *)connection appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript;

@end


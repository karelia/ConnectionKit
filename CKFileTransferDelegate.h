//
//  CKFileTransferDelegate.h
//  ConnectionKit
//
//  Created by Mike on 19/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFileTransferConnection.h"


@class CKFSItemInfo;


@protocol CKFileTransferDelegate

- (void)fileTransferConnection:(CKFileTransferConnection *)connection
              didFailWithError:(NSError *)error;

/*!
 @method fileTransferConnection:operationDidFinish:
 @param connection The connection sending the message
 @param identifier The identifier of the operation that finished
 @discussion CKConnection will not start the next operation until this method returns to give you a chance to e.g. modify the queue in response.
 */
- (void)fileTransferConnection:(CKFileTransferConnection *)connection
            operationDidFinish:(id)identifier;

/*!
 @method fileTransferConnection:operation:didFailWithError:
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
 @method fileTransferConnection:didOpenAtPath:
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
                      download:(id)identifier
                didReceiveData:(NSData *)data;

- (void)fileTransferConnection:(CKFileTransferConnection *)connection
                        upload:(id)identifier
           didSendDataOfLength:(NSUInteger)dataLength;

- (void)fileTransferConnection:(CKFileTransferConnection *)connection
                     operation:(id)identifier
          didReceiveProperties:(CKFSItemInfo *)fileInfo
                  ofItemAtPath:(NSString *)path;

- (void)fileTransferConnection:(CKFileTransferConnection *)connection
                  appendString:(NSString *)string
                  toTranscript:(CKTranscriptType)transcript;

@end

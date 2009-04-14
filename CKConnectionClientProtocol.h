//
//  CKConnectionClientProtocol.h
//  Connection
//
//  Created by Mike on 15/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//


//  CKAbstractConnection subclasses send delegate messages to their CKConnectionClient
//  object. The CKConnectionClient will then either deliver the message to the delegate
//  or provide the default implementation.


#import "CKConnectionProtocol.h"


@protocol CKConnectionClient

#pragma mark General

- (void)connectionDidConnectToHost:(NSString *)host error:(NSError *)error;
- (void)connectionDidDisconnectFromHost:(NSString *)host;

- (void)connectionDidReceiveError:(NSError *)error;

#pragma mark Authentication

/*!
 @method connectionDidReceiveAuthenticationChallenge:
 @discussion The client guarantees that it will answer the request on the same thread that
 called this method. The client may add a default credential to the challenge it issues to the
 connection delegate, if protocol did not provide one. If the client cancels the challenge, it will
 automatically call -[CKConnection forceDisconnect] before forwarding the message to the sender.
 */
- (void)connectionDidReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)connectionDidCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

- (NSString *)passphraseForHost:(NSString *)host username:(NSString *)username publicKeyPath:(NSString *)publicKeyPath;
- (NSString *)accountForUsername:(NSString *)username;

#pragma mark Transcript
- (void)appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript;
- (void)appendFormat:(NSString *)formatString toTranscript:(CKTranscriptType)transcript, ...;

#pragma mark Other

- (void)connectionDidCreateDirectory:(NSString *)dirPath error:(NSError *)error;
- (void)connectionDidDeleteDirectory:(NSString *)dirPath error:(NSError *)error;
- (void)connectionDidDeleteFile:(NSString *)path error:(NSError *)error;

- (void)connectionDidDiscoverFilesToDelete:(NSArray *)contents inAncestorDirectory:(NSString *)ancestorDirPath;
- (void)connectionDidDiscoverFilesToDelete:(NSArray *)contents inDirectory:(NSString *)dirPath;
- (void)connectionDidDeleteDirectory:(NSString *)dirPath inAncestorDirectory:(NSString *)ancestorDirPath error:(NSError *)error;
- (void)connectionDidDeleteFile:(NSString *)path inAncestorDirectory:(NSString *)ancestorDirPath error:(NSError *)error;

- (void)connectionDidChangeToDirectory:(NSString *)dirPath error:(NSError *)error;
- (void)connectionDidReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath error:(NSError *)error;
- (void)connectionDidRename:(NSString *)fromPath to:(NSString *)toPath error:(NSError *)error;
- (void)connectionDidSetPermissionsForFile:(NSString *)path error:(NSError *)error;

- (void)download:(NSString *)path didProgressToPercent:(NSNumber *)percent;
- (void)download:(NSString *)path didReceiveDataOfLength:(unsigned long long)length;
- (void)downloadDidBegin:(NSString *)remotePath;
- (void)downloadDidFinish:(NSString *)remotePath error:(NSError *)error;

- (void)upload:(NSString *)remotePath didProgressToPercent:(NSNumber *)percent;
- (void)upload:(NSString *)remotePath didSendDataOfLength:(unsigned long long)length;
- (void)uploadDidBegin:(NSString *)remotePath;
- (void)uploadDidFinish:(NSString *)remotePath error:(NSError *)error;

- (void)connectionDidCancelTransfer:(NSString *)remotePath;

- (void)connectionDidCheckExistenceOfPath:(NSString *)path pathExists:(BOOL)exists error:(NSError *)error;

@end


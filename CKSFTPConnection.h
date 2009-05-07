//
//  SFTPConnection.h
//  CocoaSFTP
//
//  Created by Brian Amerige on 11/4/07.
//  Copyright 2007 Extendmac, LLC.. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CKStreamBasedConnection.h"

extern NSString *SFTPErrorDomain;

@class CKSFTPTServer, CKInternalTransferRecord;

@interface CKSFTPConnection : CKAbstractQueueConnection
{
	int masterProxy;
	CKSFTPTServer *theSFTPTServer;
	
	NSString *rootDirectory;
	NSMutableString *currentDirectory;

	NSMutableArray *attemptedKeychainPublicKeyAuthentications;
	NSMutableArray *connectToQueue;
	NSTimer *_connectTimeoutTimer;

@private
    NSURLAuthenticationChallenge    *_lastAuthenticationChallenge;
    NSString                        *_currentPassword;
}

- (int)masterProxy;
- (void)setMasterProxy:(int)proxy;

@end


@interface CKConnectionRequest (CKSFTPConnection)
- (NSString *)SFTPPublicKeyPath;
- (NSUInteger)SFTPLoggingLevel;
@end

@interface CKMutableConnectionRequest (CKSFTPConnection)
- (void)setSFTPPublicKeyPath:(NSString *)path;
- (void)setSFTPLoggingLevel:(NSUInteger)level;
@end


@interface CKSFTPConnection (SFTPTServerCallback)
//
- (void)setServerObject:(id)serverObject;
- (void)_setupConnectTimeOut;
//
- (void)upload:(CKInternalTransferRecord *)uploadInfo didProgressTo:(double)progressPercentage withEstimatedCompletionIn:(NSString *)estimatedCompletion givenTransferRateOf:(NSString *)rate amountTransferred:(unsigned long long)amountTransferred;
- (void)download:(CKInternalTransferRecord *)downloadInfo didProgressTo:(double)progressPercentage withEstimatedCompletionIn:(NSString *)estimatedCompletion givenTransferRateOf:(NSString *)rate amountTransferred:(unsigned long long)amountTransferred;
//
- (void)finishedCommand;
- (void)receivedErrorInServerResponse:(NSString *)serverResponse;
//
- (void)getContinueQueryForUnknownHost:(NSDictionary *)hostInfo;
- (void)requestPasswordWithPrompt:(char *)header;
- (void)passwordErrorOccurred;
- (void)passphraseRequested:(NSString *)buffer;
- (void)didConnect;
- (void)didDisconnect;
- (void)didSetRootDirectory;
- (void)setCurrentDirectory:(NSString *)current;
- (void)didReceiveDirectoryContents:(NSArray*)items;

@end


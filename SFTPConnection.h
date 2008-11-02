//
//  SFTPConnection.h
//  CocoaSFTP
//
//  Created by Brian Amerige on 11/4/07.
//  Copyright 2007 Extendmac, LLC.. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SFTPTServer.h"
#import "StreamBasedConnection.h"

extern NSString *SFTPErrorDomain;

@class CKInternalTransferRecord;

@interface SFTPConnection : StreamBasedConnection
{
	int masterProxy;
	SFTPTServer *theSFTPTServer;
	NSConnection *connectionToTServer;
	
	BOOL isConnecting;
	NSString *rootDirectory;
	NSMutableString *currentDirectory;

	NSMutableArray *attemptedKeychainPublicKeyAuthentications;
	NSMutableArray *connectToQueue;
	NSTimer *_connectTimeoutTimer;

}

- (int)masterProxy;
- (void)setMasterProxy:(int)proxy;

@end

@interface SFTPConnection (SFTPTServerCallback)
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
- (void)addStringToTranscript:(NSString *)stringToAdd;
@end
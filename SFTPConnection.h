//
//  SFTPConnection.h
//  CocoaSFTP
//
//  Created by Brian Amerige on 11/4/07.
//  Copyright 2007 Extendmac, LLC.. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "StreamBasedConnection.h"
#import "CKTransferRecord.h"
#import "CKInternalTransferRecord.h"
#import "FTPConnection.h"
#import "EMKeychainProxy.h"
#import "SFTPTServer.h"

@interface SFTPConnection : StreamBasedConnection 
{
	int master;
	BOOL isConnected, isUploading, isDownloading;
	NSMutableString *currentDirectory;
	NSTextStorage *myTextStorage;
	
	NSMutableArray *uploadQueue, *downloadQueue, *deleteFileQueue, *deleteDirectoryQueue, *renameQueue, *permissionChangeQueue, *attemptedKeychainPublicKeyAuthentications;
	NSMutableArray *connectToQueue;
	
	NSMutableArray *commandQueue;
	
	SFTPTServer *theSFTPTServer;
	
	NSTimer *animateTransferProgressTimer;
}

- (void)establishDistributedObjectsConnection;
- (void)queueSFTPCommand:(void *)cmd;
- (void)queueSFTPCommandWithString:(NSString *)cmdString;
- (void)writeSFTPCommand:(void *)cmd;
- (void)writeSFTPCommandWithString:(NSString *)commandString;
- (CKTransferRecord *)uploadFile:(NSString *)localPath
						  orData:(NSData *)data
						  offset:(unsigned long long)offset
					  remotePath:(NSString *)remotePath
			checkRemoteExistence:(BOOL)checkRemoteExistenceFlag
						delegate:(id)delegate;
- (BOOL)isBusy;
- (BOOL)isUploading;
- (BOOL)isDownloading;
- (int)numberOfTransfers;
- (void)directoryContents;
- (void)finishedCommand;
- (void)checkFinishedCommandStringForNotifications:(NSString *)finishedCommand;
- (void)setServerObject:(id)serverObject;
- (void)setMasterProxy:(int)masterProxy;
- (void)finishedCommand;
- (void)didConnect;
- (void)didDisconnect;
- (void)didReceiveDirectoryContents:(NSArray*)items;
- (void)didChangeToDirectory:(NSString *)path;
- (void)upload:(CKInternalTransferRecord *)uploadInfo didProgressTo:(double)progressPercentage withEstimatedCompletionIn:(NSString *)estimatedCompletion givenTransferRateOf:(NSString *)rate amountTransferred:(unsigned long long)amountTransferred;
- (void)uploadDidBegin:(CKInternalTransferRecord *)uploadInfo;
- (void)uploadDidFinish:(CKInternalTransferRecord *)uploadInfo;
- (CKInternalTransferRecord *)currentUploadInfo;
- (void)download:(CKInternalTransferRecord *)downloadInfo didProgressTo:(double)progressPercentage withEstimatedCompletionIn:(NSString *)estimatedCompletion givenTransferRateOf:(NSString *)rate amountTransferred:(unsigned long long)amountTransferred;
- (CKInternalTransferRecord *)currentDownloadInfo;
- (void)downloadDidBegin:(CKInternalTransferRecord *)downloadInfo;
- (void)downloadDidFinish:(CKInternalTransferRecord *)downloadInfo;
- (NSString *)currentFileDeletionPath;
- (NSString *)currentDirectoryDeletionPath;
- (void)didDeleteFile:(NSString *)remotePath;
- (void)didDeleteDirectory:(NSString *)remotePath;
- (NSDictionary *)currentRenameInfo;
- (void)didRename:(NSDictionary *)renameInfo;
- (NSDictionary *)currentPermissionChangeInfo;
- (void)didSetPermissionsForFile:(NSDictionary *)permissionInfo;
- (void)passphraseRequested:(NSString *)buffer;
- (void)connectionError:(NSError *)theError;
- (void)passwordErrorOccurred;
- (void)requestPasswordWithPrompt:(char *)header;
- (void)connectionError:(NSError *)error;
- (void)getContinueQueryForUnknownHost:(NSDictionary *)hostInfo;
- (void)setCurrentRemotePath:(NSString *)remotePath;
- (void)addStringToTranscript:(NSString *)stringToAdd;
@end

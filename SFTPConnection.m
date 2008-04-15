//
//  SFTPConnection.m
//  CocoaSFTP
//
//  Created by Brian Amerige on 11/4/07.
//  Copyright 2007 Extendmac, LLC.. All rights reserved.
//

#import "SFTPConnection.h"
#import "RunLoopForwarder.h"
#import "NSFileManager+Connection.h"
#import "AbstractConnectionProtocol.h"
#import "NSString+Connection.h"
#import "SSHPassphrase.h"

#include "sshversion.h"
#include "fdwrite.h"

@implementation SFTPConnection

static char *lsform;
+ (void)load    // registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"22", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"sftp://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	NSDictionary *url2 = [NSDictionary dictionaryWithObjectsAndKeys:@"ssh://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[SFTPConnection class] forTypes:[NSArray arrayWithObjects:port, url, url2, nil]];
	[pool release];
}

+ (NSString *)name
{
	return @"SFTP";
}
+ (NSString *)urlScheme
{
	return @"sftp";
}
+ (id)connectionToHost:(NSString *)host port:(NSString *)port username:(NSString *)username password:(NSString *)password error:(NSError **)error
{
	return [[[SFTPConnection alloc] initWithHost:host
											port:port
										username:username
										password:password
										   error:error] autorelease];
}
- (id)initWithHost:(NSString *)host port:(NSString *)port username:(NSString *)username password:(NSString *)password error:(NSError **)error
{
	if ((self = [super initWithHost:host port:port username:username password:password error:error]))
	{
		uploadQueue = [[NSMutableArray array] retain];
		downloadQueue = [[NSMutableArray array] retain];
		connectToQueue = [[NSMutableArray array] retain];
		currentDirectory = [[NSMutableString string] retain];
		deleteFileQueue = [[NSMutableArray array] retain];
		deleteDirectoryQueue = [[NSMutableArray array] retain];
		renameQueue = [[NSMutableArray array] retain];
		permissionChangeQueue = [[NSMutableArray array] retain];
		commandQueue = [[NSMutableArray arrayWithObject:@"CONNECT"] retain];
		attemptedKeychainPublicKeyAuthentications = [[NSMutableArray array] retain];
		
		[self establishDistributedObjectsConnection];
	}
	return self;
}

- (void)dealloc
{
	[uploadQueue release];
	[downloadQueue release];
	[connectToQueue release];
	[deleteFileQueue release];
	[deleteDirectoryQueue release];
	[renameQueue release];
	[permissionChangeQueue release];
	[currentDirectory release];
	[commandQueue release];
	[attemptedKeychainPublicKeyAuthentications release];
	
	[super dealloc];
}

#pragma mark Getters
- (BOOL)isConnected
{
	return isConnected;
}

- (BOOL)isUploading
{
	return isUploading;
}

- (BOOL)isDownloading
{
	return isDownloading;
}

- (BOOL)isBusy
{
	return [self isUploading] || [self isDownloading];
}

- (int)numberOfTransfers
{
	return [self numberOfUploads] + [self numberOfDownloads];
}

- (int)numberOfUploads
{
	return [uploadQueue count];
}

- (int)numberOfDownloads
{
	return [downloadQueue count];
}

#pragma mark SFTP Actions
- (void)connect
{
	if (![self username])
	{
		//Can't do anything here, throw an error.
		return;
	}
	NSMutableArray *parameters = [NSMutableArray array];
	BOOL enableCompression = NO; //We do support this on the backend, but we have no UI for it yet.
	if (enableCompression)
	{
		[parameters addObject:@"-C"];
	}	
	if (![[self port] isEqualToString:@""])
	{
		[parameters addObject:[NSString stringWithFormat:@"-o Port=%i", [[self port] intValue]]];
	}
	if ([self password] && [[self password] length] > 0)
	{
		[parameters addObject:@"-o PubkeyAuthentication=no"];
	}
	else
	{
		[parameters addObject:[NSString stringWithFormat:@"-o IdentityFile=~/.ssh/%@", [self username]]];
		[parameters addObject:@"-o IdentityFile=~/.ssh/id_rsa"];
		[parameters addObject:@"-o IdentityFile=~/.ssh/id_dsa"];
	}
	[parameters addObject:[NSString stringWithFormat:@"%@@%@", [self username], [self host]]];
	
	switch (sshversion())
	{
		case SFTP_VERSION_UNSUPPORTED:
			//Not Supported.
			return;
		case SFTP_LS_LONG_FORM:
			lsform = "ls -l";
			break;
			
		case SFTP_LS_EXTENDED_LONG_FORM:
			lsform = "ls -la";
			break;
			
		case SFTP_LS_SHORT_FORM:
		default:
			lsform = "ls";
			break;
    }
	if (!theSFTPTServer)
	{
		[connectToQueue addObject:parameters];
		return;
	}
	[theSFTPTServer connectToServerWithParams:parameters fromWrapperConnection:self];
}

- (void)disconnect
{
	[self queueSFTPCommandWithString:@"quit"];
}

- (void)forceDisconnect
{
	[self writeSFTPCommandWithString:@"quit"];
}
- (void)threadedForceDisconnect
{
	[theSFTPTServer forceDisconnect];
}

#pragma mark -
- (NSString *)currentDirectory
{
	return [NSString stringWithString:currentDirectory];
}

- (void)changeToDirectory:(NSString *)newDir
{
	NSString *changeDirString = [NSString stringWithFormat:@"cd \"%@\"", newDir];
	[self queueSFTPCommandWithString:changeDirString];
	[self queueSFTPCommandWithString:@"pwd"];
}

- (void)contentsOfDirectory:(NSString *)newDir
{
	[self changeToDirectory:newDir];
	[self directoryContents];
}

- (void)directoryContents
{
	if ([currentDirectory length] == 0)
	{
		[self changeToDirectory:@"./"];
	}
	[self queueSFTPCommand:lsform];
}

#pragma mark -
- (void)createDirectory:(NSString *)newDirectoryPath
{
	[self queueSFTPCommandWithString:[NSString stringWithFormat:@"mkdir \"%@\"", newDirectoryPath]];
}

- (void)createDirectory:(NSString *)newDirectoryPath permissions:(unsigned long)permissions
{
	[self createDirectory:newDirectoryPath];
	[self setPermissions:permissions forFile:newDirectoryPath];
}

#pragma mark -
- (void)uploadFile:(NSString *)localPath
{
	[self uploadFile:localPath orData:nil offset:0 remotePath:nil checkRemoteExistence:NO delegate:nil];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	[self uploadFile:localPath toFile:remotePath checkRemoteExistence:NO delegate:nil];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	[self uploadFile:localPath toFile:remotePath checkRemoteExistence:flag delegate:nil];
}
- (CKTransferRecord *)uploadFile:(NSString *)localPath  toFile:(NSString *)remotePath  checkRemoteExistence:(BOOL)flag  delegate:(id)delegate
{
	NSAssert(localPath && ![localPath isEqualToString:@""], @"localPath is nil!");
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
	return [self uploadFile:localPath
					 orData:nil
					 offset:0
				 remotePath:remotePath
	   checkRemoteExistence:flag
				   delegate:delegate];
}
- (CKTransferRecord *)uploadFile:(NSString *)localPath orData:(NSData *)data offset:(unsigned long long)offset remotePath:(NSString *)remotePath checkRemoteExistence:(BOOL)checkRemoteExistenceFlag delegate:(id)delegate
{
	if (!localPath)
	{
		localPath = [remotePath lastPathComponent];
	}
	if (!remotePath)
	{
		remotePath = [[self currentDirectory] stringByAppendingPathComponent:[localPath lastPathComponent]];
	}
	
	unsigned long long uploadSize = 0;
	if (data)
	{
		uploadSize = [data length];
		
		//Super Über Cheap Way Until I figure out how to do this in a pretty way.
		NSString *temporaryParentPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ConnectionKitTemporary"];
		[[NSFileManager defaultManager] recursivelyCreateDirectory:temporaryParentPath attributes:nil];
		localPath = [temporaryParentPath stringByAppendingPathComponent:[remotePath lastPathComponent]];
		[data writeToFile:localPath atomically:YES];
	}
	else
	{
		NSDictionary *attributes = [[NSFileManager defaultManager] fileAttributesAtPath:localPath traverseLink:YES];
		uploadSize = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
	}
	
	CKTransferRecord *record = [CKTransferRecord recordWithName:remotePath size:uploadSize];
	[record setUpload:YES];
	[record setObject:localPath forKey:QueueUploadLocalFileKey];
	[record setObject:remotePath forKey:QueueUploadRemoteFileKey];
	
	id internalTransferRecordDelegate = (delegate) ? delegate : record;
		
	CKInternalTransferRecord *internalRecord = [CKInternalTransferRecord recordWithLocal:localPath data:data offset:offset remote:remotePath delegate:internalTransferRecordDelegate userInfo:record];
	
	[uploadQueue addObject:internalRecord];
	[self queueSFTPCommandWithString:[NSString stringWithFormat:@"put \"%@\" \"%@\"", localPath, remotePath]];
	
	return record;
}
- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	[self uploadFile:nil orData:data offset:0 remotePath:remotePath checkRemoteExistence:NO delegate:nil];
}

- (CKTransferRecord *)uploadFromData:(NSData *)data toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag delegate:(id)delegate
{
	NSAssert(data, @"no data");	// data should not be nil, but it shoud be OK to have zero length!
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
	return [self uploadFile:nil
					 orData:data
					 offset:0
				 remotePath:remotePath
	   checkRemoteExistence:flag
				   delegate:delegate];
}

#pragma mark -
- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	[self downloadFile:remotePath toDirectory:dirPath overwrite:flag delegate:nil];
}

- (CKTransferRecord *)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag delegate:(id)delegate
{
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"no remotePath");
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
	NSString *remoteFileName = [remotePath lastPathComponent];
	NSString *localPath = [dirPath stringByAppendingPathComponent:remoteFileName];
	
	if (!flag)
	{
		if ([[NSFileManager defaultManager] fileExistsAtPath:localPath])
		{
			if (_flags.error) {
				NSError *error = [NSError errorWithDomain:FTPErrorDomain
													 code:FTPDownloadFileExists
												 userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInConnectionKitBundle(@"Local File already exists", @"FTP download error")
																					  forKey:NSLocalizedDescriptionKey]];
				[_forwarder connection:self didReceiveError:error];
			}
			return nil;
		}
	}
	
	CKTransferRecord *record = [CKTransferRecord recordWithName:remotePath size:0];
	[record setProperty:remotePath forKey:QueueDownloadRemoteFileKey];
	[record setProperty:localPath forKey:QueueDownloadDestinationFileKey];
	[record setProperty:[NSNumber numberWithInt:0] forKey:QueueDownloadTransferPercentReceived];
	
	CKInternalTransferRecord *internalTransferRecord = [CKInternalTransferRecord recordWithLocal:localPath data:nil offset:0 remote:remotePath delegate:delegate ? delegate : record userInfo:record];

	[downloadQueue addObject:internalTransferRecord];
	[self queueSFTPCommandWithString:[NSString stringWithFormat:@"get \"%@\" \"%@\"", remotePath, localPath]];
	
	return record;
}

#pragma mark -
- (void)threadedCancelTransfer
{
	[self forceDisconnect];
	[self connect];
//	[self writeSFTPCommandWithString:@"Interrupt"];
}

#pragma mark -
- (void)deleteFile:(NSString *)remotePath
{
	[deleteFileQueue addObject:remotePath];
	[self queueSFTPCommandWithString:[NSString stringWithFormat:@"rm \"%@\"", remotePath]];
}

- (void)deleteDirectory:(NSString *)remotePath
{
	[deleteDirectoryQueue addObject:remotePath];
	[self queueSFTPCommandWithString:[NSString stringWithFormat:@"rmdir \"%@\"", remotePath]];
}

#pragma mark -
- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSDictionary *renameDictionary = [NSDictionary dictionaryWithObjectsAndKeys:fromPath, @"fromPath", toPath, @"toPath", nil];
	[renameQueue addObject:renameDictionary];
	[self queueSFTPCommandWithString:[NSString stringWithFormat:@"rename \"%@\" \"%@\"", fromPath, toPath]];
}
- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	NSDictionary *permissionChangeDictionary = [NSDictionary dictionaryWithObjectsAndKeys:path, @"remotePath", [NSNumber numberWithUnsignedLong:permissions], @"Permissions", nil];
	[permissionChangeQueue addObject:permissionChangeDictionary];
	
	NSString *command = [NSString stringWithFormat:@"chmod %lo \"%@\"", permissions, path];
	[self queueSFTPCommandWithString:command];
}
#pragma mark -
#pragma mark SFTPConnection Private
#pragma mark Command Queueing
- (void)queueSFTPCommand:(void *)cmd
{
	NSString *cmdString = [NSString stringWithUTF8String:(char *)cmd];
	[self queueSFTPCommandWithString:cmdString];
}

- (void)queueSFTPCommandWithString:(NSString *)cmdString
{
	[self logForCommandQueue:[NSString stringWithFormat:@"Queued \"%@\"", cmdString]];
	unsigned int queuePlacement = [commandQueue count];
	[commandQueue addObject:cmdString];
	if (queuePlacement == 0)
	{
		[self writeSFTPCommandWithString:cmdString];
	}
}

- (void)writeSFTPCommand:(void *)cmd
{
	int wr;
	if ((wr = write(master, cmd, strlen(cmd))) != strlen(cmd))
	{
		goto WRITE_ERROR;
	}
	if ((wr = write(master, "\n", strlen("\n"))) != strlen("\n"))
	{
		goto WRITE_ERROR;
	}
	return;
WRITE_ERROR:
	NSLog(@"Write Failed, wrong number of byes");
	exit(2);
}

- (void)writeSFTPCommandWithString:(NSString *)commandString
{
	if (!commandString)
	{
		return;
	}
	[self logForCommandQueue:[NSString stringWithFormat:@"Dispatching \"%@\"", commandString]];
	if ([commandString isEqualToString:@"CONNECT"])
	{
		return;
	}
	if ([commandString hasPrefix:@"put"])
	{
		[self uploadDidBegin:[self currentUploadInfo]];
	}
	else if ([commandString hasPrefix:@"get"])
	{
		[self downloadDidBegin:[self currentDownloadInfo]];
	}
	char *command = (char *)[commandString UTF8String];
	[self writeSFTPCommand:command];
}

#pragma mark Misc.
#pragma mark CoreSetup
- (void)establishDistributedObjectsConnection
{
	NSPort *receivePort = [NSPort port];
	NSPort *sendPort = [NSPort port];
	NSConnection *connectionToTServer = [[NSConnection alloc] initWithReceivePort:receivePort sendPort:sendPort];
	[connectionToTServer setRootObject:self];
	theSFTPTServer = nil;
	NSArray *portArray = [NSArray arrayWithObjects:sendPort, receivePort, nil];
	[NSThread detachNewThreadSelector:@selector(connectWithPorts:) toTarget:[SFTPTServer class] withObject:portArray];
}

- (void)logForCommandQueue:(NSString *)log
{
	BOOL shouldLogCommandQueue = [[NSUserDefaults standardUserDefaults] boolForKey:@"logCommandQueue"];
	if (!shouldLogCommandQueue)
	{
		return;
	}
	NSLog(@"%@", log);
}
@end

#pragma mark -
#pragma mark SFTP Backend Interface
@implementation SFTPConnection (BackendInterface)
- (void)logServerResponseBuffer:(NSString *)serverBuffer
{
	BOOL shouldLogServerResponseBuffer = [[NSUserDefaults standardUserDefaults] boolForKey:@"logServerResponseBuffer"];
	if (!shouldLogServerResponseBuffer)
	{
		return;
	}
	NSLog(@"%@", serverBuffer);
}

- (void)setMasterProxy:(int)masterProxy
{
	master = masterProxy;
}

- (void)setServerObject:(id)serverObject
{
	[serverObject setProtocolForProxy:@protocol(SFTPTServerInterface)];
	theSFTPTServer = [(SFTPTServer<SFTPTServerInterface>*)serverObject retain];
	
	if ([connectToQueue count] > 0)
	{
		NSArray *parameters = [connectToQueue objectAtIndex:0];
		[theSFTPTServer connectToServerWithParams:parameters fromWrapperConnection:self];
		[connectToQueue removeObjectAtIndex:0];
	}
}

- (void)finishedCommand
{
	if ([commandQueue count] <= 0)
	{
		return;
	}
	NSString *finishedCommand = [commandQueue objectAtIndex:0];
	[self logForCommandQueue:[NSString stringWithFormat:@"Finished \"%@\"", finishedCommand]];
	[self checkFinishedCommandStringForNotifications:finishedCommand];
	[commandQueue removeObjectAtIndex:0];	
	if ([commandQueue count] > 0)
	{
		BOOL shouldConfirmQueuedCommandDispatch = [[NSUserDefaults standardUserDefaults] boolForKey:@"shouldConfirmQueuedCommandDispatch"];
		BOOL performCommand = YES;
		if (shouldConfirmQueuedCommandDispatch)
		{
			performCommand = NSRunAlertPanel(@"Dispatch Next Command?", [NSString stringWithFormat:@"There is an additional command in the queue, \"%@\". Would you like to dispatch this command?", [commandQueue objectAtIndex:0]], @"Dispatch", @"Ignore", nil) == 1;
		}
		if (performCommand)
		{
			[self writeSFTPCommandWithString:[commandQueue objectAtIndex:0]];
		}
	}
	else
	{
		[self logForCommandQueue:@"CommandQueue is now empty."];
	}
}

- (void)checkFinishedCommandStringForNotifications:(NSString *)finishedCommand
{
	if ([finishedCommand hasPrefix:@"put"])
	{
		//Upload Finished
		[self uploadDidFinish:[self currentUploadInfo]];
	}
	else if ([finishedCommand hasPrefix:@"get"])
	{
		//Download Finished
		[self downloadDidFinish:[self currentDownloadInfo]];
	}
	//NOTE: We are checking for rmdir before rm because it would return yes for the "rm" prefix when it is really "rmdir
	else if ([finishedCommand hasPrefix:@"rmdir"])
	{
		//Deleted Directory
		[self didDeleteDirectory:[self currentDirectoryDeletionPath]];
	}	
	else if ([finishedCommand hasPrefix:@"rm"])
	{
		//Deleted File
		[self didDeleteFile:[self currentFileDeletionPath]];
	}
	else if ([finishedCommand hasPrefix:@"rename"])
	{
		//Renamed File/Directory
		[self didRename:[self currentRenameInfo]];
	}
	else if ([finishedCommand hasPrefix:@"chmod"])
	{
		[self didSetPermissionsForFile:[self currentPermissionChangeInfo]];
	}
	else if ([finishedCommand hasPrefix:@"cd"])
	{
		NSString *directory = [finishedCommand substringWithRange:NSMakeRange(4, [finishedCommand length] - 5)]; // from cd "httpdocs" to httpdocs
		[self didChangeToDirectory:directory];
	}
}

#pragma mark -
- (void)dequeueUpload
{
	[uploadQueue removeObjectAtIndex:0];
	if ([uploadQueue count] == 0)
	{
		isUploading = NO;
	}
}

- (void)dequeueDownload
{
	[downloadQueue removeObjectAtIndex:0];
	if ([downloadQueue count] == 0)
	{
		isDownloading = NO;
	}
}

- (void)dequeueFileDeletion
{
	[deleteFileQueue removeObjectAtIndex:0];
}

- (void)dequeueDirectoryDeletion
{
	[deleteDirectoryQueue removeObjectAtIndex:0];
}

- (void)dequeueRename
{
	[renameQueue removeObjectAtIndex:0];
}
- (void)dequeuePermissionChange
{
	[permissionChangeQueue removeObjectAtIndex:0];
}

#pragma mark -
- (CKInternalTransferRecord *)currentUploadInfo
{
	return [uploadQueue objectAtIndex:0];
}

- (CKInternalTransferRecord *)currentDownloadInfo
{
	return [downloadQueue objectAtIndex:0];
}

- (NSString *)currentFileDeletionPath
{
	return [deleteFileQueue objectAtIndex:0];
}

- (NSString *)currentDirectoryDeletionPath
{
	return [deleteDirectoryQueue objectAtIndex:0];
}

- (NSDictionary *)currentRenameInfo
{
	return [renameQueue objectAtIndex:0];
}
- (NSDictionary *)currentPermissionChangeInfo
{
	return [permissionChangeQueue objectAtIndex:0];
}

#pragma mark -
- (void)didReceiveDirectoryContents:(NSArray*)items
{
	if (_flags.directoryContents)
	{
		[_forwarder connection:self didReceiveContents:items ofDirectory:[NSString stringWithString:currentDirectory]];
	}
}
- (void)didChangeToDirectory:(NSString *)path
{
	if (_flags.changeDirectory)
	{
		[_forwarder connection:self didChangeToDirectory:path];
	}
}
#pragma mark -
- (void)upload:(CKInternalTransferRecord *)uploadInfo didProgressTo:(double)progressPercentage withEstimatedCompletionIn:(NSString *)estimatedCompletion givenTransferRateOf:(NSString *)rate amountTransferred:(unsigned long long)amountTransferred
{
	NSNumber *progress = [NSNumber numberWithDouble:progressPercentage];
	
	CKTransferRecord *record = [uploadInfo userInfo];
	
	if ([uploadInfo delegateRespondsToTransferProgressedTo])
	{
		[[uploadInfo delegate] transfer:record progressedTo:progress];
	}

	if (progressPercentage == 100.0 && [uploadInfo delegateRespondsToTransferDidFinish])
	{
		[[uploadInfo delegate] transferDidFinish:record];
	}
	else
	{
		unsigned long long previousTransferred = [record transferred];
		unsigned long long chunkLength = amountTransferred - previousTransferred;
		if ([uploadInfo delegateRespondsToTransferTransferredData])
		{
			[[uploadInfo delegate] transfer:record transferredDataOfLength:chunkLength];
		}
	}

	if (_flags.uploadPercent)
	{
		NSString *remotePath = [uploadInfo remotePath];
		[_forwarder connection:self upload:remotePath progressedTo:progress];
	}
}

- (void)uploadDidBegin:(CKInternalTransferRecord *)uploadInfo
{
	isUploading = YES;
	if ([uploadInfo delegateRespondsToTransferDidBegin])
	{
		[[uploadInfo delegate] transferDidBegin:[uploadInfo userInfo]];
	}		
	if (_flags.didBeginUpload)
	{
		NSString *remotePath = [uploadInfo remotePath];
		[_forwarder connection:self uploadDidBegin:remotePath];
	}
}

- (void)uploadDidFinish:(CKInternalTransferRecord *)uploadInfo
{
	NSString *remotePath = [NSString stringWithString:[uploadInfo remotePath]];
	[self dequeueUpload];	
	if (_flags.uploadFinished)
	{
		[_forwarder connection:self uploadDidFinish:remotePath];
	}
}

#pragma mark -
- (void)download:(CKInternalTransferRecord *)downloadInfo didProgressTo:(double)progressPercentage withEstimatedCompletionIn:(NSString *)estimatedCompletion givenTransferRateOf:(NSString *)rate amountTransferred:(unsigned long long)amountTransferred
{
	NSNumber *progress = [NSNumber numberWithDouble:progressPercentage];
	
	CKTransferRecord *record = [downloadInfo userInfo];
	
	if ([downloadInfo delegateRespondsToTransferProgressedTo])
	{
		[[downloadInfo delegate] transfer:record progressedTo:progress];
	}
	
	if (progressPercentage == 100.0 && [downloadInfo delegateRespondsToTransferDidFinish])
	{
		[[downloadInfo delegate] transferDidFinish:record];
	}
	else
	{
		unsigned long long previousTransferred = [record transferred];
		unsigned long long chunkLength = amountTransferred - previousTransferred;
		if ([downloadInfo delegateRespondsToTransferTransferredData])
		{
			[[downloadInfo delegate] transfer:record transferredDataOfLength:chunkLength];
		}
	}
	
	if (_flags.downloadPercent)
	{
		NSString *remotePath = [downloadInfo remotePath];
		[_forwarder connection:self download:remotePath progressedTo:progress];
	}
}
- (void)downloadDidBegin:(CKInternalTransferRecord *)downloadInfo
{
	isDownloading = YES;
	if (_flags.didBeginDownload)
	{
		NSString *remotePath = [downloadInfo objectForKey:@"remotePath"];
		[_forwarder connection:self downloadDidBegin:remotePath];
	}
}

- (void)downloadDidFinish:(CKInternalTransferRecord *)downloadInfo
{
	NSString *remotePath = [NSString stringWithString:[downloadInfo remotePath]];
	[self dequeueDownload];
	if (_flags.downloadFinished)
	{
		[_forwarder connection:self downloadDidFinish:remotePath];
	}
}

#pragma mark -
- (void)didDeleteFile:(NSString *)remotePath
{
	NSString *ourRemotePath = [NSString stringWithString:remotePath];
	[self dequeueFileDeletion];
	if (_flags.deleteFile)
	{
		[_forwarder connection:self didDeleteFile:ourRemotePath];
	}
}

- (void)didDeleteDirectory:(NSString *)remotePath
{
	NSString *ourRemotePath = [NSString stringWithString:remotePath];
	[self dequeueDirectoryDeletion];
	if (_flags.deleteDirectory)
	{
		[_forwarder connection:self didDeleteDirectory:ourRemotePath];
	}
}

#pragma mark -
- (void)didRename:(NSDictionary *)renameInfo
{
	NSString *fromPath = [NSString stringWithString:[renameInfo objectForKey:@"fromPath"]];
	NSString *toPath = [NSString stringWithString:[renameInfo objectForKey:@"toPath"]];
	[self dequeueRename];
	if (_flags.rename)
	{
		[_forwarder connection:self didRename:fromPath to:toPath];
	}
}
- (void)didSetPermissionsForFile:(NSDictionary *)permissionInfo
{
	NSString *remotePath = [NSString stringWithString:[permissionInfo objectForKey:@"remotePath"]];
	[self dequeuePermissionChange];
	if (_flags.permissions)
	{
		[_forwarder connection:self didSetPermissionsForFile:remotePath];
	}
}

#pragma mark -
- (void)requestPasswordWithPrompt:(char *)header
{
	if (![self password])
	{
		[self passwordErrorOccurred];
		return;
	}
	[self writeSFTPCommandWithString:[self password]];
}

- (void)getContinueQueryForUnknownHost:(NSDictionary *)hostInfo
{
	//Authenticity of the host couldn't be established. yes/no scenario
	[self writeSFTPCommandWithString:@"yes"];
}
- (void)passphraseRequested:(NSString *)buffer
{
	//Typical Buffer: Enter passphrase for key '/Users/brian/.ssh/id_rsa': 
	
	NSString *pubKeyPath = [buffer substringWithRange:NSMakeRange(26, [buffer length]-29)];
	
	//Try to get it ourselves via keychain before asking client app for it
	EMGenericKeychainItem *item = [[EMKeychainProxy sharedProxy] genericKeychainItemForService:@"SSH" withUsername:pubKeyPath];
	if (item && [item password] && ![attemptedKeychainPublicKeyAuthentications containsObject:pubKeyPath])
	{
		[attemptedKeychainPublicKeyAuthentications addObject:pubKeyPath];
		[self writeSFTPCommandWithString:[item password]];
		return;
	}
	
	//We don't have it on keychain, so ask the delegate for it if we can, or ask ourselves if not.	
	NSString *passphrase = nil;
	if (_flags.passphrase)
	{
		passphrase = [_forwarder connection:self passphraseForHost:[self host] username:[self username] publicKeyPath:pubKeyPath];
	}
	else
	{
		//No delegate method implemented, and it's not already on the keychain. Ask ourselves.
		SSHPassphrase *passphraseFetcher = [[SSHPassphrase alloc] init];
		passphrase = [passphraseFetcher passphraseForPublicKey:pubKeyPath account:[self username]];
		[passphraseFetcher release];
	}
	
	if (passphrase)
	{
		[self writeSFTPCommandWithString:passphrase];
		return;
	}	
	
	[self passwordErrorOccurred];
}

- (void)didConnect
{
	//Clear any failed pubkey authentications as we're now connected
	[attemptedKeychainPublicKeyAuthentications removeAllObjects];
	
	isConnected = YES;
	if (_flags.didConnect)
	{
		[_forwarder connection:self didConnectToHost:[self host]];
	}
	if (_flags.didAuthenticate)
	{
		[_forwarder connection:self didAuthenticateToHost:[self host]];
	}		
}
- (void)didDisconnect
{
	isConnected = NO;
	if (_flags.didDisconnect)
	{
		[_forwarder connection:self didDisconnectFromHost:[self host]];
	}
}
- (void)setCurrentRemotePath:(NSString *)remotePath
{
	[currentDirectory setString:remotePath];
}
- (void)passwordErrorOccurred
{
	if (_flags.badPassword)
	{
		[_forwarder connectionDidSendBadPassword:self];
	}
}

- (void)connectionError:(NSError *)theError
{
	if (_flags.error)
	{
		[_forwarder connection:self didReceiveError:theError];
	}
}
- (void)addStringToTranscript:(NSString *)stringToAdd
{
	[self appendToTranscript:[NSAttributedString attributedStringWithString:stringToAdd attributes:[AbstractConnection receivedAttributes]]];
}
@end
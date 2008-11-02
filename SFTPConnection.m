//
//  SFTPConnection.m
//  CocoaSFTP
//
//  Created by Brian Amerige on 11/4/07.
//  Copyright 2007 Extendmac, LLC.. All rights reserved.
//

#import "SFTPConnection.h"

#import "ConnectionThreadManager.h"
#import "RunLoopForwarder.h"
#import "SSHPassphrase.h"
#import "CKTransferRecord.h"
#import "CKInternalTransferRecord.h"
#import "EMKeychainProxy.h"
#import "FTPConnection.h"
#import "AbstractConnectionProtocol.h"

#import "NSFileManager+Connection.h"
#import "NSString+Connection.h"

#include "sshversion.h"
#include "fdwrite.h"

@interface SFTPConnection (Private)
- (void)_writeSFTPCommandWithString:(NSString *)commandString;
- (void)_handleFinishedCommand:(ConnectionCommand *)command serverErrorResponse:(NSString *)errorResponse;
//
- (void)_finishedCommandInConnectionAwaitingCurrentDirectoryState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse;
- (void)_finishedCommandInConnectionChangingDirectoryState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse;
- (void)_finishedCommandInConnectionCreateDirectoryState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse;
- (void)_finishedCommandInConnectionAwaitingRenameState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse;
- (void)_finishedCommandInConnectionSettingPermissionState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse;
- (void)_finishedCommandInConnectionDeleteFileState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse;
- (void)_finishedCommandInConnectionDeleteDirectoryState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse;
- (void)_finishedCommandInConnectionUploadingFileState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse;
- (void)_finishedCommandInConnectionDownloadingFileState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse;
//
- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  orData:(NSData *)data 
						  offset:(unsigned long long)offset 
					  remotePath:(NSString *)remotePath
			checkRemoteExistence:(BOOL)flag
						delegate:(id)delegate;
- (void)uploadDidBegin:(CKInternalTransferRecord *)uploadInfo;
//
- (void)passwordErrorOccurred;
@end

@implementation SFTPConnection

NSString *SFTPErrorDomain = @"SFTPErrorDomain";
static NSString *lsform = nil;

#pragma mark -
#pragma mark Getting Started / Tearing Down
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

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
				 error:(NSError **)error
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
		connectToQueue = [[NSMutableArray array] retain];
		currentDirectory = [[NSMutableString string] retain];
		attemptedKeychainPublicKeyAuthentications = [[NSMutableArray array] retain];
	}
	return self;
}

- (void)_establishDistributedObjectsConnection
{	
	NSPort *receivePort = [NSPort port];
	NSPort *sendPort = [NSPort port];
	// intentional leak, follows TrivialThreads sample code, connectionWithReceivePort:sendPort: does not work
	if (connectionToTServer)
	{
		[connectionToTServer invalidate];
		[connectionToTServer release];
		connectionToTServer = nil;
	}
	connectionToTServer = [[NSConnection alloc] initWithReceivePort:receivePort sendPort:sendPort];
	[connectionToTServer setRootObject:self];
	theSFTPTServer = nil;
	NSArray *portArray = [NSArray arrayWithObjects:sendPort, receivePort, nil];
	[NSThread detachNewThreadSelector:@selector(connectWithPorts:) toTarget:[SFTPTServer class] withObject:portArray];
}

- (void)setServerObject:(id)serverObject
{
	[serverObject setProtocolForProxy:@protocol(SFTPTServerInterface)];
	theSFTPTServer = [(SFTPTServer<SFTPTServerInterface>*)serverObject retain];
	
	if ([connectToQueue count] > 0)
	{
		NSArray *parameters = [connectToQueue objectAtIndex:0];
		
		[self _setupConnectTimeOut];
		
		isConnecting = YES;
		[theSFTPTServer connectToServerWithArguments:parameters forWrapperConnection:self];
		[connectToQueue removeObjectAtIndex:0];
	}
}

- (void)_setupConnectTimeOut
{
	//Set up a timeout for connecting. If we're not connected in 10 seconds, error!
	unsigned timeout = 10;
	NSNumber *defaultsValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"CKFTPDataConnectionTimeoutValue"];
	if (defaultsValue) {
		timeout = [defaultsValue unsignedIntValue];
	}
	
	_connectTimeoutTimer = [[NSTimer scheduledTimerWithTimeInterval:timeout
															 target:self
														   selector:@selector(_connectTimeoutTimerFire:)
														   userInfo:nil
															repeats:NO] retain];
}

- (void)dealloc
{
	[connectToQueue release];
	[currentDirectory release];
	[rootDirectory release];
	[attemptedKeychainPublicKeyAuthentications release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Accessors

- (int)masterProxy { return masterProxy; }

- (void)setMasterProxy:(int)proxy
{
	masterProxy = proxy;
}

#pragma mark -
#pragma mark Connecting
- (void)connect
{
	if (isConnecting)
		return;
		
	if (![self username])
	{
		//Can't do anything here, throw an error.
		return;
	}
	NSMutableArray *parameters = [NSMutableArray array];
	BOOL enableCompression = NO; //We do support this on the backend, but we have no UI for it yet.
	if (enableCompression)
		[parameters addObject:@"-C"];
	if (![[self port] isEqualToString:@""])
		[parameters addObject:[NSString stringWithFormat:@"-o Port=%i", [[self port] intValue]]];
	if ([self password] && [[self password] length] > 0)
		[parameters addObject:@"-o PubkeyAuthentication=no"];
	else
	{
		NSString *publicKeyPath = [self propertyForKey:@"CKSFTPPublicKeyPath"];
		if (publicKeyPath && [publicKeyPath length] > 0)
			[parameters addObject:[NSString stringWithFormat:@"-o IdentityFile=%@", publicKeyPath]];
		else
		{
			[parameters addObject:[NSString stringWithFormat:@"-o IdentityFile=~/.ssh/%@", [self username]]];
			[parameters addObject:@"-o IdentityFile=~/.ssh/id_rsa"];
			[parameters addObject:@"-o IdentityFile=~/.ssh/id_dsa"];
		}
	}
	[parameters addObject:[NSString stringWithFormat:@"%@@%@", [self username], [self host]]];
	
	switch (sshversion())
	{
		case SFTP_VERSION_UNSUPPORTED:
			//Not Supported.
			return;
		case SFTP_LS_LONG_FORM:
			lsform = @"ls -l";
			break;
			
		case SFTP_LS_EXTENDED_LONG_FORM:
			lsform = @"ls -la";
			break;
			
		case SFTP_LS_SHORT_FORM:
		default:
			lsform = @"ls";
			break;
    }
	
	if (isConnecting || _flags.isConnected)
		return;
	
	if (!theSFTPTServer)
	{
		[connectToQueue addObject:parameters];
		[self performSelectorOnMainThread:@selector(_establishDistributedObjectsConnection) withObject:nil waitUntilDone:NO];
		return;
	}
	
	[self _setupConnectTimeOut];
	
	isConnecting = YES;
	[theSFTPTServer connectToServerWithArguments:parameters forWrapperConnection:self];
}

#pragma mark -
#pragma mark Disconnecting
- (void)disconnect
{
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedDisconnect];
}

- (void)threadedDisconnect
{
	ConnectionCommand *quit = [ConnectionCommand command:@"quit"
											  awaitState:ConnectionIdleState
											   sentState:ConnectionSentDisconnectState
											   dependant:nil
												userInfo:nil];
	[self queueCommand:quit];
}

- (void)forceDisconnect
{
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedForceDisconnect];
}

- (void)threadedForceDisconnect
{
	[self didDisconnect];
}


#pragma mark -
#pragma mark Directory Changes
- (NSString *)rootDirectory
{
	return rootDirectory;
}

- (NSString *)currentDirectory
{
	return [NSString stringWithString:currentDirectory];
}

- (void)changeToDirectory:(NSString *)newDir
{
	ConnectionCommand *pwd = [ConnectionCommand command:@"pwd" 
											 awaitState:ConnectionIdleState
											  sentState:ConnectionAwaitingCurrentDirectoryState
											  dependant:nil
											   userInfo:nil];
	ConnectionCommand *cd = [ConnectionCommand command:[NSString stringWithFormat:@"cd \"%@\"", newDir]
											awaitState:ConnectionIdleState
											 sentState:ConnectionChangingDirectoryState
											 dependant:pwd
											  userInfo:nil];
	[self queueCommand:cd];
	[self queueCommand:pwd];
}

- (void)contentsOfDirectory:(NSString *)newDir
{
	[self changeToDirectory:newDir];
	[self directoryContents];
}

- (void)directoryContents
{
	ConnectionCommand *ls = [ConnectionCommand command:lsform
											awaitState:ConnectionIdleState
											 sentState:ConnectionAwaitingDirectoryContentsState
											 dependant:nil
											  userInfo:nil];
	[self queueCommand:ls];
}

#pragma mark -
#pragma mark File Manipulation
- (void)createDirectory:(NSString *)newDirectoryPath
{
	NSAssert(newDirectoryPath && ![newDirectoryPath isEqualToString:@""], @"no directory specified");
	
	ConnectionCommand *mkd = [ConnectionCommand command:[NSString stringWithFormat:@"mkdir \"%@\"", newDirectoryPath]
											 awaitState:ConnectionIdleState
											  sentState:ConnectionCreateDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:mkd];
}

- (void)createDirectory:(NSString *)newDirectoryPath permissions:(unsigned long)permissions
{
	[self createDirectory:newDirectoryPath];
	[self setPermissions:permissions forFile:newDirectoryPath];
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSAssert(fromPath && ![fromPath isEqualToString:@""], @"fromPath is nil!");
	NSAssert(toPath && ![toPath isEqualToString:@""], @"toPath is nil!");
	
	[self queueRename:fromPath];
	[self queueRename:toPath];
	
	ConnectionCommand *rename = [ConnectionCommand command:[NSString stringWithFormat:@"rename \"%@\" \"%@\"", fromPath, toPath]
												awaitState:ConnectionIdleState
												 sentState:ConnectionAwaitingRenameState
												 dependant:nil
												  userInfo:nil];
	[self queueCommand:rename];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"no file/path specified");
	
	[self queuePermissionChange:path];
	ConnectionCommand *chmod = [ConnectionCommand command:[NSString stringWithFormat:@"chmod %lo \"%@\"", permissions, path]
											   awaitState:ConnectionIdleState
												sentState:ConnectionSettingPermissionsState
												dependant:nil
												 userInfo:nil];
	[self queueCommand:chmod];
}

#pragma mark -
#pragma mark Uploading
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
		localPath = [remotePath lastPathComponent];
	if (!remotePath)
		remotePath = [[self currentDirectory] stringByAppendingPathComponent:[localPath lastPathComponent]];
	
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
	
	[self queueUpload:internalRecord];
	
	ConnectionCommand *upload = [ConnectionCommand command:[NSString stringWithFormat:@"put \"%@\" \"%@\"", localPath, remotePath]
												awaitState:ConnectionIdleState
												 sentState:ConnectionUploadingFileState
												 dependant:nil
												  userInfo:nil];
	[self queueCommand:upload];
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
#pragma mark Downloading
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
	
	if (!flag && [[NSFileManager defaultManager] fileExistsAtPath:localPath])
	{
		if (_flags.error)
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"Local File already exists", @"FTP download error"), NSLocalizedDescriptionKey,
									  remotePath, NSFilePathErrorKey, nil];
			NSError *error = [NSError errorWithDomain:SFTPErrorDomain code:FTPDownloadFileExists userInfo:userInfo];
			[_forwarder connection:self didReceiveError:error];
		}
		return nil;
	}
	
	CKTransferRecord *record = [CKTransferRecord recordWithName:remotePath size:0];
	[record setProperty:remotePath forKey:QueueDownloadRemoteFileKey];
	[record setProperty:localPath forKey:QueueDownloadDestinationFileKey];
	[record setProperty:[NSNumber numberWithInt:0] forKey:QueueDownloadTransferPercentReceived];
	
	CKInternalTransferRecord *internalTransferRecord = [CKInternalTransferRecord recordWithLocal:localPath
																							data:nil
																						  offset:0
																						  remote:remotePath
																						delegate:delegate ? delegate : record
																						userInfo:record];

	[self queueDownload:internalTransferRecord];
	
	ConnectionCommand *download = [ConnectionCommand command:[NSString stringWithFormat:@"get \"%@\" \"%@\"", remotePath, localPath]
												  awaitState:ConnectionIdleState
												   sentState:ConnectionDownloadingFileState
												   dependant:nil
													userInfo:nil];
	[self queueCommand:download];
	
	return record;
}

#pragma mark -
#pragma mark Deletion
- (void)deleteFile:(NSString *)remotePath
{
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"path is nil!");
	
	[self queueDeletion:remotePath];
	
	ConnectionCommand *delete = [ConnectionCommand command:[NSString stringWithFormat:@"rm \"%@\"", remotePath]
												awaitState:ConnectionIdleState
												 sentState:ConnectionDeleteFileState
												 dependant:nil
												  userInfo:nil];
	[self queueCommand:delete];
}

- (void)deleteDirectory:(NSString *)remotePath
{
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
	[self queueDeletion:remotePath];
	
	ConnectionCommand *delete = [ConnectionCommand command:[NSString stringWithFormat:@"rmdir \"%@\"", remotePath]
												awaitState:ConnectionIdleState
												 sentState:ConnectionDeleteDirectoryState
												 dependant:nil
												  userInfo:nil];
	[self queueCommand:delete];
}

#pragma mark -
#pragma mark Misc.
- (void)threadedCancelTransfer
{
	[self forceDisconnect];
	[self connect];
}

#pragma mark -
#pragma mark Command Queueing
- (void)sendCommand:(id)command
{
	[self _writeSFTPCommandWithString:command];
}

- (void)_writeSFTPCommand:(void *)cmd
{
	if (!theSFTPTServer)
		return;
	size_t commandLength = strlen(cmd);
	if ( commandLength > 0 )
	{
		// Sandvox, at least, consistently gets -1 back after sending quit
		// this trap allows execution to continue
		// THIS MAY BE AN ISSUE FOR OTHER APPS
		BOOL isQuitCommand = (0 == strcmp(cmd, "quit"));
		ssize_t bytesWritten = write(masterProxy, cmd, strlen(cmd));
		if ( bytesWritten != commandLength && !isQuitCommand )
		{
			NSLog(@"_writeSFTPCommand: %@ failed writing command", [NSString stringWithUTF8String:cmd]);
		}
		
		commandLength = strlen("\n");
		bytesWritten = write(masterProxy, "\n", strlen("\n"));
		if ( bytesWritten != commandLength && !isQuitCommand )
		{
			NSLog(@"_writeSFTPCommand %@ failed writing newline", [NSString stringWithUTF8String:cmd]);
		}
	}
}

- (void)_writeSFTPCommandWithString:(NSString *)commandString
{
	if (!commandString)
		return;
	if ([commandString isEqualToString:@"CONNECT"])
		return;
	if ([commandString hasPrefix:@"put"])
		[self uploadDidBegin:[self currentUpload]];
	else if ([commandString hasPrefix:@"get"])
		[self downloadDidBegin:[self currentDownload]];
	char *command = (char *)[commandString UTF8String];
	[self _writeSFTPCommand:command];
}

#pragma mark -

- (void)finishedCommand
{
	ConnectionCommand *finishedCommand = [self lastCommand];
	[self _handleFinishedCommand:finishedCommand serverErrorResponse:nil];
}

- (void)receivedErrorInServerResponse:(NSString *)serverResponse
{
	ConnectionCommand *erroredCommand = [self lastCommand];
	[self _handleFinishedCommand:erroredCommand serverErrorResponse:serverResponse];
}

- (void)_handleFinishedCommand:(ConnectionCommand *)command serverErrorResponse:(NSString *)errorResponse
{
	ConnectionState finishedState = GET_STATE;
		
	switch (finishedState)
	{
		case ConnectionAwaitingCurrentDirectoryState:
			[self _finishedCommandInConnectionAwaitingCurrentDirectoryState:[command command] serverErrorResponse:errorResponse];
			break;
		case ConnectionChangingDirectoryState:
			[self _finishedCommandInConnectionChangingDirectoryState:[command command] serverErrorResponse:errorResponse];
			break;
		case ConnectionCreateDirectoryState:
			[self _finishedCommandInConnectionCreateDirectoryState:[command command] serverErrorResponse:errorResponse];
			break;
		case ConnectionAwaitingRenameState:
			[self _finishedCommandInConnectionAwaitingRenameState:[command command] serverErrorResponse:errorResponse];
			break;
		case ConnectionSettingPermissionsState:
			[self _finishedCommandInConnectionSettingPermissionState:[command command] serverErrorResponse:errorResponse];
			break;
		case ConnectionDeleteFileState:
			[self _finishedCommandInConnectionDeleteFileState:[command command] serverErrorResponse:errorResponse];
			break;
		case ConnectionDeleteDirectoryState:
			[self _finishedCommandInConnectionDeleteDirectoryState:[command command] serverErrorResponse:errorResponse];
			break;
		case ConnectionUploadingFileState:
			[self _finishedCommandInConnectionUploadingFileState:[command command] serverErrorResponse:errorResponse];
			break;
		case ConnectionDownloadingFileState:
			[self _finishedCommandInConnectionDownloadingFileState:[command command] serverErrorResponse:errorResponse];
			break;
		default:
			break;
	}
	[self setState:ConnectionIdleState];
}

#pragma mark -

- (void)_finishedCommandInConnectionAwaitingCurrentDirectoryState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse
{
	NSError *error = nil;
	NSString *path = [self currentDirectory];
	if (errorResponse)
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to change to directory", @"Failed to change to directory");
		if ([errorResponse containsSubstring:@"permission"]) //Permission issue
			localizedDescription = LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedDescription, NSLocalizedDescriptionKey, path, NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:SFTPErrorDomain code:0 userInfo:userInfo];
	}
	
	//We don't need to parse anything for the current directory, it's set by SFTPTServer.
	if (_flags.changeDirectory)
		[_forwarder connection:self didChangeToDirectory:path error:error];
}

- (void)_finishedCommandInConnectionChangingDirectoryState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse
{
	//Temporarily don't do anything here (handled by PWD)
	return;
	
	//Typical Command string is			cd "/blah/blah/blah"
	NSRange pathRange = NSMakeRange(4, [commandString length] - 5);
	NSString *path = ([commandString length] > NSMaxRange(pathRange)) ? [commandString substringWithRange:pathRange] : nil;
	
	NSError *error = nil;
	if (errorResponse)
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to change to directory", @"Failed to change to directory");
		if ([errorResponse containsSubstring:@"permission"]) //Permission issue
			localizedDescription = LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedDescription, NSLocalizedDescriptionKey, path, NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:SFTPErrorDomain code:0 userInfo:userInfo];
	}
	
	if (_flags.changeDirectory)
		[_forwarder connection:self didChangeToDirectory:path error:error];	
}

- (void)_finishedCommandInConnectionCreateDirectoryState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse
{
	//CommandString typically is	mkdir "/path/to/new/dir"
	NSRange pathRange = NSMakeRange(7, [commandString length] - 8); //8 chops off last quote too
	NSString *path = ([commandString length] > NSMaxRange(pathRange)) ? [commandString substringWithRange:pathRange] : nil;
	
	NSError *error = nil;
	if (errorResponse)
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Create directory operation failed", @"Create directory operation failed");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedDescription, NSLocalizedDescriptionKey, path, NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:SFTPErrorDomain code:0 userInfo:userInfo];
	}
	
	if (_flags.createDirectory)
		[_forwarder connection:self didCreateDirectory:path error:error];
	
}

- (void)_finishedCommandInConnectionAwaitingRenameState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse
{
	NSString *fromPath = [_fileRenames objectAtIndex:0];
	NSString *toPath = [_fileRenames objectAtIndex:1];

	NSError *error = nil;
	if (errorResponse)
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to rename file.", @"Failed to rename file.");
		if ([errorResponse containsSubstring:@"permission"]) //Permission issue
			localizedDescription = LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedDescription, NSLocalizedDescriptionKey, fromPath, @"fromPath", toPath, @"toPath", nil];
		error = [NSError errorWithDomain:SFTPErrorDomain code:0 userInfo:userInfo];		
	}
	
	[fromPath retain];
	[toPath retain];
	
	[_fileRenames removeObjectAtIndex:0];
	[_fileRenames removeObjectAtIndex:0];							 
	
	if (_flags.rename)
		[_forwarder connection:self didRename:fromPath to:toPath error:error];

	[fromPath release];
	[toPath release];
}

- (void)_finishedCommandInConnectionSettingPermissionState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse
{
	NSError *error = nil;
	if (errorResponse)
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to set permissions for path %@", @"SFTP Upload error");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  localizedDescription, NSLocalizedDescriptionKey, 
								  [self currentPermissionChange], NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:SFTPErrorDomain code:0 userInfo:userInfo];				
	}
	
	if (_flags.permissions)
		[_forwarder connection:self didSetPermissionsForFile:[self currentPermissionChange] error:error];
	[self dequeuePermissionChange];
}

- (void)_finishedCommandInConnectionDeleteFileState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse
{
	NSError *error = nil;
	if (errorResponse)
	{
		NSString *localizedDescription = [NSString stringWithFormat:@"%@: %@", LocalizedStringInConnectionKitBundle(@"Failed to delete file", @"couldn't delete the file"), [[self currentDirectory] stringByAppendingPathComponent:[self currentDeletion]]];
		if ([errorResponse containsSubstring:@"permission"]) //Permission issue
			localizedDescription = LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedDescription, NSLocalizedDescriptionKey, [self currentDeletion], NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:SFTPErrorDomain code:0 userInfo:userInfo];				
	}
	
	if (_flags.deleteFile)
		[_forwarder connection:self didDeleteFile:[self currentDeletion] error:error];
	[self dequeueDeletion];
}

- (void)_finishedCommandInConnectionDeleteDirectoryState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse
{
	NSError *error = nil;
	if (errorResponse)
	{
		NSString *localizedDescription = [NSString stringWithFormat:@"%@: %@", LocalizedStringInConnectionKitBundle(@"Failed to delete file", @"couldn't delete the file"), [[self currentDirectory] stringByAppendingPathComponent:[self currentDeletion]]];
		if ([errorResponse containsSubstring:@"permission"]) //Permission issue
			localizedDescription = LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedDescription, NSLocalizedDescriptionKey, [self currentDeletion], NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:SFTPErrorDomain code:0 userInfo:userInfo];				
	}
	
	if (_flags.deleteDirectory)
		[_forwarder connection:self didDeleteDirectory:[self currentDeletion] error:error];
	[self dequeueDeletion];
}

- (void)_finishedCommandInConnectionUploadingFileState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse
{
	NSError *error = nil;
	if (errorResponse)
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to upload file.", @"Failed to upload file.");
		if ([errorResponse containsSubstring:@"permission"]) //Permission issue
			localizedDescription = LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedDescription, NSLocalizedDescriptionKey, [[self currentUpload] remotePath], NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:SFTPErrorDomain code:0 userInfo:userInfo];				
	}
	
	CKInternalTransferRecord *upload = [[self currentUpload] retain]; 
	[self dequeueUpload];
	
	if (_flags.uploadFinished)
		[_forwarder connection:self uploadDidFinish:[upload remotePath] error:error];
	if ([upload delegateRespondsToTransferDidFinish])
		[[upload delegate] transferDidFinish:[upload userInfo] error:error];

	[upload release];
}

- (void)_finishedCommandInConnectionDownloadingFileState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse
{
	//We only act here if there is an error OR if the file we're downloaded finished without delivering progress (usually small files). We otherwise handle dequeueing and download notifications when the progress reaches 100.
	
	NSError *error = nil;
	if (errorResponse)
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to download file.", @"Failed to download file.");
		if ([errorResponse containsSubstring:@"permission"]) //Permission issue
			localizedDescription = LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedDescription, NSLocalizedDescriptionKey, [[self currentDownload] remotePath], NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:SFTPErrorDomain code:0 userInfo:userInfo];				
	}
	
	CKInternalTransferRecord *download = [[self currentDownload] retain]; 
	[self dequeueDownload];
	
	if (_flags.downloadFinished)
		[_forwarder connection:self downloadDidFinish:[download remotePath] error:error];
	if ([download delegateRespondsToTransferDidFinish])
		[[download delegate] transferDidFinish:[download userInfo] error:error];
	if (_flags.error)
		[_forwarder connection:self didReceiveError:error];
	
	[download release];	
}

#pragma mark -
#pragma mark SFTPTServer Callbacks
- (void)didConnect
{
	if (_connectTimeoutTimer && [_connectTimeoutTimer isValid])
	{
		[_connectTimeoutTimer invalidate];
		[_connectTimeoutTimer release];
	}
	
	//Clear any failed pubkey authentications as we're now connected
	[attemptedKeychainPublicKeyAuthentications removeAllObjects];
	
	//Request the remote working directory
	ConnectionCommand *getCurrentDirectoryCommand = [ConnectionCommand command:@"pwd"
																	awaitState:ConnectionIdleState
																	 sentState:ConnectionAwaitingCurrentDirectoryState
																	 dependant:nil
																	  userInfo:nil];
	[self pushCommandOnCommandQueue:getCurrentDirectoryCommand];
}

- (void)_connectTimeoutTimerFire:(NSTimer *)timer
{
	[timer release];
	
	if (_flags.didConnect)
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Timed Out waiting for remote host.", @"time out");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  localizedDescription, NSLocalizedDescriptionKey, 
								  [self host], ConnectionHostKey, nil];
		
		NSError *error = [NSError errorWithDomain:SFTPErrorDomain code:StreamErrorTimedOut userInfo:userInfo];
		[_forwarder connection:self didConnectToHost:[self host] error:error];
	}
}

- (void)didSetRootDirectory
{
	rootDirectory = [[NSString alloc] initWithString:currentDirectory];
	
	isConnecting = NO;
	_flags.isConnected = YES;
	
	if (_flags.didConnect)
		[_forwarder connection:self didConnectToHost:[self host] error:nil];
	if (_flags.didAuthenticate)
		[_forwarder connection:self didAuthenticateToHost:[self host] error:nil];
}

- (void)setCurrentDirectory:(NSString *)current
{
	[currentDirectory setString:current];
}

- (void)didDisconnect
{
	if (connectionToTServer)
	{
		[connectionToTServer invalidate];
		[connectionToTServer release];
		connectionToTServer = nil;
	}
	if (theSFTPTServer)
	{
		[theSFTPTServer release];
		theSFTPTServer = nil;
	}
		
	[attemptedKeychainPublicKeyAuthentications removeAllObjects];			
	
	_flags.isConnected = NO;
	if (_flags.didDisconnect)
	{
		[_forwarder connection:self didDisconnectFromHost:[self host]];
	}
}

- (void)didReceiveDirectoryContents:(NSArray*)items
{
	if (_flags.directoryContents)
		[_forwarder connection:self didReceiveContents:items ofDirectory:[NSString stringWithString:currentDirectory] error:nil];
}

- (void)upload:(CKInternalTransferRecord *)uploadInfo didProgressTo:(double)progressPercentage withEstimatedCompletionIn:(NSString *)estimatedCompletion givenTransferRateOf:(NSString *)rate amountTransferred:(unsigned long long)amountTransferred
{
	CKTransferRecord *record = [uploadInfo userInfo];
	NSNumber *progress = [NSNumber numberWithDouble:progressPercentage];
	
	if ([uploadInfo delegateRespondsToTransferProgressedTo])
		[[uploadInfo delegate] transfer:record progressedTo:progress];
	if (_flags.uploadPercent)
	{
		NSString *remotePath = [uploadInfo remotePath];
		[_forwarder connection:self upload:remotePath progressedTo:progress];
	}
	
	
	if (progressPercentage != 100.0)
	{
		unsigned long long previousTransferred = [record transferred];
		unsigned long long chunkLength = amountTransferred - previousTransferred;
		if ([uploadInfo delegateRespondsToTransferTransferredData])
			[[uploadInfo delegate] transfer:record transferredDataOfLength:chunkLength];
	}
}

- (void)uploadDidBegin:(CKInternalTransferRecord *)uploadInfo
{
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

- (void)download:(CKInternalTransferRecord *)downloadInfo didProgressTo:(double)progressPercentage withEstimatedCompletionIn:(NSString *)estimatedCompletion givenTransferRateOf:(NSString *)rate amountTransferred:(unsigned long long)amountTransferred
{
	NSNumber *progress = [NSNumber numberWithDouble:progressPercentage];
	
	CKTransferRecord *record = [downloadInfo userInfo];
	
	if ([downloadInfo delegateRespondsToTransferProgressedTo])
	{
		[[downloadInfo delegate] transfer:record progressedTo:progress];
	}
	
	if (progressPercentage != 100.0)
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
	if (_flags.didBeginDownload)
	{
		NSString *remotePath = [downloadInfo objectForKey:@"remotePath"];
		[_forwarder connection:self downloadDidBegin:remotePath];
	}
	if ([downloadInfo delegateRespondsToTransferDidBegin])
		[[downloadInfo delegate] transferDidBegin:[downloadInfo userInfo]];
}

#pragma mark -
- (void)requestPasswordWithPrompt:(char *)header
{
	if (![self password])
	{
		[self passwordErrorOccurred];
		return;
	}
	[self _writeSFTPCommandWithString:[self password]];
}

- (void)getContinueQueryForUnknownHost:(NSDictionary *)hostInfo
{
	//Authenticity of the host couldn't be established. yes/no scenario
	[self _writeSFTPCommandWithString:@"yes"];
}
- (void)passphraseRequested:(NSString *)buffer
{
	//Typical Buffer: Enter passphrase for key '/Users/brian/.ssh/id_rsa': 
	
	NSString *pubKeyPath = [buffer substringWithRange:NSMakeRange(26, [buffer length]-29)];
	
	//Try to get it ourselves via keychain before asking client app for it
	EMGenericKeychainItem *item = [[EMKeychainProxy sharedProxy] genericKeychainItemForService:@"SSH" withUsername:pubKeyPath];
	if (item && [item password] && [[item password] length] > 0 && ![attemptedKeychainPublicKeyAuthentications containsObject:pubKeyPath])
	{
		[attemptedKeychainPublicKeyAuthentications addObject:pubKeyPath];
		[self _writeSFTPCommandWithString:[item password]];
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
		[self _writeSFTPCommandWithString:passphrase];
		return;
	}	
	
	[self passwordErrorOccurred];
}

- (void)passwordErrorOccurred
{
	if (_flags.badPassword)
	{
		[_forwarder connectionDidSendBadPassword:self];
	}
}

- (void)addStringToTranscript:(NSString *)stringToAdd
{
	[self appendToTranscript:[NSAttributedString attributedStringWithString:stringToAdd attributes:[AbstractConnection receivedAttributes]]];
}

@end
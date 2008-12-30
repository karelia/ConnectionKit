//
//  SFTPConnection.m
//  CocoaSFTP
//
//  Created by Brian Amerige on 11/4/07.
//  Copyright 2007 Extendmac, LLC.. All rights reserved.
//

#import "CKSFTPConnection.h"

#import "CKConnectionThreadManager.h"
#import "RunLoopForwarder.h"
#import "CKSSHPassphrase.h"
#import "CKTransferRecord.h"
#import "CKInternalTransferRecord.h"
#import "EMKeychainProxy.h"
#import "CKFTPConnection.h"
#import "CKConnectionProtocol.h"
#import "CKURLProtectionSpace.h"

#import "NSFileManager+Connection.h"
#import "NSString+Connection.h"

#include "sshversion.h"
#include "fdwrite.h"

@interface CKSFTPConnection (Private)
- (void)_writeSFTPCommandWithString:(NSString *)commandString;
- (void)_handleFinishedCommand:(CKConnectionCommand *)command serverErrorResponse:(NSString *)errorResponse;
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


@interface CKSFTPConnection (Authentication) <NSURLAuthenticationChallengeSender>
@end


#pragma mark -


@implementation CKSFTPConnection

NSString *SFTPErrorDomain = @"SFTPErrorDomain";
static NSString *lsform = nil;

#pragma mark -
#pragma mark Getting Started / Tearing Down
+ (void)load    // registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forName:[self name] URLScheme:@"sftp"];
    [[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forName:[self name] URLScheme:@"ssh"];
    [pool release];
}

+ (NSInteger)defaultPort { return 22; }

+ (NSString *)name
{
	return @"SFTP";
}

+ (NSArray *)URLSchemes
{
	return [NSArray arrayWithObjects:@"sftp", @"ssh", nil];
}

- (id)initWithURL:(NSURL *)URL
{
	if ((self = [super initWithURL:URL]))
	{
		theSFTPTServer = [[CKSFTPTServer alloc] init];
		connectToQueue = [[NSMutableArray array] retain];
		currentDirectory = [[NSMutableString string] retain];
		attemptedKeychainPublicKeyAuthentications = [[NSMutableArray array] retain];
	}
	return self;
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
    [_lastAuthenticationChallenge release];
    [_currentPassword release];
	
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
    
    
    // Can't connect till we have a password (due to using the SFTP command-line tool)
    NSURLProtectionSpace *protectionSpace = [[CKURLProtectionSpace alloc] initWithHost:[[self URL] host]
                                                                                  port:[self port]
                                                                              protocol:@"ssh"
                                                                                 realm:nil
                                                                  authenticationMethod:NSURLAuthenticationMethodDefault];
    
    _lastAuthenticationChallenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:protectionSpace
                                                                              proposedCredential:[self proposedCredentialForProtectionSpace:protectionSpace]
                                                                            previousFailureCount:0
                                                                                 failureResponse:nil
                                                                                           error:nil
                                                                                          sender:self];
    
    [protectionSpace release];
    
    [self didReceiveAuthenticationChallenge:_lastAuthenticationChallenge];
}

/*  Support method. Called once the delegate has provided a username to connect with
 */
- (void)connectWithUsername:(NSString *)username
{
    NSAssert(username, @"Can't create an SFTP connection without a username");
    
    NSMutableArray *parameters = [NSMutableArray array];
	BOOL enableCompression = NO; //We do support this on the backend, but we have no UI for it yet.
	if (enableCompression)
		[parameters addObject:@"-C"];
	
    if ([self port])
    {
		[parameters addObject:[NSString stringWithFormat:@"-o Port=%i", [self port]]];
    }
    
	if (_currentPassword && [_currentPassword length] > 0)
    {
		[parameters addObject:@"-o PubkeyAuthentication=no"];
    }
	else
	{
		NSString *publicKeyPath = [self propertyForKey:@"CKSFTPPublicKeyPath"];
		if (publicKeyPath && [publicKeyPath length] > 0)
			[parameters addObject:[NSString stringWithFormat:@"-o IdentityFile=%@", publicKeyPath]];
		else
		{
			[parameters addObject:[NSString stringWithFormat:@"-o IdentityFile=~/.ssh/%@", username]];
			[parameters addObject:@"-o IdentityFile=~/.ssh/id_rsa"];
			[parameters addObject:@"-o IdentityFile=~/.ssh/id_dsa"];
		}
	}
	[parameters addObject:[NSString stringWithFormat:@"%@@%@", username, [[self URL] host]]];
	
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
	
	[self _setupConnectTimeOut];
	[self setState:CKConnectionNotConnectedState];
	isConnecting = YES;
	[NSThread detachNewThreadSelector:@selector(_threadedSpawnSFTPTeletypeServer:) toTarget:self withObject:parameters];
}
- (void)_threadedSpawnSFTPTeletypeServer:(NSArray *)parameters
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	if (theSFTPTServer)
	{
		[theSFTPTServer release];
		theSFTPTServer = nil;
	}
	
	theSFTPTServer = [[CKSFTPTServer alloc] init];	
	[theSFTPTServer connectToServerWithArguments:parameters forWrapperConnection:self];
	
	[pool release];
}

#pragma mark -
#pragma mark Disconnecting
- (void)disconnect
{
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedDisconnect];
}

- (void)threadedDisconnect
{
	CKConnectionCommand *quit = [CKConnectionCommand command:@"quit"
											  awaitState:CKConnectionIdleState
											   sentState:CKConnectionSentDisconnectState
											   dependant:nil
												userInfo:nil];
	[self queueCommand:quit];
}

- (void)forceDisconnect
{
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedForceDisconnect];
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
	CKConnectionCommand *pwd = [CKConnectionCommand command:@"pwd" 
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionAwaitingCurrentDirectoryState
											  dependant:nil
											   userInfo:nil];
	CKConnectionCommand *cd = [CKConnectionCommand command:[NSString stringWithFormat:@"cd \"%@\"", newDir]
											awaitState:CKConnectionIdleState
											 sentState:CKConnectionChangingDirectoryState
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
	CKConnectionCommand *ls = [CKConnectionCommand command:lsform
											awaitState:CKConnectionIdleState
											 sentState:CKConnectionAwaitingDirectoryContentsState
											 dependant:nil
											  userInfo:nil];
	[self queueCommand:ls];
}

#pragma mark -
#pragma mark File Manipulation
- (void)createDirectory:(NSString *)newDirectoryPath
{
	NSAssert(newDirectoryPath && ![newDirectoryPath isEqualToString:@""], @"no directory specified");
	
	CKConnectionCommand *mkd = [CKConnectionCommand command:[NSString stringWithFormat:@"mkdir \"%@\"", newDirectoryPath]
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionCreateDirectoryState
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
	
	CKConnectionCommand *rename = [CKConnectionCommand command:[NSString stringWithFormat:@"rename \"%@\" \"%@\"", fromPath, toPath]
												awaitState:CKConnectionIdleState
												 sentState:CKConnectionAwaitingRenameState
												 dependant:nil
												  userInfo:nil];
	[self queueCommand:rename];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"no file/path specified");
	
	[self queuePermissionChange:path];
	CKConnectionCommand *chmod = [CKConnectionCommand command:[NSString stringWithFormat:@"chmod %lo \"%@\"", permissions, path]
											   awaitState:CKConnectionIdleState
												sentState:CKConnectionSettingPermissionsState
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

- (CKTransferRecord *)uploadFile:(NSString *)localPath  toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag  delegate:(id)delegate
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
		localPath = [temporaryParentPath stringByAppendingPathComponent:[NSString uuid]];
		[data writeToFile:localPath atomically:YES];
	}
	else
	{
		NSDictionary *attributes = [[NSFileManager defaultManager] fileAttributesAtPath:localPath traverseLink:YES];
		uploadSize = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
	}
	
	CKTransferRecord *record = [CKTransferRecord recordWithName:remotePath size:uploadSize];
	[record setUpload:YES];
	[record setObject:localPath forKey:CKQueueUploadLocalFileKey];
	[record setObject:remotePath forKey:CKQueueUploadRemoteFileKey];
	
	id internalTransferRecordDelegate = (delegate) ? delegate : record;
		
	CKInternalTransferRecord *internalRecord = [CKInternalTransferRecord recordWithLocal:localPath data:data offset:offset remote:remotePath delegate:internalTransferRecordDelegate userInfo:record];
	
	[self queueUpload:internalRecord];
	
	CKConnectionCommand *upload = [CKConnectionCommand command:[NSString stringWithFormat:@"put \"%@\" \"%@\"", localPath, remotePath]
												awaitState:CKConnectionIdleState
												 sentState:CKConnectionUploadingFileState
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
	[record setProperty:remotePath forKey:CKQueueDownloadRemoteFileKey];
	[record setProperty:localPath forKey:CKQueueDownloadDestinationFileKey];
	[record setProperty:[NSNumber numberWithInt:0] forKey:CKQueueDownloadTransferPercentReceived];
	
	CKInternalTransferRecord *internalTransferRecord = [CKInternalTransferRecord recordWithLocal:localPath
																							data:nil
																						  offset:0
																						  remote:remotePath
																						delegate:delegate ? delegate : record
																						userInfo:record];

	[self queueDownload:internalTransferRecord];
	
	CKConnectionCommand *download = [CKConnectionCommand command:[NSString stringWithFormat:@"get \"%@\" \"%@\"", remotePath, localPath]
												  awaitState:CKConnectionIdleState
												   sentState:CKConnectionDownloadingFileState
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
	
	CKConnectionCommand *delete = [CKConnectionCommand command:[NSString stringWithFormat:@"rm \"%@\"", remotePath]
												awaitState:CKConnectionIdleState
												 sentState:CKConnectionDeleteFileState
												 dependant:nil
												  userInfo:nil];
	[self queueCommand:delete];
}

- (void)deleteDirectory:(NSString *)remotePath
{
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
	[self queueDeletion:remotePath];
	
	CKConnectionCommand *delete = [CKConnectionCommand command:[NSString stringWithFormat:@"rmdir \"%@\"", remotePath]
												awaitState:CKConnectionIdleState
												 sentState:CKConnectionDeleteDirectoryState
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
	@synchronized (self)
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
	[self _handleFinishedCommand:[self lastCommand] serverErrorResponse:nil];
}

- (void)receivedErrorInServerResponse:(NSString *)serverResponse
{
	CKConnectionCommand *erroredCommand = [self lastCommand];
	[self _handleFinishedCommand:erroredCommand serverErrorResponse:serverResponse];
}

- (void)_handleFinishedCommand:(CKConnectionCommand *)command serverErrorResponse:(NSString *)errorResponse
{
	@synchronized (self)
	{
		CKConnectionState finishedState = GET_STATE;
			
		switch (finishedState)
		{
			case CKConnectionAwaitingCurrentDirectoryState:
				[self _finishedCommandInConnectionAwaitingCurrentDirectoryState:[command command] serverErrorResponse:errorResponse];
				break;
			case CKConnectionChangingDirectoryState:
				[self _finishedCommandInConnectionChangingDirectoryState:[command command] serverErrorResponse:errorResponse];
				break;
			case CKConnectionCreateDirectoryState:
				[self _finishedCommandInConnectionCreateDirectoryState:[command command] serverErrorResponse:errorResponse];
				break;
			case CKConnectionAwaitingRenameState:
				[self _finishedCommandInConnectionAwaitingRenameState:[command command] serverErrorResponse:errorResponse];
				break;
			case CKConnectionSettingPermissionsState:
				[self _finishedCommandInConnectionSettingPermissionState:[command command] serverErrorResponse:errorResponse];
				break;
			case CKConnectionDeleteFileState:
				[self _finishedCommandInConnectionDeleteFileState:[command command] serverErrorResponse:errorResponse];
				break;
			case CKConnectionDeleteDirectoryState:
				[self _finishedCommandInConnectionDeleteDirectoryState:[command command] serverErrorResponse:errorResponse];
				break;
			case CKConnectionUploadingFileState:
				[self _finishedCommandInConnectionUploadingFileState:[command command] serverErrorResponse:errorResponse];
				break;
			case CKConnectionDownloadingFileState:
				[self _finishedCommandInConnectionDownloadingFileState:[command command] serverErrorResponse:errorResponse];
				break;
			default:
				break;
		}
		[self setState:CKConnectionIdleState];
	}
}

#pragma mark -

- (void)_finishedCommandInConnectionAwaitingCurrentDirectoryState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse
{
	//We don't need to do anything beacuse SFTPTServer calls setCurrentDirectory on us.
}

- (void)_finishedCommandInConnectionChangingDirectoryState:(NSString *)commandString serverErrorResponse:(NSString *)errorResponse
{
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
	CKConnectionCommand *getCurrentDirectoryCommand = [CKConnectionCommand command:@"pwd"
																	awaitState:CKConnectionIdleState
																	 sentState:CKConnectionAwaitingCurrentDirectoryState
																	 dependant:nil
																	  userInfo:nil];
	[self pushCommandOnCommandQueue:getCurrentDirectoryCommand];
}

- (void)_connectTimeoutTimerFire:(NSTimer *)timer
{
	NSAssert2(timer == _connectTimeoutTimer,
			  @"-[%@ %@] called with unexpected timer object",
			  NSStringFromClass([self class]),
			  NSStringFromSelector(_cmd));
	
	
	[_connectTimeoutTimer release];
	_connectTimeoutTimer = nil;
	
	
	if (_flags.didConnect)
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Timed Out waiting for remote host.", @"time out");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  localizedDescription, NSLocalizedDescriptionKey, 
								  [[self URL] host], ConnectionHostKey, nil];
		
		NSError *error = [NSError errorWithDomain:SFTPErrorDomain code:StreamErrorTimedOut userInfo:userInfo];
		[_forwarder connection:self didConnectToHost:[[self URL] host] error:error];
	}
}

- (void)didSetRootDirectory
{
	rootDirectory = [[NSString alloc] initWithString:currentDirectory];
	
	isConnecting = NO;
	_flags.isConnected = YES;
	
	if (_flags.didConnect)
    {
		[_forwarder connection:self didConnectToHost:[[self URL] host] error:nil];
    }
}

- (void)setCurrentDirectory:(NSString *)current
{
	[currentDirectory setString:current];
}

- (void)didDisconnect
{
	if (theSFTPTServer)
	{
		[theSFTPTServer release];
		theSFTPTServer = nil;
	}
		
	[attemptedKeychainPublicKeyAuthentications removeAllObjects];			
	
	_flags.isConnected = NO;
	if (_flags.didDisconnect)
	{
		[_forwarder connection:self didDisconnectFromHost:[[self URL] host]];
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
	if (_currentPassword)
    {
        [self _writeSFTPCommandWithString:_currentPassword];
        [_currentPassword release]; _currentPassword = nil;
    }
    else
	{
		[self passwordErrorOccurred];
	}
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
		CKConnectionCommand *command = [CKConnectionCommand command:[item password]
														 awaitState:CKConnectionIdleState
														  sentState:CKConnectionSentPasswordState
														  dependant:nil
														   userInfo:nil];
		[self pushCommandOnHistoryQueue:command];
		_state = [command sentState];
		[self sendCommand:[command command]];
		return;
	}
	
	//We don't have it on keychain, so ask the delegate for it if we can, or ask ourselves if not.	
	NSString *passphrase = nil;
	if (_flags.passphrase)
	{
		passphrase = [_forwarder connection:self passphraseForHost:[[self URL] host] username:[[self URL] user] publicKeyPath:pubKeyPath];
	}
	else
	{
		//No delegate method implemented, and it's not already on the keychain. Ask ourselves.
		CKSSHPassphrase *passphraseFetcher = [[CKSSHPassphrase alloc] init];
		passphrase = [passphraseFetcher passphraseForPublicKey:pubKeyPath account:[[self URL] user]];
		[passphraseFetcher release];
	}
	
	if (passphrase)
	{
		CKConnectionCommand *command = [CKConnectionCommand command:passphrase
														 awaitState:CKConnectionIdleState
														  sentState:CKConnectionSentPasswordState
														  dependant:nil
														   userInfo:nil];
		[self pushCommandOnHistoryQueue:command];
		_state = [command sentState];
		[self sendCommand:[command command]];		
		return;
	}	
	
	[self passwordErrorOccurred];
}

- (void)passwordErrorOccurred
{
	// TODO: Use the new authentication APIs instead
	// [_forwarder connectionDidSendBadPassword:self];
}

@end


#pragma mark -
#pragma mark Authentication


@implementation CKSFTPConnection (Authentication)

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge == _lastAuthenticationChallenge)
    {
        [self disconnect];
    }
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    // SFTP absolutely requires authentication to continue, so fail with an error
    if (challenge == _lastAuthenticationChallenge)
    {
        if (_flags.error)
        {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:LocalizedStringInConnectionKitBundle(@"SFTP connections require some form of authentication.", @"SFTP authenticaton error")
                                                                 forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:SFTPErrorDomain code:CKConnectionErrorBadPassword userInfo:userInfo];
            [_forwarder connection:self didReceiveError:error];
        }
        
        [self disconnect];
    }
}

/*  Start login
 */
- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge == _lastAuthenticationChallenge)
    {
        // Store the password ready for after we've connected
        _currentPassword = [[credential password] copy];
        
        // Start login with the supplied username
        [self connectWithUsername:[credential user]];
    }
}

@end


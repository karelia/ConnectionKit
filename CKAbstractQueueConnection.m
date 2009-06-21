/*
 Copyright (c) 2005, Greg Hulands <ghulands@mac.com>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 */

#import "CKAbstractQueueConnection.h"
#import "NSObject+Connection.h"
#import "CKConnectionThreadManager.h"
#import "CKTransferRecord.h"
#import "NSString+Connection.h"
#import "NSFileManager+Connection.h"

NSString *CKQueueDomain = @"Queuing";

static NSString *CKRecursiveDownloadShouldOverwriteExistingFilesKey = @"CKRecursiveDownloadShouldOverwriteExistingFilesKey";

#define QUEUE_HISTORY_COMMAND_SIZE 5

@interface NSObject (HistoryQueueSupport)
- (void)didPushToHistoryQueue;
@end

@implementation CKAbstractQueueConnection

- (id)initWithRequest:(CKConnectionRequest *)request
{
	if (self = [super initWithRequest:request])
	{
		myQueueFlags.isDeleting = NO;
		
		_queueLock = [[NSRecursiveLock alloc] init];
		
		_commandHistory = [[NSMutableArray array] retain];
		_commandQueue = [[NSMutableArray array] retain];
		_downloadQueue = [[NSMutableArray array] retain];
		_uploadQueue = [[NSMutableArray array] retain];
		_fileDeletes = [[NSMutableArray array] retain];
		_fileRenames = [[NSMutableArray array] retain];
		_filePermissions = [[NSMutableArray array] retain];
		_fileCheckQueue = [[NSMutableArray array] retain];
		_filesNeedingOverwriteConfirmation = [[NSMutableDictionary dictionary] retain];
		
		//Recursive Deletion
		_recursiveDeletionsQueue = [[NSMutableArray alloc] init];
		_emptyDirectoriesToDelete = [[NSMutableArray alloc] init];
		_filesToDelete = [[NSMutableArray alloc] init];
		_recursiveDeletionLock = [[NSLock alloc] init];		
		
		_fileCheckLock = [[NSLock alloc] init];
		
		_recursiveS3RenamesQueue = [[NSMutableArray alloc] init];
		_recursivelyRenamedDirectoriesToDelete = [[NSMutableArray alloc] init];
		_recursiveS3RenameLock = [[NSLock alloc] init];
		
		_recursiveDownloadQueue = [[NSMutableArray alloc] init];
		_recursiveDownloadLock = [[NSLock alloc] init];		
	}
	return self;
}

- (void)dealloc
{
	[_queueLock release];
	[_commandHistory release];
	[_commandQueue release];
	[_downloadQueue release];
	[_uploadQueue release];
	[_fileDeletes release];
	[_fileRenames release];
	[_filePermissions release];
	[_fileCheckQueue release];
	[_filesNeedingOverwriteConfirmation release];
	
	//Recursive Deletion
	[_recursiveDeletionsQueue release];
	[_recursiveDeletionConnection setDelegate:nil];
	[_recursiveDeletionConnection forceDisconnect];
	[_recursiveDeletionConnection release];
	[_emptyDirectoriesToDelete release];
	[_filesToDelete release];
	[_recursiveDeletionLock release];	
	
	[_fileCheckingConnection setDelegate:nil];
	[_fileCheckingConnection forceDisconnect];
	[_fileCheckingConnection release];
	[_fileCheckLock release];
	[_fileCheckInFlight release];
	
	[_recursiveS3RenameLock release];
	[_recursiveS3RenamesQueue release];
	[_recursivelyRenamedDirectoriesToDelete release];
	
	[_recursiveDownloadConnection setDelegate:nil];
	[_recursiveDownloadConnection forceDisconnect];
	[_recursiveDownloadConnection release];
	[_recursiveDownloadQueue release];
	[_recursiveDownloadLock release];	
	
	[super dealloc];
}

#pragma mark -
#pragma mark Abstract Override

- (void)turnOnRecursiveUpload
{
	_isRecursiveUploading = YES;
}

- (void)turnOffRecursiveUpload
{
	_isRecursiveUploading = NO;
}

- (CKTransferRecord *)uploadLocalItem:(NSString *)localPath
					toRemoteDirectory:(NSString *)remoteDirectoryPath
					ignoreHiddenItems:(BOOL)ignoreHiddenItemsFlag
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(turnOnRecursiveUpload)
													  target:self
												   arguments:[NSArray array]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionIdleState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
	CKTransferRecord *rec = [super uploadLocalItem:localPath
								 toRemoteDirectory:remoteDirectoryPath
								 ignoreHiddenItems:ignoreHiddenItemsFlag];
	
	inv = [NSInvocation invocationWithSelector:@selector(turnOffRecursiveUpload)
										target:self
									 arguments:[NSArray array]];
	cmd = [CKConnectionCommand command:inv
						  awaitState:CKConnectionIdleState
						   sentState:CKConnectionIdleState
						   dependant:nil
							userInfo:nil];
	[self queueCommand:cmd];
	return rec;
}

- (void)threadedDisconnect
{
	[self emptyAllQueues];
	[_fileCheckingConnection disconnect];
	[_recursiveDeletionConnection disconnect];
	[_recursiveDownloadConnection disconnect];
	[_recursiveS3RenameConnection disconnect];
	[super threadedDisconnect];
}

- (void)threadedForceDisconnect
{
	[self emptyAllQueues];
	[_fileCheckingConnection forceDisconnect];
	[_recursiveDeletionConnection forceDisconnect];
	[_recursiveDownloadConnection forceDisconnect];
	[_recursiveS3RenameConnection forceDisconnect];
	[super threadedForceDisconnect];
}

- (void)cleanupConnection
{
	[_fileCheckingConnection cleanupConnection];
	[_recursiveDeletionConnection cleanupConnection];
	[_recursiveDownloadConnection cleanupConnection];
	[_recursiveS3RenameConnection cleanupConnection];
}

- (void)threadedCancelAll
{
	[_queueLock lock];
	[_commandQueue removeAllObjects];
	[_queueLock unlock];
	[super threadedCancelAll];
}

- (BOOL)isBusy
{
	BOOL isLocallyBusy = ([self numberOfCommands] + [self numberOfDeletions] + [self numberOfPermissionChanges] + [self numberOfTransfers]) > 0;
	BOOL peerConnectionsAreBusy = ([_recursiveDownloadConnection isBusy] || [_recursiveDeletionConnection isBusy] || [_fileCheckingConnection isBusy]);
	return (isLocallyBusy || peerConnectionsAreBusy);
}

#pragma mark -
#pragma mark Recursive Deletion Support Methods
- (void)temporarilyTakeOverRecursiveDeletionDelegate
{
	previousWorkingDirectory = [[NSString stringWithString:[self currentDirectory]] retain];
	previousDelegate = [self delegate];
	_recursiveDeletionConnection = self;
	[_recursiveDeletionConnection setDelegate:self];
}
- (void)restoreRecursiveDeletionDelegate
{
	if (!previousDelegate)
		return;
	[self changeToDirectory:previousWorkingDirectory];
	[_recursiveDeletionConnection setDelegate:previousDelegate];
	previousDelegate = nil;
	[previousWorkingDirectory release];
	previousWorkingDirectory = nil;
	_recursiveDeletionConnection = nil;
}
- (void)processRecursiveDeletionQueue
{
	if (!_recursiveDeletionConnection)
	{
		_recursiveDeletionConnection = [[[self class] alloc] initWithRequest:[self request]];
		[_recursiveDeletionConnection setName:@"recursive deletion"];
		[_recursiveDeletionConnection setDelegate:self];
		[_recursiveDeletionConnection connect];
	}
	
	[_recursiveDeletionLock lock];
	if (!myQueueFlags.isDeleting && [_recursiveDeletionsQueue count] > 0)
	{
		_numberOfDeletionListingsRemaining++;
		myQueueFlags.isDeleting = YES;
		NSString *directoryPath = [_recursiveDeletionsQueue objectAtIndex:0];
		[_emptyDirectoriesToDelete addObject:directoryPath];
		
		[_recursiveDeletionConnection changeToDirectory:directoryPath];
		[_recursiveDeletionConnection directoryContents];
	}
	[_recursiveDeletionLock unlock];
}

- (void)recursivelyDeleteDirectory:(NSString *)path
{
	//Don't perform recursive deletion on WebDAV or MobileMe.
	CKProtocol protocol = [[self class] protocol];
	if (protocol == CKWebDAVProtocol || protocol == CKMobileMeProtocol)
	{
		//WebDAV and MobileMe (as WebDAV derived) both support deletion of directories that have contents. No need for recursive deletion here!
		[self deleteDirectory:path];
		return;
	}
	[_recursiveDeletionLock lock];
	[_recursiveDeletionsQueue addObject:[path stringByStandardizingPath]];
	[_recursiveDeletionLock unlock];	
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processRecursiveDeletionQueue];
}

#pragma mark -
#pragma mark Recursive Downloading Support
- (void)recursivelySendTransferDidFinishMessage:(CKTransferRecord *)record
{
	[record transferDidFinish:record error:nil];
	NSEnumerator *contentsEnumerator = [[record children] objectEnumerator];
	CKTransferRecord *child;
	while ((child = [contentsEnumerator nextObject]))
	{
		[self recursivelySendTransferDidFinishMessage:child];
	}
}
- (void)temporarilyTakeOverRecursiveDownloadingDelegate
{
	previousWorkingDirectory = [[NSString stringWithString:[self currentDirectory]] retain];
	previousDelegate = [self delegate];
	_recursiveDownloadConnection = self;
	[_recursiveDownloadConnection setDelegate:self];
}
- (void)restoreRecursiveDownloadingDelegate
{
	if (!previousDelegate)
		return;
	[self changeToDirectory:previousWorkingDirectory];
	[_recursiveDownloadConnection setDelegate:previousDelegate];
	previousDelegate = nil;
	[previousWorkingDirectory release];
	previousWorkingDirectory = nil;
	_recursiveDownloadConnection = nil;
}
- (void)processRecursiveDownloadingQueue
{
	if (!_recursiveDownloadConnection)
	{
		_recursiveDownloadConnection = [[[self class] alloc] initWithRequest:[self request]];
		[_recursiveDownloadConnection setName:@"recursive download"];
		[_recursiveDownloadConnection setDelegate:self];
	}
	if (![_recursiveDownloadConnection isConnected])
	{
		[_recursiveDownloadConnection connect];
	}
	[_recursiveDownloadLock lock];
	if (!myQueueFlags.isDownloading && [_recursiveDownloadQueue count] > 0)
	{
		myQueueFlags.isDownloading = YES;
		CKTransferRecord *record = [_recursiveDownloadQueue objectAtIndex:0];
		_numberOfDownloadListingsRemaining++;
		[_recursiveDownloadConnection changeToDirectory:[record remotePath]];
		[_recursiveDownloadConnection directoryContents];
	}
	[_recursiveDownloadLock unlock];
}

- (CKTransferRecord *)recursivelyDownload:(NSString *)remotePath
									   to:(NSString *)localPath
								overwrite:(BOOL)flag
{
	CKTransferRecord *rec = [CKTransferRecord downloadRecordForConnection:self
														 sourceRemotePath:remotePath
													 destinationLocalPath:[localPath stringByAppendingPathComponent:[remotePath lastPathComponent]]
																	 size:0];
	
	[rec setProperty:[NSNumber numberWithBool:flag] forKey:CKRecursiveDownloadShouldOverwriteExistingFilesKey];

	[_recursiveDownloadLock lock];
	[_recursiveDownloadQueue addObject:rec];
	[_recursiveDownloadLock unlock];
	
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processRecursiveDownloadingQueue];
	
	return rec;
}

#pragma mark -
#pragma mark Recursive S3 Directory Rename Support Methods
- (void)processRecursiveS3RenamingQueue
{
	if (!_recursiveS3RenameConnection)
	{
		_recursiveS3RenameConnection = [[[self class] alloc] initWithRequest:[self request]];
		[_recursiveS3RenameConnection setName:@"Recursive S3 Renaming"];
		[_recursiveS3RenameConnection setDelegate:self];
	}
	[_recursiveS3RenameLock lock];
	if (!myQueueFlags.isRecursivelyRenamingForS3 && [_recursiveS3RenamesQueue count] > 0)
	{
		myQueueFlags.isRecursivelyRenamingForS3 = YES;
		NSDictionary *renameDictionary = [_recursiveS3RenamesQueue objectAtIndex:0];
		NSString *fromDirectoryPath = [renameDictionary objectForKey:@"FromDirectoryPath"];
		
		/*
		 Here's the plan:
		 (a) Create a new directory at the toDirectoryPath. Cache the old path for deletion later.
		 (b) Recursively list the contents of fromDirectoryPath.
		 (c) Create new directories at the appropriate paths for directories. Cache the old directory paths for deletion later.
		 (d) Rename the files.
		 (e) When we're done listing and done renaming, delete the old directory paths.
		 */
		
		_numberOfS3RenameListingsRemaining++;
		[_recursiveS3RenameConnection changeToDirectory:fromDirectoryPath];
		[_recursiveS3RenameConnection directoryContents];
	}
	[_recursiveS3RenameLock unlock];
}
- (void)recursivelyRenameS3Directory:(NSString *)fromDirectoryPath to:(NSString *)toDirectoryPath
{
	[_recursiveS3RenameLock lock];
	NSDictionary *renameDictionary = [NSDictionary dictionaryWithObjectsAndKeys:fromDirectoryPath, @"FromDirectoryPath", toDirectoryPath, @"ToDirectoryPath", nil];
	[_recursiveS3RenamesQueue addObject:renameDictionary];
	[_recursiveS3RenameLock unlock];
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processRecursiveS3RenamingQueue];
}

#pragma mark -
#pragma mark File Checking

- (void)processFileCheckingQueue
{
	if (!_fileCheckingConnection) 
	{
		_fileCheckingConnection = [[[self class] alloc] initWithRequest:[self request]];
        [_fileCheckingConnection setDelegate:self];
		[_fileCheckingConnection setName:@"File Checking Connection"];
		[_fileCheckingConnection connect];
	}
	[_fileCheckLock lock];
	if (!_fileCheckInFlight && [self numberOfFileChecks] > 0)
	{
		_fileCheckInFlight = [[self currentFileCheck] copy];
		NSString *dir = [_fileCheckInFlight stringByDeletingLastPathComponent];
		if (!dir)
			NSLog(@"%@: %@", NSStringFromSelector(_cmd), _fileCheckInFlight);
		[_fileCheckingConnection changeToDirectory:dir];
		[_fileCheckingConnection directoryContents];
	}
	[_fileCheckLock unlock];
}

- (void)checkExistenceOfPath:(NSString *)path
{
	NSString *dir = [path stringByDeletingLastPathComponent];
	
	//if we pass in a relative path (such as xxx.tif), then the last path is @"", with a length of 0, so we need to add the current directory
	//according to docs, passing "/" to stringByDeletingLastPathComponent will return "/", conserving a 1 size
	//
	if (!dir || [dir length] == 0)
	{
		path = [[self currentDirectory] stringByAppendingPathComponent:path];
	}
	[_fileCheckLock lock];
	[self queueFileCheck:path];
	[_fileCheckLock unlock];
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processFileCheckingQueue];
}

#pragma mark -
#pragma mark Peer Connection Delegate Methods
- (void)connection:(id <CKConnection>)conn didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	//Forward to our delegate 
	[[self client] connectionDidReceiveAuthenticationChallenge:challenge];
}

- (void)connection:(id <CKConnection>)conn appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript
{
	//Forward to our delegate.
	[[self client] appendString:string toTranscript:transcript];
}

- (void)connection:(id <CKConnection>)conn didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	//We failed to do whatever recursive operation we were asked to do. Appropriately error!
	if (conn == _recursiveDeletionConnection)
	{
		[_recursiveDeletionLock lock];
		NSString *directoryPath = [_recursiveDeletionsQueue objectAtIndex:0];
		if (_numberOfDeletionListingsRemaining > 0)
			_numberOfDeletionListingsRemaining--;
		if (_numberOfDirDeletionsRemaining > 0)
			_numberOfDirDeletionsRemaining--;
		[_recursiveDeletionLock unlock];
		
		NSString *localizedDescription = [NSString stringWithFormat:@"%@: %@", LocalizedStringInConnectionKitBundle(@"Failed to delete file", @"couldn't delete the file"), directoryPath];
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  localizedDescription, NSLocalizedDescriptionKey, 
								  directoryPath, NSFilePathErrorKey, nil];
		NSError *error = [NSError errorWithDomain:CKStreamDomain 
											 code:0 //Code has no meaning in this context
										 userInfo:userInfo];
		[[self client] connectionDidDeleteDirectory:directoryPath error:error];
	}
	else if (conn == _recursiveDownloadConnection)
	{
		[_recursiveDownloadLock lock];
		NSDictionary *record = [_recursiveDownloadQueue objectAtIndex:0];
		if (_numberOfDownloadListingsRemaining > 0)
			_numberOfDownloadListingsRemaining--;
		[_recursiveDownloadLock unlock];
		
		NSString *directoryPath = [record objectForKey:@"remote"];
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to download file.", @"Failed to download file.");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  localizedDescription, NSLocalizedDescriptionKey, 
								  directoryPath, NSFilePathErrorKey, nil];
		NSError *error = [NSError errorWithDomain:CKStreamDomain 
											 code:0 //code doesn't mean anything in this context.
										 userInfo:userInfo];
		[[self client] downloadDidFinish:directoryPath error:error];
	}
	else if (conn == _recursiveS3RenameConnection)
	{
		[_recursiveS3RenameLock lock];
		
		NSDictionary *renameDictionary = [_recursiveS3RenamesQueue objectAtIndex:0];
		
		if (_numberOfS3RenameListingsRemaining > 0)
			_numberOfS3RenameListingsRemaining--;
		if (_numberOfS3RenamesRemaining > 0)
			_numberOfS3RenamesRemaining--;
		
		[_recursiveS3RenameLock unlock];
		
		NSString *fromDirectoryPath = [renameDictionary objectForKey:@"FromDirectoryPath"];
		NSString *toDirectoryPath = [renameDictionary objectForKey:@"ToDirectoryPath"];
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to rename file.", @"Failed to rename file.");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedDescription, NSLocalizedDescriptionKey, fromDirectoryPath, @"fromPath", toDirectoryPath, @"toPath", nil];
		NSError *error = [NSError errorWithDomain:CKStreamDomain 
											 code:0 //Code has no meaning in this context.
										 userInfo:userInfo];
		[[self client] connectionDidRename:fromDirectoryPath to:toDirectoryPath error:error];
	}
	else if (conn == _fileCheckingConnection)
	{
		[_fileCheckLock lock];
		
		NSString *path = [NSString stringWithString:[self currentFileCheck]];
		
		if ([self numberOfFileChecks] > 0)
			[self dequeueFileCheck];
		
		[_fileCheckLock unlock];
		
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to check existence of file", @"Failed to check existence of file");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedDescription, NSLocalizedDescriptionKey, path, NSFilePathErrorKey, nil];
		NSError *error = [NSError errorWithDomain:CKStreamDomain 
											 code:0 //Code has no meaning in this context.
										 userInfo:userInfo];
		
		[[self client] connectionDidCheckExistenceOfPath:path pathExists:NO error:error];
	}
}


- (NSString *)connection:(id <CKConnection>)con
	   passphraseForHost:(NSString *)host 
				username:(NSString *)username
		   publicKeyPath:(NSString *)pubKeyPath
{
	//TODO:
	//If a peer connection is asking for a passphrase, that means we, as the model connection, were asked for it as well. Can't we just access that result and use it?
	return [[self client] passphraseForHost:host username:username publicKeyPath:pubKeyPath];
}

- (void)connection:(id <CKConnection>)con didReceiveError:(NSError *)error
{
	if (con == _recursiveDeletionConnection &&
		[[error localizedDescription] containsSubstring:@"failed to delete file"] &&
		[[error localizedFailureReason] containsSubstring:@"permission denied"])
	{
		//Permission Error while deleting a file in recursive deletion. We handle it as if it successfully deleted the file, but don't give any delegate notifications about this specific file.
		[_recursiveDeletionLock lock];
		if ([_filesToDelete count] == 0 && _numberOfDeletionListingsRemaining == 0)
		{
			_numberOfDirDeletionsRemaining += [_emptyDirectoriesToDelete count];
			NSEnumerator *e = [_emptyDirectoriesToDelete reverseObjectEnumerator];
			NSString *cur;
			while (cur = [e nextObject])
			{
				[_recursiveDeletionConnection deleteDirectory:cur];
			}
			[_emptyDirectoriesToDelete removeAllObjects];
		}
		[_recursiveDeletionLock unlock];		
		return;
	}
	else if (con == _recursiveDeletionConnection &&
			 [[error localizedDescription] containsSubstring:@"failed to delete directory"])
	{
		//Permission Error while deleting a directory in recursive deletion. We handle it as if it successfully deleted the directory. If the error is for the actual ancestor directory, we send out an error.
		[_recursiveDeletionLock lock];
		_numberOfDirDeletionsRemaining--;
		if (_numberOfDirDeletionsRemaining == 0 && [_recursiveDeletionsQueue count] > 0)
		{
			[_recursiveDeletionsQueue removeObjectAtIndex:0];
			
            [[self client] connectionDidReceiveError:error];
			
			if ([_recursiveDeletionsQueue count] == 0)
			{
				myQueueFlags.isDeleting = NO;				
				[_recursiveDeletionConnection disconnect];
			}
			else
			{
				NSString *directoryPath = [_recursiveDeletionsQueue objectAtIndex:0];
				[_emptyDirectoriesToDelete addObject:directoryPath];
				_numberOfDeletionListingsRemaining++;
				[_recursiveDeletionConnection changeToDirectory:directoryPath];
				[_recursiveDeletionConnection directoryContents];
			}
		}
		[_recursiveDeletionLock unlock];	
		return;
	}
	//If any of these connections are nil, they were released by the didDisconnect method. We need them, however.
	//In testing, this is because the host didn't support the number of additional concurrent connections we requested to open.
	//To remedy this, we point the nil connection to ourself connection, who will perform that work as well.
	
	NSLog(@"%@", [error description]);
	if ([_recursiveDeletionsQueue count] > 0 && con == _recursiveDeletionConnection)
	{
		if (previousDelegate)
			return;
		
		[self temporarilyTakeOverRecursiveDeletionDelegate];
		
		[_recursiveDeletionLock lock];
		NSString *pathToDelete = [_recursiveDeletionsQueue objectAtIndex:0];
		[_recursiveDeletionLock unlock];
		
		[_recursiveDeletionConnection changeToDirectory:pathToDelete];
		[_recursiveDeletionConnection directoryContents];
	}
	else if ([_recursiveDownloadQueue count] > 0 && con == _recursiveDownloadConnection)
	{
		if (previousDelegate)
			return;
		
		[self temporarilyTakeOverRecursiveDownloadingDelegate];
		
		[_recursiveDownloadLock lock];
		NSString *pathToDownload = [[_recursiveDownloadQueue objectAtIndex:0] objectForKey:@"remote"];
		[_recursiveDownloadLock unlock];
		
		[_recursiveDownloadConnection changeToDirectory:pathToDownload];
		[_recursiveDownloadConnection directoryContents];
	}
}

- (void)connection:(id <CKConnection>)con didChangeToDirectory:(NSString *)dirPath error:(NSError *)error;
{
	if (!error)
		return;
	//We had some difficulty changing to a directory. We're obviously not going to list that directory, we lets just remove it from whatever queue we need to
	if (con == _fileCheckingConnection)
	{
		[_fileCheckLock lock];
		
		NSEnumerator *e = [[NSArray arrayWithArray:_fileCheckQueue] nextObject];
		NSString *filePathToCheck;
		while (filePathToCheck = [e nextObject])
		{
			if (![[filePathToCheck stringByDeletingLastPathComponent] isEqualToString:dirPath])
				continue;
			
            [[self client] connectionDidCheckExistenceOfPath:filePathToCheck pathExists:NO error:error];
			
			[_fileCheckQueue removeObject:filePathToCheck];
			if ([filePathToCheck isEqualToString:_fileCheckInFlight])
			{
				[_fileCheckInFlight autorelease];
				_fileCheckInFlight = nil;
				[self performSelector:@selector(processFileCheckingQueue) withObject:nil afterDelay:0];
			}
		}
		[_fileCheckLock unlock];
	}
	else if (con == _recursiveDeletionConnection)
	{
		[_recursiveDeletionLock lock];
		_numberOfDeletionListingsRemaining--;
		[_recursiveDeletionLock unlock];
	}
	else if (con == _recursiveDownloadConnection)
	{
		
	}
	else if (con == _recursiveS3RenameConnection)
	{
	}
}
- (void)connection:(id <CKConnection>)con didDisconnectFromHost:(NSString *)host
{
	if (con == _fileCheckingConnection)
	{
		[_fileCheckingConnection release];
		_fileCheckingConnection = nil;
	}
	else if (con == _recursiveDeletionConnection)
	{
		[_recursiveDeletionConnection release];
		_recursiveDeletionConnection = nil;
	}
	else if (con == _recursiveDownloadConnection)
	{
		[_recursiveDownloadConnection release];
		_recursiveDownloadConnection = nil;
	}
	else if (con == _recursiveS3RenameConnection)
	{
		[_recursiveS3RenameConnection release];
		_recursiveS3RenameConnection = nil;
	}
}

- (void)connection:(id <CKConnection>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath error:(NSError *)error
{
	if (con == _fileCheckingConnection)
	{
        NSArray *currentDirectoryContentsFilenames = [contents valueForKey:@"filename"];
        NSMutableArray *fileChecksToRemoveFromQueue = [NSMutableArray array];
        [_fileCheckLock lock];
        NSEnumerator *pathsToCheckForEnumerator = [_fileCheckQueue objectEnumerator];
        NSString *currentPathToCheck;
        while ((currentPathToCheck = [pathsToCheckForEnumerator nextObject]))
        {
            if (![[currentPathToCheck stringByDeletingLastPathComponent] isEqualToString:dirPath])
            {
                continue;
            }
            [fileChecksToRemoveFromQueue addObject:currentPathToCheck];
            BOOL currentDirectoryContainsFile = [currentDirectoryContentsFilenames containsObject:[currentPathToCheck lastPathComponent]];
            [[self client] connectionDidCheckExistenceOfPath:currentPathToCheck pathExists:currentDirectoryContainsFile error:nil];
        }
        [_fileCheckQueue removeObjectsInArray:fileChecksToRemoveFromQueue];
        [_fileCheckLock unlock];
		
		[_fileCheckInFlight autorelease];
		_fileCheckInFlight = nil;
		[self performSelector:@selector(processFileCheckingQueue) withObject:nil afterDelay:0.0];
	}
	else if (con == _recursiveDeletionConnection)
	{
		[_recursiveDeletionLock lock];
		_numberOfDeletionListingsRemaining--;
		
		if (![dirPath hasPrefix:[_recursiveDeletionsQueue objectAtIndex:0]])
		{
			//If we get here, we received a listing for something that is *not* a subdirectory of the root path we were asked to delete. Log it, and return.
			NSLog(@"Received Listing For Inappropriate Path when Recursively Deleting.");
			[_recursiveDeletionLock unlock];
			return;
		}
		
		NSEnumerator *e = [contents objectEnumerator];
		CKDirectoryListingItem *cur;
		
		[[self client] connectionDidDiscoverFilesToDelete:contents inAncestorDirectory:[_recursiveDeletionsQueue objectAtIndex:0]];
		
        [[self client] connectionDidDiscoverFilesToDelete:contents inDirectory:dirPath];
		
		while ((cur = [e nextObject]))
		{
			if ([cur isDirectory])
			{
				_numberOfDeletionListingsRemaining++;
				[_recursiveDeletionConnection changeToDirectory:[dirPath stringByAppendingPathComponent:[cur filename]]];
				[_recursiveDeletionConnection directoryContents];
			}
			else
			{
				[_filesToDelete addObject:[dirPath stringByAppendingPathComponent:[cur filename]]];
			}
		}
		
		if (![_recursiveDeletionsQueue containsObject:[dirPath stringByStandardizingPath]])
		{
			[_emptyDirectoriesToDelete addObject:[dirPath stringByStandardizingPath]];
		}
		if (_numberOfDeletionListingsRemaining == 0)
		{
			if ([_filesToDelete count] > 0)
			{
				//We finished listing what we need to delete. Let's delete it now.
				NSEnumerator *e = [_filesToDelete objectEnumerator];
				NSString *pathToDelete;
				while (pathToDelete = [e nextObject])
				{
					[_recursiveDeletionConnection deleteFile:pathToDelete];
				}
			}
			else
			{
				//We've finished listing directories and deleting files. Let's delete directories.
				_numberOfDirDeletionsRemaining += [_emptyDirectoriesToDelete count];
				NSEnumerator *e = [_emptyDirectoriesToDelete reverseObjectEnumerator];
				NSString *cur;
				while (cur = [e nextObject])
				{
					[_recursiveDeletionConnection deleteDirectory:cur];
				}
				[_emptyDirectoriesToDelete removeAllObjects];				
			}
		}
		[_recursiveDeletionLock unlock];
	}
	else if (con == _recursiveDownloadConnection) 
	{
		[_recursiveDownloadLock lock];
		if ([_recursiveDownloadQueue count] <= 0)
		{
			[_recursiveDownloadLock unlock];
			return;
		}
		
		_numberOfDownloadListingsRemaining--;		
		CKTransferRecord *rootTransferRecord = [_recursiveDownloadQueue objectAtIndex:0];
		[_recursiveDownloadLock unlock];
		
		NSString *remotePath = [rootTransferRecord remotePath];
		NSString *localPath = [rootTransferRecord localPath];
		BOOL shouldOverwriteExistingFiles = [[rootTransferRecord propertyForKey:CKRecursiveDownloadShouldOverwriteExistingFilesKey] boolValue];
		
		//Setup the local relative directory
		NSString *relativeRemotePath = [dirPath substringFromIndex:[remotePath length]]; 
		NSString *thisListingLocalPath = [localPath stringByAppendingPathComponent:relativeRemotePath];
		[[NSFileManager defaultManager] recursivelyCreateDirectory:thisListingLocalPath attributes:nil];
		
		CKTransferRecord *thisDirectoryRecord = [CKTransferRecord downloadRecordForConnection:self
																			 sourceRemotePath:dirPath
																		 destinationLocalPath:thisListingLocalPath
																						 size:0];
		CKTransferRecord *thisDirectoryParentRecord = [rootTransferRecord childTransferRecordForRemotePath:[dirPath stringByDeletingLastPathComponent]];
		[thisDirectoryParentRecord addChild:thisDirectoryRecord];
		
		NSEnumerator *directoryContentsEnumerator = [contents objectEnumerator];
		CKDirectoryListingItem *listingItem;
		
		while ((listingItem = [directoryContentsEnumerator nextObject]))
		{
			if ([listingItem isDirectory])
			{
				[_recursiveDownloadLock lock];
				_numberOfDownloadListingsRemaining++;
				[_recursiveDownloadLock unlock];
				[_recursiveDownloadConnection changeToDirectory:[dirPath stringByAppendingPathComponent:[listingItem filename]]];
				[_recursiveDownloadConnection directoryContents];
			}
			else if ([listingItem isRegularFile])
			{
				CKTransferRecord *down = [self downloadFile:[dirPath stringByAppendingPathComponent:[listingItem filename]] 
												toDirectory:thisListingLocalPath
												  overwrite:shouldOverwriteExistingFiles
												   delegate:nil];
				[down setSize:[[listingItem size] unsignedLongLongValue]];
				[thisDirectoryRecord addChild:down];
			}
		}
		if (_numberOfDownloadListingsRemaining == 0)
		{
            [_recursiveDownloadLock lock];
			myQueueFlags.isDownloading = NO;
			
			//If we were downloading an empty folder, make sure to mark it as complete.
			CKTransferRecord *rootTransferRecord = [_recursiveDownloadQueue objectAtIndex:0];
			if ([[rootTransferRecord children] count] == 0)
				[rootTransferRecord transferDidFinish:rootTransferRecord error:nil];
			
			[_recursiveDownloadQueue removeObjectAtIndex:0];
			[_recursiveDownloadLock unlock];
			
			if ([_recursiveDownloadQueue count] > 0)
				[self performSelector:@selector(processRecursiveDownloadingQueue) withObject:nil afterDelay:0.0];
			else
				[self restoreRecursiveDownloadingDelegate];
		}
	}
	else if (con == _recursiveS3RenameConnection)
	{
		[_recursiveS3RenameLock lock];
		NSString *fromRootPath = [[_recursiveS3RenamesQueue objectAtIndex:0] objectForKey:@"FromDirectoryPath"];
		NSString *toRootPath = [[_recursiveS3RenamesQueue objectAtIndex:0] objectForKey:@"ToDirectoryPath"];
		NSString *toDirPath = [toRootPath stringByAppendingPathComponent:[dirPath substringFromIndex:[fromRootPath length]]];
		[con createDirectory:toDirPath];
		
		NSEnumerator *contentsEnumerator = [contents objectEnumerator];
		CKDirectoryListingItem *item;
		while ((item = [contentsEnumerator nextObject]))
		{
			NSString *itemRemotePath = [dirPath stringByAppendingPathComponent:[item filename]];
			if ([item isDirectory])
			{
				_numberOfS3RenameListingsRemaining++;
				[con changeToDirectory:itemRemotePath];
				[con directoryContents];
			}
			else
			{
				_numberOfS3RenamesRemaining++;
				NSString *newItemRemotePath = [toDirPath stringByAppendingPathComponent:[itemRemotePath lastPathComponent]];
				[con rename:itemRemotePath to:newItemRemotePath];
			}
		}
		
		_numberOfS3RenameListingsRemaining--;
		[_recursivelyRenamedDirectoriesToDelete addObject:dirPath];
		
		if (_numberOfS3RenamesRemaining == 0 && _numberOfS3RenameListingsRemaining == 0)
		{
			NSEnumerator *renamedDirectoriesToDelete = [_recursivelyRenamedDirectoriesToDelete reverseObjectEnumerator];
			NSString *path;
			while ((path = [renamedDirectoriesToDelete nextObject]))
			{
				_numberOfS3RenameDirectoryDeletionsRemaining++;
				[con deleteDirectory:path];
			}
			[_recursivelyRenamedDirectoriesToDelete removeAllObjects];
		}		
		
		[_recursiveS3RenameLock unlock];
	}
}

- (void)connection:(CKAbstractConnection *)conn didRename:(NSString *)fromPath to:(NSString *)toPath error:(NSError *)error
{
	if (conn == _recursiveS3RenameConnection)
	{
		[_recursiveS3RenameLock lock];
		_numberOfS3RenamesRemaining--;
		if (_numberOfS3RenamesRemaining == 0 && _numberOfS3RenameListingsRemaining == 0)
		{
			NSEnumerator *renamedDirectoriesToDelete = [_recursivelyRenamedDirectoriesToDelete reverseObjectEnumerator];
			NSString *path;
			while ((path = [renamedDirectoriesToDelete nextObject]))
			{
				_numberOfS3RenameDirectoryDeletionsRemaining++;
				[conn deleteDirectory:path];
			}
			[_recursivelyRenamedDirectoriesToDelete removeAllObjects];
		}
		[_recursiveS3RenameLock unlock];
	}
}

- (void)connection:(id <CKConnection>)con didDeleteFile:(NSString *)path error:(NSError *)error
{
	if (con == _recursiveDeletionConnection)
	{
		[[self client] connectionDidDeleteFile:[path stringByStandardizingPath] inAncestorDirectory:[_recursiveDeletionsQueue objectAtIndex:0] error:error];
		
		
		[_recursiveDeletionLock lock];
		[_filesToDelete removeObject:path];
		if ([_filesToDelete count] == 0 && _numberOfDeletionListingsRemaining == 0)
		{
			_numberOfDirDeletionsRemaining += [_emptyDirectoriesToDelete count];
			NSEnumerator *e = [_emptyDirectoriesToDelete reverseObjectEnumerator];
			NSString *cur;
			while (cur = [e nextObject])
			{
				[_recursiveDeletionConnection deleteDirectory:cur];
			}
			[_emptyDirectoriesToDelete removeAllObjects];
		}
		[_recursiveDeletionLock unlock];
	}
}

- (void)connection:(id <CKConnection>)con didDeleteDirectory:(NSString *)dirPath error:(NSError *)error
{
	if (con == _recursiveDeletionConnection)
	{
		[_recursiveDeletionLock lock];
		_numberOfDirDeletionsRemaining--;
		if (_numberOfDirDeletionsRemaining == 0 && [_recursiveDeletionsQueue count] > 0)
		{
			[_recursiveDeletionsQueue removeObjectAtIndex:0];
            if (previousDelegate && _recursiveDeletionConnection == self && [_recursiveDeletionConnection delegate] == self)
            {
                //In connection:didReceiveError, we were notified that the deletion connection we attempted to open up failed to open. To remedy this, we used OURSELF as the deletion connection, temporarily setting our delegate to OURSELF so we'd receive the calls we needed to perform the deletion. 
                //Now that we're done, let's restore our delegate.
                [self restoreRecursiveDeletionDelegate];
                [[self client] connectionDidDeleteDirectory:dirPath error:error];
                if ([_recursiveDeletionsQueue count] > 0)
                    [self temporarilyTakeOverRecursiveDeletionDelegate];
            }
            else
            {
                [[self client] connectionDidDeleteDirectory:dirPath error:error];
            }
			
			if ([_recursiveDeletionsQueue count] == 0)
			{
				myQueueFlags.isDeleting = NO;				
				[_recursiveDeletionConnection disconnect];
			}
			else
			{
				NSString *directoryPath = [_recursiveDeletionsQueue objectAtIndex:0];
				[_emptyDirectoriesToDelete addObject:directoryPath];
				_numberOfDeletionListingsRemaining++;
				[_recursiveDeletionConnection changeToDirectory:directoryPath];
				[_recursiveDeletionConnection directoryContents];
			}
		}
		else
		{
            NSString *ancestorDirectory = [_recursiveDeletionsQueue objectAtIndex:0];
            if (previousDelegate && _recursiveDeletionConnection == self && [_recursiveDeletionConnection delegate] == self)
            {
                [self restoreRecursiveDeletionDelegate];
                [[self client] connectionDidDeleteDirectory:[dirPath stringByStandardizingPath] inAncestorDirectory:ancestorDirectory error:error];
                [self temporarilyTakeOverRecursiveDeletionDelegate];
            }
            else
            {
                [[self client] connectionDidDeleteDirectory:[dirPath stringByStandardizingPath] inAncestorDirectory:ancestorDirectory error:error];
            }
		}
		[_recursiveDeletionLock unlock];
	}
	else if (con == _recursiveS3RenameConnection)
	{
		[_recursiveS3RenameLock lock];
		
		_numberOfS3RenameDirectoryDeletionsRemaining--;
		if (_numberOfS3RenameDirectoryDeletionsRemaining == 0)
		{
			_numberOfS3RenameListingsRemaining = 0;
			_numberOfS3RenamesRemaining = 0;
			_numberOfS3RenameDirectoryDeletionsRemaining = 0;
			myQueueFlags.isRecursivelyRenamingForS3 = NO;
			NSDictionary *renameDictionary = [_recursiveS3RenamesQueue objectAtIndex:0];
			NSString *fromDirectoryPath = [NSString stringWithString:[renameDictionary objectForKey:@"FromDirectoryPath"]];
			NSString *toDirectoryPath = [NSString stringWithString:[renameDictionary objectForKey:@"ToDirectoryPath"]];
			[_recursiveS3RenamesQueue removeObjectAtIndex:0];
			
			if ([_recursiveS3RenamesQueue count] > 0)
			{
				[self processRecursiveS3RenamingQueue];
			}
			else
			{
				[con disconnect];
				[[self client] connectionDidRename:fromDirectoryPath to:toDirectoryPath error:nil];
			}
		}
		
		[_recursiveS3RenameLock unlock];
	}
}

#pragma mark -
#pragma mark Command History

- (id)lastCommand
{
	[_queueLock lock];
	id last = [_commandHistory count] > 0 ? [_commandHistory objectAtIndex:0] : nil;
	[_queueLock unlock];
	return last;
}

- (NSArray *)commandHistory
{
	[_queueLock lock];
	NSArray *copy = [NSArray arrayWithArray:_commandHistory];
	[_queueLock unlock];
	return copy;
}

- (void)pushCommandOnHistoryQueue:(id)command
{
	KTLog(CKQueueDomain, KTLogDebug, @"Pushing Command on History Queue: %@", [command shortDescription]);
	[_queueLock lock];
	[_commandHistory insertObject:command atIndex:0];
	
	// This is a framework internal "hack" to allow the webdav file upload request to release the data of a file
	if ([command isKindOfClass:[CKConnectionCommand class]])
	{
		if ([[command command] respondsToSelector:@selector(didPushToHistoryQueue)])
		{
			[[command command] didPushToHistoryQueue];
		}
	}
	if (QUEUE_HISTORY_COMMAND_SIZE != 0 && [_commandHistory count] > QUEUE_HISTORY_COMMAND_SIZE)
	{
		[_commandHistory removeLastObject];
	}
	[_queueLock unlock];
}

- (void)pushCommandOnCommandQueue:(id)command
{
	KTLog(CKQueueDomain, KTLogDebug, @"Pushing Command on Command Queue: %@", [command shortDescription]);
	[_queueLock lock];
	[_commandQueue insertObject:command atIndex:0];
	[_queueLock unlock];
}

#pragma mark -
#pragma mark Queue Support

- (void)setState:(CKConnectionState)aState		// Safe "setter" -- do NOT just change raw variable.  Called by EITHER thread.
{
	KTLog(CKStateMachineDomain, KTLogDebug, @"Changing State from %@ to %@", [self stateName:_state], [self stateName:aState]);
	
    [super setState:aState];
	
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] checkQueue];
}

- (void)sendCommand:(id)command
{
	; //subclass to do work
}

- (BOOL)isCheckingQueue
{
	return myQueueFlags.isCheckingQueue;
}

- (void)checkQueue
{
	KTLog(CKStateMachineDomain, KTLogDebug, @"Checking Queue");
	[_queueLock lock];
	myQueueFlags.isCheckingQueue = YES;
	[_queueLock unlock];
	
	BOOL checkAgain = NO;
	do {
		BOOL nextTry = 0 != [self numberOfCommands];
		if (!nextTry)
		{
			KTLog(CKStateMachineDomain, KTLogDebug, @"Queue is Empty");
		}
		while (nextTry)
		{
			CKConnectionCommand *command = [[self currentCommand] retain];
			if (command && GET_STATE == [command awaitState])
			{
				KTLog(CKStateMachineDomain, KTLogDebug, @"Dispatching Command: %@", command);
				_state = [command sentState];	// don't use setter; we don't want to recurse
				[self pushCommandOnHistoryQueue:command];
				[self dequeueCommand];
				
				[self sendCommand:[command command]];
				
				// go to next one, there's something else to do
				[_queueLock lock];
				nextTry = [_commandQueue count] > 0; 
				if (!nextTry)
				{
					myQueueFlags.isCheckingQueue = NO;
				}
				[_queueLock unlock];
			}
			else
			{
				KTLog(CKStateMachineDomain, KTLogDebug, @"State %@ not ready for command at top of queue: %@, needs %@", [self stateName:GET_STATE], command, [self stateName:[command awaitState]]);
				nextTry = NO;		// don't try.  
			}
			[command release];
		}
		
		
		// It is possible that queueCommand: can be called while checkQueue is called
		// and queueCommand: will not call checkQueue because the value of myQueueFlags.isCheckingQueue
		// is YES. checkQueue, however, might have already checked the numberOfCommands and assigned
		// NO to nextTry BEFORE queueCommand: gets called (and queueCommand: gets called before
		// checkQueue reaches then end and sets isCheckingQueue to NO) which will lead to checkQueue
		// never being called for that newly added command. 
		// This simple check counting mechanism allows queueCommand to signal to checkQueue that a new
		// command has been added and the queue should be checked again. -- Seth Willits
		[_queueLock lock];
		checkAgain = (_checkQueueCount > 0);
		if (checkAgain)
		{
			_checkQueueCount--;
		}
		[_queueLock unlock];
		
	} while (checkAgain);
	
	
	[_queueLock lock];
	myQueueFlags.isCheckingQueue = NO;
	[_queueLock unlock];
	KTLog(CKStateMachineDomain, KTLogDebug, @"Done Checking Queue");
}	

- (NSString *)queueDescription
{
	NSMutableString *string = [NSMutableString string];
	NSEnumerator *theEnum = [_commandQueue objectEnumerator];
	id object;
	[string appendFormat:@"Current State: %@\n", [self stateName:GET_STATE]];
	[string appendString:@"(\n"];
	
	while (nil != (object = [theEnum nextObject]) )
	{
		[string appendFormat:@"\t\"%@\" ? %@ > %@,\n", [object command], [self stateName:[object awaitState]], [self stateName:[object sentState]]];
	}
	[string deleteCharactersInRange:NSMakeRange([string length] - 2, 2)];
	[string appendString:@"\n)"];
	return string;
}
- (NSMutableArray *)uploadQueue
{
	return _uploadQueue;
}
- (NSMutableArray *)downloadQueue
{
	return _downloadQueue;
}
- (NSMutableArray *)commandQueue
{
	return _downloadQueue;
}
/* NOTE:  Not sure if we necessarily need this subclass override here. This does seem to fix an issue with file based connections, but until I have a chance to test it further, we'll leave it commented out.  -Brian Amerige 
- (void)startBulkCommands
{
	[super startBulkCommands];
	_openBulkCommands++;
}
- (void)endBulkCommands
{
	[super endBulkCommands];
	_openBulkCommands--;
	
	if (_openBulkCommands == 0 && ![self isCheckingQueue])
	{
		[self checkQueue];
	}
}*/

#define ADD_TO_QUEUE(queue, object) [_queueLock lock]; [queue addObject:object]; [_queueLock unlock];

- (void)queueCommand:(CKConnectionCommand *)command
{
	[_queueLock lock];
	[_commandQueue addObject:command];
	KTLog(CKQueueDomain, KTLogDebug, @".. %@ (queue size now = %d)", [command command], [_commandQueue count]);		// show when a command gets queued
	[_queueLock unlock];
	
	BOOL isChecking;
	
	[_queueLock lock];
	isChecking = myQueueFlags.isCheckingQueue;
	
	// See checkQueue for an explanation of _checkQueueCount
	if (isChecking) {
		_checkQueueCount++;
	}
	[_queueLock unlock];
	
	if (!_inBulk && !isChecking) {
		[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] checkQueue];
	}
}

- (void)queueDownload:(id)download
{
	KTLog(CKQueueDomain, KTLogDebug, @"Queuing Download: %@", [download shortDescription]);
	ADD_TO_QUEUE(_downloadQueue, download)
}

- (void)queueUpload:(id)upload
{
	KTLog(CKQueueDomain, KTLogDebug, @"Queueing Upload: %@", [upload shortDescription]);
	ADD_TO_QUEUE(_uploadQueue, upload)
}

- (void)queueDeletion:(id)deletion
{
	KTLog(CKQueueDomain, KTLogDebug, @"Queuing Deletion: %@", [deletion shortDescription]);
	ADD_TO_QUEUE(_fileDeletes, deletion)
}

- (void)queueRename:(id)name
{
	KTLog(CKQueueDomain, KTLogDebug, @"Queuing Rename: %@", [name shortDescription]);
	ADD_TO_QUEUE(_fileRenames, name)
}

- (void)queuePermissionChange:(id)perms
{
	KTLog(CKQueueDomain, KTLogDebug, @"Queuing Permission Change: %@", [perms shortDescription]);
	ADD_TO_QUEUE(_filePermissions, perms)
}

- (void)queueFileCheck:(id)file
{
	KTLog(CKQueueDomain, KTLogDebug, @"Queuing File Existence: %@", [file shortDescription]);
	ADD_TO_QUEUE(_fileCheckQueue, file);
}

#define DEQUEUE(q) [_queueLock lock]; if ([q count] > 0) [q removeObjectAtIndex:0]; [_queueLock unlock];

- (void)dequeueCommand
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing Command");
	DEQUEUE(_commandQueue)
}

- (void)dequeueDownload
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing Download");
	DEQUEUE(_downloadQueue)
}

- (void)dequeueUpload
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing Upload");
	DEQUEUE(_uploadQueue)
}

- (void)dequeueDeletion
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing Deletion");
	DEQUEUE(_fileDeletes)
}

- (void)dequeueRename
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing Rename");
	DEQUEUE(_fileRenames)
}

- (void)dequeuePermissionChange
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing Permission Change");
	DEQUEUE(_filePermissions)
}

- (void)dequeueFileCheck
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing File Check");
	DEQUEUE(_fileCheckQueue);
}

#define CURRENT_QUEUE(q) \
	[_queueLock lock]; \
	id obj = nil; \
	if ([q count] > 0) { \
		obj = [[[q objectAtIndex:0] retain] autorelease]; \
	} \
	[_queueLock unlock]; \
	return obj;

- (id)currentCommand
{
	CURRENT_QUEUE(_commandQueue);
}

- (id)currentDownload
{
	CURRENT_QUEUE(_downloadQueue);
}

- (id)currentUpload
{
	CURRENT_QUEUE(_uploadQueue);
}

- (id)currentDeletion
{
	CURRENT_QUEUE(_fileDeletes);
}

- (id)currentRename
{
	CURRENT_QUEUE(_fileRenames);
}

- (id)currentPermissionChange
{
	CURRENT_QUEUE(_filePermissions);
}

- (id)currentFileCheck
{
	CURRENT_QUEUE(_fileCheckQueue);
}

#define COUNT_QUEUE(q) [_queueLock lock]; unsigned count = [q count]; [_queueLock unlock]; return count;

- (unsigned)numberOfCommands
{
	COUNT_QUEUE(_commandQueue)
}

- (unsigned)numberOfDownloads
{
	COUNT_QUEUE(_downloadQueue)
}

- (unsigned)numberOfUploads
{
	COUNT_QUEUE(_uploadQueue)
}

- (unsigned)numberOfDeletions
{
	COUNT_QUEUE(_fileDeletes)
}

- (unsigned)numberOfRenames
{
	COUNT_QUEUE(_fileRenames)
}

- (unsigned)numberOfPermissionChanges
{
	COUNT_QUEUE(_filePermissions)
}

- (unsigned)numberOfTransfers
{
	return [self numberOfUploads] + [self numberOfDownloads];
}

- (unsigned)numberOfFileChecks
{
	COUNT_QUEUE(_fileCheckQueue);
}

#define MT_QUEUE(q) [_queueLock lock]; [q removeAllObjects]; [_queueLock unlock];

- (void)emptyCommandQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying Command Queue");
	MT_QUEUE(_commandQueue)
}

- (void)emptyDownloadQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying Download Queue");
	MT_QUEUE(_downloadQueue)
}

- (void)emptyUploadQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying Upload Queue");
	MT_QUEUE(_uploadQueue)
}

- (void)emptyDeletionQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying Deletion Queue");
	MT_QUEUE(_fileDeletes)
}

- (void)emptyRenameQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying Rename Queue");
	MT_QUEUE(_fileRenames)
}

- (void)emptyFileCheckQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying File Existence Queue");
	MT_QUEUE(_fileCheckQueue);
}

- (void)emptyPermissionChangeQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying Permission Change Queue");
	MT_QUEUE(_filePermissions)
}

- (void)emptyAllQueues
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying All Queues");
	[_queueLock lock];
	[_commandQueue removeAllObjects];
	[_downloadQueue removeAllObjects];
	[_uploadQueue removeAllObjects];
	[_fileDeletes removeAllObjects];
	[_fileRenames removeAllObjects];
	[_filePermissions removeAllObjects];
	[_queueLock unlock];
}

@end

@interface CKConnectionCommand (Private)
- (void)setParentCommand:(CKConnectionCommand *)cmd;
@end

@implementation CKConnectionCommand

+ (id)command:(id)type 
   awaitState:(CKConnectionState)await
	sentState:(CKConnectionState)sent
	dependant:(CKConnectionCommand *)dep
	 userInfo:(id)ui
{
	return [CKConnectionCommand command:type
						   awaitState:await
							sentState:sent
						   dependants:dep != nil ? [NSArray arrayWithObject:dep] : [NSArray array]
							 userInfo:ui];
}

+ (id)command:(id)type 
   awaitState:(CKConnectionState)await
	sentState:(CKConnectionState)sent
   dependants:(NSArray *)deps
	 userInfo:(id)ui
{
	return [[[CKConnectionCommand alloc] initWithCommand:type
											awaitState:await
											 sentState:sent
											dependants:deps
											  userInfo:ui] autorelease];
}

- (id)initWithCommand:(id)type 
		   awaitState:(CKConnectionState)await
			sentState:(CKConnectionState)sent
		   dependants:(NSArray *)deps
			 userInfo:(id)ui
{
	if (self = [super init]) {
		_command = [type retain];
		_awaitState = await;
		_sentState = sent;
		_dependants = [[NSMutableArray arrayWithArray:deps] retain];
		[_dependants makeObjectsPerformSelector:@selector(setParentCommand:) withObject:self];
		_userInfo = [ui retain];
		_properties = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_dependants makeObjectsPerformSelector:@selector(setParentCommand:) withObject:nil];
	[_dependants release];
	[_userInfo release];
	[_command release];
	[_properties release];
	[super dealloc];
}

- (NSString *)description
{
	if ([_command isKindOfClass:[NSInvocation class]])
		return [NSString stringWithFormat:@"Invocation with selector: %@", NSStringFromSelector([_command selector])];
	return [NSString stringWithFormat:@"%@", _command];
}

- (void)setCommand:(id)type
{
	[_command autorelease];
	_command = [type copy];
}

- (void)setAwaitState:(CKConnectionState)await
{
	_awaitState = await;
}

- (void)setSentState:(CKConnectionState)sent
{
	_sentState = sent;
}

- (void)setUserInfo:(id)ui
{
	[_userInfo autorelease];
	_userInfo = [ui retain];
}

- (void)setProperty:(id)property forKey:(NSString *)key
{
	[_properties setObject:property forKey:key];
}

- (id)propertyForKey:(NSString *)key
{
	return [_properties objectForKey:key];
}

- (id)command
{
	return _command;
}

- (CKConnectionState)awaitState
{
	return _awaitState;
}

- (CKConnectionState)sentState
{
	return _sentState;
}

- (id)userInfo
{
	return _userInfo;
}

- (void)addDependantCommand:(CKConnectionCommand *)command
{
	[command setParentCommand:self];
	[_dependants addObject:command];
}

- (void)removeDependantCommand:(CKConnectionCommand *)command
{
	[command setParentCommand:nil];
	[_dependants removeObject:command];
}

- (NSArray *)dependantCommands
{
	return [NSArray arrayWithArray:_dependants];
}

- (void)setParentCommand:(CKConnectionCommand *)cmd
{
	_parent = cmd;
}

- (CKConnectionCommand *)parentCommand
{
	return _parent;
}

- (CKConnectionCommand *)firstCommandInChain
{
	if (_parent)
		return [_parent firstCommandInChain];
	return self;
}

- (void)recursivelyAddedSequencedCommand:(CKConnectionCommand *)cmd toSequence:(NSMutableArray *)sequence
{
	[sequence addObject:cmd];
	NSEnumerator *e = [[cmd dependantCommands] objectEnumerator];
	CKConnectionCommand *cur;
	
	while (cur = [e nextObject])
	{
		[self recursivelyAddedSequencedCommand:cur toSequence:sequence];
	}
}

- (NSArray *)sequencedChain
{
	NSMutableArray *sequence = [NSMutableArray array];
	
	CKConnectionCommand *first = [self firstCommandInChain];
	
	[self recursivelyAddedSequencedCommand:first toSequence:sequence];
	
	return sequence;
}

@end


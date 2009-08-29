/*
 Copyright (c) 2004-2006 Karelia Software. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Karelia Software nor the names of its contributors may be used to 
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

#import "CKFileConnection.h"
#import "RunLoopForwarder.h"

#import "CKConnectionThreadManager.h"
#import "CKInternalTransferRecord.h"
#import "CKTransferRecord.h"
#import "CKAbstractQueueConnection.h"
#import "NSFileManager+Connection.h"
#import "CKConnectionProtocol.h"

NSString *CKFileConnectionErrorDomain = @"FileConnectionErrorDomain";

enum { CONNECT = 4000, COMMAND, ABORT, CANCEL_ALL, DISCONNECT, FORCE_DISCONNECT, KILL_THREAD };		// port messages

@interface CKFileConnection (Private)
- (void)processInvocations;
- (void)_uploadFile:(NSString *)f toFile:(NSString *)t;
- (void)sendPortMessage:(int)message;
- (void)_upload:(CKInternalTransferRecord *)upload
checkRemoteExistence:(NSNumber *)check;
- (void)_threaded_upload:(CKInternalTransferRecord *)internalUploadRecord checkRemoteExistence:(NSNumber *)check;
@end

@implementation CKFileConnection

#pragma mark -
#pragma mark Accessors

- (int)currentOperation
{
    return myCurrentOperation;
}
- (void)setCurrentOperation:(int)aCurrentOperation
{
    myCurrentOperation = aCurrentOperation;
}

#pragma mark -
#pragma mark Initialization

/*!	Simpler initializer since there's none of this information needed
*/
+ (CKFileConnection *)connection
{
	CKFileConnection *c = [[CKFileConnection alloc] init];
	return [c autorelease];
}

+ (CKProtocol)protocol
{
	return CKFileProtocol;
}

+ (void)load    // registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	//Register all URL Schemes and the protocol.
	NSEnumerator *URLSchemeEnumerator = [[self URLSchemes] objectEnumerator];
	NSString *URLScheme;
	while ((URLScheme = [URLSchemeEnumerator nextObject]))
		[[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forProtocol:[self protocol] URLScheme:URLScheme];
	
    [pool release];
}

+ (NSArray *)URLSchemes { return [NSArray arrayWithObject:@"file"]; }

- (id)initWithRequest:(CKConnectionRequest *)request
{
	if (self = [super initWithRequest:request])
	{
		myCurrentDirectory = [[NSString alloc] initWithString:NSHomeDirectory()];
	}
	return self;
}

- (id)init
{
	return [self initWithRequest:[CKConnectionRequest requestWithURL:[NSURL fileURLWithPath:NSHomeDirectory()]]];
}

- (void)dealloc
{
	[myCurrentDirectory release];
	[super dealloc];
}

- (void)connect
{
	if (!_isConnecting && ![self isConnected])
	{
		[[self client] appendLine:LocalizedStringInConnectionKitBundle(@"Connecting...", @"file transcript") toTranscript:CKTranscriptSent];
		[super connect];
	}
}

- (void)sendCommand:(id)command
{
	[command invoke];
}

- (void)threadedConnect
{
	[super threadedConnect];
	
    myFileManager = [[NSFileManager alloc] init];
	[[self client] appendLine:LocalizedStringInConnectionKitBundle(@"Connected to File System", @"file transcript") toTranscript:CKTranscriptSent];
	
	[self setState:CKConnectionIdleState];
	[[self client] connectionDidOpenAtPath:[self currentDirectory] error:nil];
}

- (void)threadedAbort
{
    NSString *remotePath = [self currentUpload] ? [[self currentUpload] remotePath] : [[self currentDownload] remotePath];
    [[self client] connectionDidCancelTransfer:remotePath];
	[self processInvocations];
}

- (void)threadedCancelAll
{
	[self threadedAbort];
}


#pragma mark -
#pragma mark Main Methods

- (void)_changeToDirectory:(NSString *)aDirectory
{
	[self setCurrentOperation:kChangeToDirectory];
		
	if ([myFileManager changeCurrentDirectoryPath:aDirectory])
	{
		[[self client] connectionDidChangeToDirectory:aDirectory error:nil];
	}
	
	[myCurrentDirectory autorelease];
	myCurrentDirectory = [aDirectory copy];
	[self setState:CKConnectionIdleState];
}

- (void)changeToDirectory:(NSString *)aDirectory	// an absolute directory
{
	NSAssert(aDirectory && ![aDirectory isEqualToString:@""], @"no directory specified");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(_changeToDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObjects:aDirectory, nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionChangedDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

#pragma mark -
- (NSString *)currentDirectory
{
	return myCurrentDirectory;
}

#pragma mark -

- (void)createDirectory:(NSString *)dirPath
{
	[self createDirectory:dirPath permissions:0755];
}

- (void)_createDirectory:(NSString *)aName permissions:(NSNumber *)perms
{
	[self setCurrentOperation:kCreateDirectory];
	unsigned long aPermissions = [perms unsignedLongValue];
	
	[[self client] appendFormat:LocalizedStringInConnectionKitBundle(@"Create Directory %@ (%lo)", @"file transcript")
                   toTranscript:CKTranscriptSent,
                                aName,
								aPermissions];
	
	
	NSDictionary *fmDictionary = nil;
	if (0 != aPermissions)
	{
		fmDictionary = [NSDictionary dictionaryWithObject:[NSNumber numberWithLong:aPermissions] forKey:NSFilePosixPermissions];
	}
	
	NSError *error = nil;	
    if (![myFileManager createDirectoryAtPath:aName withIntermediateDirectories:YES attributes:fmDictionary error:&error])
	{
		BOOL exists;
		[myFileManager fileExistsAtPath:aName isDirectory:&exists];
		NSDictionary *ui = [NSDictionary dictionaryWithObjectsAndKeys:
							LocalizedStringInConnectionKitBundle(@"Could not create directory", @"FileConnection create directory error"), NSLocalizedDescriptionKey,
							aName, NSFilePathErrorKey,
							[NSNumber numberWithBool:exists], ConnectionDirectoryExistsKey,
							aName, ConnectionDirectoryExistsFilenameKey, nil];		
		error = [NSError errorWithDomain:CKFileConnectionErrorDomain code:[self currentOperation] userInfo:ui];
	}
	
    [[self client] connectionDidCreateDirectory:aName error:error];
    
	[self setState:CKConnectionIdleState];
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)aPermissions
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no directory specified");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(_createDirectory:permissions:)
													  target:self
												   arguments:[NSArray arrayWithObjects:dirPath, [NSNumber numberWithUnsignedLong:aPermissions], nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionCreateDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

#pragma mark -

- (void)_setPermissions:(NSNumber *)perms forFile:(NSString *)path
{
	[self setCurrentOperation:kSetPermissions];
	
    NSError *error = nil;
	NSMutableDictionary *attribs = [[myFileManager attributesOfItemAtPath:path error:&error] mutableCopy];
	[attribs setObject:perms forKey:NSFilePosixPermissions];
	
	if (![myFileManager setAttributes:attribs ofItemAtPath:path error:&error])
	{
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  LocalizedStringInConnectionKitBundle(@"Could not change file permissions", @"FileConnection set permissions error"), NSLocalizedDescriptionKey,
								  path, NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:CKFileConnectionErrorDomain code:[self currentOperation] userInfo:userInfo];		
	}
	
    [[self client] connectionDidSetPermissionsForFile:path error:error];

	[attribs release];
	[self setState:CKConnectionIdleState];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"no file/path specified");
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(_setPermissions:forFile:)
													  target:self
												   arguments:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedLong:permissions], path, nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionSettingPermissionsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

#pragma mark -
- (void)_rename:(NSString *)fromPath to:(NSString *)toPath
{
	[self setCurrentOperation:kRename];
	
    [[self client] appendFormat:LocalizedStringInConnectionKitBundle(@"Renaming %@ to %@", @"file transcript")
                   toTranscript:CKTranscriptSent, fromPath, toPath];
	
	NSError *error = nil;	
	if (![myFileManager moveItemAtPath:fromPath toPath:toPath error:&error] || error != nil)
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to rename file.", @"Failed to rename file.");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedDescription, NSLocalizedDescriptionKey, nil];
		error = [NSError errorWithDomain:CKFileConnectionErrorDomain code:[self currentOperation] userInfo:userInfo];
	}
	
    [[self client] connectionDidRename:fromPath to:toPath error:error];

	[self setState:CKConnectionIdleState];
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSAssert(fromPath && ![fromPath isEqualToString:@""], @"fromPath is nil!");
    NSAssert(toPath && ![toPath isEqualToString:@""], @"toPath is nil!");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(_rename:to:)
													  target:self
												   arguments:[NSArray arrayWithObjects:fromPath, toPath, nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionAwaitingRenameState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

#pragma mark -

- (void)_deleteFile:(NSString *)path
{
	[self setCurrentOperation:kDeleteFile];
	
    [[self client] appendFormat:LocalizedStringInConnectionKitBundle(@"Deleting File %@", @"file transcript")
                   toTranscript:CKTranscriptSent, path];
	
	
	NSError *error = nil;	
	if (![myFileManager removeItemAtPath:path error:&error] || error != nil)
	{
		NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Failed to delete file: %@", @"error for deleting a file"), path];
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  localizedDescription, NSLocalizedDescriptionKey, 
								  path, NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:CKFileConnectionErrorDomain code:kDeleteFile userInfo:userInfo];		
	}
	
    [[self client] connectionDidDeleteFile:path error:error];
	
	[self setState:CKConnectionIdleState];
}

- (void)deleteFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"path is nil!");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(_deleteFile:)
													  target:self 
												   arguments:[NSArray arrayWithObject:path]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionDeleteFileState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)_deleteDirectory:(NSString *)dirPath
{
	[self setCurrentOperation:kDeleteDirectory];
	
	NSError *error = nil;
	if (![myFileManager removeItemAtPath:dirPath error:&error] || error != nil)
	{
		NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Failed to delete directory: %@", @"error for deleting a directory"), dirPath];
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  localizedDescription, NSLocalizedDescriptionKey,
								  dirPath, NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:CKFileConnectionErrorDomain code:kDeleteFile userInfo:userInfo];
	}
	
    [[self client] connectionDidDeleteDirectory:dirPath error:error];

	[self setState:CKConnectionIdleState];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"dirPath is nil!");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(_deleteDirectory:)
													  target:self 
												   arguments:[NSArray arrayWithObject:dirPath]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionDeleteDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)recursivelyDeleteDirectory:(NSString *)path
{
	[self deleteDirectory:path];
}

#pragma mark -

- (void)_upload:(CKInternalTransferRecord *)internalUploadRecord checkRemoteExistence:(NSNumber *)check
{
	//We thread this to prevent blocking, since we're looping through the file read/write
	NSDictionary *argumentDictionary = [NSDictionary dictionaryWithObjectsAndKeys:internalUploadRecord, @"internalUploadRecord", check, @"checkRemoteExistence", nil];
	[NSThread detachNewThreadSelector:@selector(_threadedUpload:) toTarget:self withObject:argumentDictionary];
}
- (void)_threadedUpload:(NSDictionary *)argumentDictionary
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	CKInternalTransferRecord *internalUploadRecord = [argumentDictionary objectForKey:@"internalUploadRecord"];
	CKTransferRecord *transferRecord = [internalUploadRecord userInfo];
	NSFileManager *fm = myFileManager;
	BOOL flag = [[argumentDictionary objectForKey:@"checkRemoteExistence"] boolValue];
	
	[[self client] appendFormat:LocalizedStringInConnectionKitBundle(@"Copying %@ to %@", @"file transcript")
                   toTranscript:CKTranscriptSent, [internalUploadRecord localPath], [internalUploadRecord remotePath]];
		
	if (flag)
	{
		if ([fm fileExistsAtPath:[internalUploadRecord remotePath]])
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File Already Exists", @"FileConnection error"), NSLocalizedDescriptionKey, 
									  [internalUploadRecord remotePath], NSFilePathErrorKey, nil];
			NSError *error = [NSError errorWithDomain:CKFileConnectionErrorDomain code:kFileExists userInfo:userInfo];
			[internalUploadRecord retain];
			[self dequeueUpload];
			// send finished

			[[self client] uploadDidFinish:[internalUploadRecord remotePath] error:error];
			
            if ([internalUploadRecord delegateRespondsToTransferDidFinish])
				[[internalUploadRecord delegate] transferDidFinish:transferRecord error:error];
			[internalUploadRecord release];
			[self setState:CKConnectionIdleState];			
			
			[pool release];
			return;
		}
	}
	
    NSError *error = nil;
	[fm removeItemAtPath:[internalUploadRecord remotePath] error:&error];
	
	if ([internalUploadRecord delegateRespondsToTransferDidBegin])
		[[internalUploadRecord delegate] transferDidBegin:transferRecord];

    [[self client] uploadDidBegin:[internalUploadRecord remotePath]];
	
	FILE *from = fopen([[internalUploadRecord localPath] fileSystemRepresentation], "r"); // Must use -fileSystemRepresentation to handle non-ASCII paths
	FILE *to = fopen([[internalUploadRecord remotePath] fileSystemRepresentation], "a");
	
	// I put these assertions back in; it's better to get an assertion failure than a crash!
	NSAssert(from, @"path from cannot be found");
	NSAssert(to, @"path to cannot be found");
	int fno = fileno(from), tno = fileno(to);
	char bytes[8096];
	int len;
	unsigned long long size = [[[fm attributesOfItemAtPath:[internalUploadRecord localPath] error:&error] objectForKey:NSFileSize] unsignedLongLongValue];
	unsigned long long sizeDecrementing = size;

	clearerr(from);
	
	// feof() doesn;t seem to work for some reason so we'll just count the byte size of the file
	NSTimeInterval lastTransferredLengthUpdateTime = 0.0;
	while (sizeDecrementing > 0) 
	{
		len = read(fno, bytes, 8096);
		len = write(tno, bytes, len);
		
		//Inform delegates and records
		
		unsigned long long transferredSoFar = (size - sizeDecrementing);
		
		//Only update transferredLength at most once per second. This prevents too many notifications being sent.
		NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
		NSTimeInterval timeSinceLastTransferredLengthUpdate = now - lastTransferredLengthUpdateTime;
		if (lastTransferredLengthUpdateTime == 0.0 || timeSinceLastTransferredLengthUpdate >= 1.0)
		{
			unsigned long long deltaTransferred = transferredSoFar - [transferRecord transferred];
			if ([internalUploadRecord delegateRespondsToTransferTransferredData])
				[[internalUploadRecord delegate] transfer:transferRecord transferredDataOfLength:deltaTransferred];
			[[self client] upload:[internalUploadRecord remotePath] didSendDataOfLength:deltaTransferred];			
		}
		
		//Progress
		NSInteger percentageTransferred = (NSInteger)(((double)transferredSoFar / (double)size) * 100);
		
		//Only send updates for progress if we've changed integer progress. This prevents too many notifications being sent.
		if ((percentageTransferred - [transferRecord progress]) >= 1)
		{
			NSNumber *percent = [NSNumber numberWithInt:percentageTransferred];
			if ([internalUploadRecord delegateRespondsToTransferProgressedTo])
				[[internalUploadRecord delegate] transfer:transferRecord progressedTo:percent];
			[[self client] upload:[internalUploadRecord remotePath] didProgressToPercent:percent];
		}
		
		sizeDecrementing -= len;
	}
	
	fclose(from);
	fclose(to);
	
	[internalUploadRecord retain];
	[self dequeueUpload];

	// send finished
	if ([internalUploadRecord delegateRespondsToTransferDidFinish])
		[[internalUploadRecord delegate] transferDidFinish:transferRecord error:nil];
	[[self client] uploadDidFinish:[internalUploadRecord remotePath] error:nil];
	
	[internalUploadRecord release];
	[self setState:CKConnectionIdleState];
	
	[pool release];
}

- (CKTransferRecord *)_uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate
{
	NSAssert(localPath && ![localPath isEqualToString:@""], @"localPath is nil!");
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
    NSError *error = nil;
	NSDictionary *attribs = [myFileManager attributesOfItemAtPath:localPath error:&error];
	CKTransferRecord *rec = [CKTransferRecord uploadRecordForConnection:self
														sourceLocalPath:localPath
												  destinationRemotePath:remotePath
																   size:[[attribs objectForKey:NSFileSize] unsignedLongLongValue] 
															isDirectory:NO];
	CKInternalTransferRecord *upload = [CKInternalTransferRecord recordWithLocal:localPath
																			data:nil
																		  offset:0
																		  remote:remotePath
																		delegate:(delegate) ? delegate : rec
																		userInfo:rec];
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(_upload:checkRemoteExistence:)
													  target:self
												   arguments:[NSArray arrayWithObjects:upload, [NSNumber numberWithBool:flag], nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	[self queueUpload:upload];
	[self queueCommand:cmd];
	return rec;
}

- (void)_uploadData:(CKInternalTransferRecord *)upload checkRemoteExistence:(NSNumber *)check
{
	BOOL flag = [check boolValue];
	
	[[self client] appendFormat:LocalizedStringInConnectionKitBundle(@"Writing data to %@", @"file transcript")
                   toTranscript:CKTranscriptSent, [upload remotePath]];
	
	if (flag)
	{
		if ([myFileManager fileExistsAtPath:[upload remotePath]])
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File Already Exists", @"FileConnection error"), NSLocalizedDescriptionKey, 
									  [upload remotePath], NSFilePathErrorKey, nil];
			NSError *error = [NSError errorWithDomain:CKFileConnectionErrorDomain code:kFileExists userInfo:userInfo];
			
			// send finished
            [[self client] uploadDidFinish:[upload remotePath] error:error];
			
            if ([upload delegateRespondsToTransferDidFinish])
				[[upload delegate] transferDidFinish:[upload userInfo] error:error];			
			return;
		}
	}
    NSError *error = nil;
	(void) [myFileManager removeItemAtPath:[upload remotePath] error:&error];
	BOOL success = [myFileManager createFileAtPath:[upload remotePath]
										  contents:[upload data]
										attributes:nil];

	if ([upload delegateRespondsToTransferDidBegin])
		[[upload delegate] transferDidBegin:[upload userInfo]];

    [[self client] uploadDidBegin:[upload remotePath]];
    
	//need to send the amount of bytes transferred.
	unsigned long long size = [[[myFileManager attributesOfItemAtPath:[upload remotePath] error:&error] objectForKey:NSFileSize] unsignedLongLongValue];

    [[self client] upload:[upload remotePath] didSendDataOfLength:size];
    
	if ([upload delegateRespondsToTransferTransferredData])
		[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:size];
	// send 100%
	if ([upload delegateRespondsToTransferProgressedTo])
		[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:100]];

    [[self client] upload:[upload remotePath] didProgressToPercent:[NSNumber numberWithInt:100]];
	
	if (!success)
	{
		 NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								   LocalizedStringInConnectionKitBundle(@"Failed to upload data", @"FileConnection copy data error"), NSLocalizedDescriptionKey,
								   [upload remotePath], NSFilePathErrorKey,nil];
		 error = [NSError errorWithDomain:CKConnectionErrorDomain code:ConnectionErrorUploading userInfo:userInfo];
	}
	
	// send finished
	[[self client] uploadDidFinish:[upload remotePath] error:error];
    
	if ([upload delegateRespondsToTransferDidFinish])
		[[upload delegate] transferDidFinish:[upload userInfo] error:error];

	[self setState:CKConnectionIdleState];
}

- (CKTransferRecord *)uploadFromData:(NSData *)data
							  toFile:(NSString *)remotePath 
				checkRemoteExistence:(BOOL)flag
							delegate:(id)delegate
{
	NSAssert(data, @"no data");	// data should not be nil, but it shoud be OK to have zero length!
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
	CKTransferRecord *rec = [CKTransferRecord uploadRecordForConnection:self
														sourceLocalPath:@""
												  destinationRemotePath:remotePath
																   size:[data length] 
															isDirectory:NO];
	CKInternalTransferRecord *upload = [CKInternalTransferRecord recordWithLocal:nil
																			data:data
																		  offset:0
																		  remote:remotePath
																		delegate:delegate ? delegate : rec
																		userInfo:rec];
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(_uploadData:checkRemoteExistence:)
													  target:self
												   arguments:[NSArray arrayWithObjects:upload, [NSNumber numberWithBool:flag], nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
	return rec;
}

#pragma mark -
- (void)_download:(CKInternalTransferRecord *)internalDownloadRecord overwrite:(NSNumber *)overwrite
{
	//We thread this to prevent blocking, since we're looping through the file read/write
	NSDictionary *argumentDictionary = [NSDictionary dictionaryWithObjectsAndKeys:internalDownloadRecord, @"internalDownloadRecord", overwrite, @"overwrite", nil];
	[NSThread detachNewThreadSelector:@selector(_threadedDownload:) toTarget:self withObject:argumentDictionary];
}
- (void)_threadedDownload:(NSDictionary *)argumentDictionary
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	CKInternalTransferRecord *internalDownloadRecord = [argumentDictionary objectForKey:@"internalDownloadRecord"];
	CKTransferRecord *transferRecord = [internalDownloadRecord userInfo];
	NSFileManager *fm = myFileManager;
	BOOL flag = [[argumentDictionary objectForKey:@"overwrite"] boolValue];
	
	[[self client] appendFormat:LocalizedStringInConnectionKitBundle(@"Copying %@ to %@", @"file transcript")
                   toTranscript:CKTranscriptSent, [internalDownloadRecord localPath], [internalDownloadRecord remotePath]];
	
	NSString *sourcePath = [internalDownloadRecord remotePath];
	NSString *destinationPath = [internalDownloadRecord localPath];
	
	if (flag)
	{
		if ([fm fileExistsAtPath:destinationPath])
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File Already Exists", @"FileConnection error"), NSLocalizedDescriptionKey, 
									  destinationPath, NSFilePathErrorKey, nil];
			NSError *error = [NSError errorWithDomain:CKFileConnectionErrorDomain code:kFileExists userInfo:userInfo];
			[internalDownloadRecord retain];
			[self dequeueDownload];
			// send finished
			
			[[self client] downloadDidFinish:sourcePath error:error];
			
            if ([internalDownloadRecord delegateRespondsToTransferDidFinish])
				[[internalDownloadRecord delegate] transferDidFinish:transferRecord error:error];
			[internalDownloadRecord release];
			[self setState:CKConnectionIdleState];			
			
			[pool release];
			return;
		}
	}
	NSError *error = nil;
	[fm removeItemAtPath:destinationPath error:&error];
	
	if ([internalDownloadRecord delegateRespondsToTransferDidBegin])
		[[internalDownloadRecord delegate] transferDidBegin:transferRecord];
	
    [[self client] downloadDidBegin:sourcePath];
	
	FILE *from = fopen([sourcePath fileSystemRepresentation], "r"); // Must use -fileSystemRepresentation to handle non-ASCII paths
	FILE *to = fopen([destinationPath fileSystemRepresentation], "a");
	
	// I put these assertions back in; it's better to get an assertion failure than a crash!
	NSAssert(from, @"path from cannot be found");
	NSAssert(to, @"path to cannot be found");
	int fno = fileno(from), tno = fileno(to);
	char bytes[8096];
	int len;
	unsigned long long size = [[[fm attributesOfItemAtPath:sourcePath error:&error] objectForKey:NSFileSize] unsignedLongLongValue];
	unsigned long long sizeDecrementing = size;
	
	clearerr(from);
	
	// feof() doesn;t seem to work for some reason so we'll just count the byte size of the file
	NSTimeInterval lastTransferredLengthUpdateTime = 0.0;
	while (sizeDecrementing > 0) 
	{
		len = read(fno, bytes, 8096);
		len = write(tno, bytes, len);
		
		//Inform delegates and records
		
		unsigned long long transferredSoFar = (size - sizeDecrementing);
		
		//Only update transferredLength at most once per second. This prevents too many notifications being sent.
		NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
		NSTimeInterval timeSinceLastTransferredLengthUpdate = now - lastTransferredLengthUpdateTime;
		if (lastTransferredLengthUpdateTime == 0.0 || timeSinceLastTransferredLengthUpdate >= 1.0)
		{
			unsigned long long deltaTransferred = transferredSoFar - [transferRecord transferred];
			if ([internalDownloadRecord delegateRespondsToTransferTransferredData])
				[[internalDownloadRecord delegate] transfer:transferRecord transferredDataOfLength:deltaTransferred];
			[[self client] download:sourcePath didReceiveDataOfLength:deltaTransferred];		
		}
		
		//Progress
		NSInteger percentageTransferred = (NSInteger)(((double)transferredSoFar / (double)size) * 100);
		
		//Only send updates for progress if we've changed integer progress. This prevents too many notifications being sent.
		if ((percentageTransferred - [transferRecord progress]) >= 1)
		{
			NSNumber *percent = [NSNumber numberWithInt:percentageTransferred];
			if ([internalDownloadRecord delegateRespondsToTransferProgressedTo])
				[[internalDownloadRecord delegate] transfer:transferRecord progressedTo:percent];
			[[self client] download:sourcePath didProgressToPercent:percent];
		}
		
		sizeDecrementing -= len;
	}
	
	fclose(from);
	fclose(to);
	
	[internalDownloadRecord retain];
	[self dequeueDownload];
	
	// send finished
	if ([internalDownloadRecord delegateRespondsToTransferDidFinish])
		[[internalDownloadRecord delegate] transferDidFinish:transferRecord error:nil];
	[[self client] downloadDidFinish:sourcePath error:nil];
	
	[internalDownloadRecord release];
	[self setState:CKConnectionIdleState];
	
	[pool release];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	[self downloadFile:remotePath toDirectory:dirPath overwrite:flag delegate:nil];
}

- (CKTransferRecord *)downloadFile:(NSString *)remotePath 
					   toDirectory:(NSString *)dirPath 
						 overwrite:(BOOL)flag
						  delegate:(id)delegate
{
	NSString *destinationLocalPath = [dirPath stringByAppendingPathComponent:[remotePath lastPathComponent]];
	CKTransferRecord *record = [CKTransferRecord downloadRecordForConnection:self
															sourceRemotePath:remotePath
														destinationLocalPath:destinationLocalPath
																		size:0 
																 isDirectory:NO];
	CKTransferRecord *download = [CKInternalTransferRecord recordWithLocal:destinationLocalPath
																	  data:nil
																	offset:0
																	remote:remotePath
																  delegate:(delegate) ? delegate : record
																  userInfo:record];
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(_download:overwrite:) target:self arguments:[NSArray arrayWithObjects:download, [NSNumber numberWithBool:flag], nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
												 awaitState:CKConnectionIdleState
												  sentState:CKConnectionDownloadingFileState 
												  dependant:nil
												   userInfo:nil];
	[self queueDownload:download];
	[self queueCommand:cmd];
	return record;
}

#pragma mark -

- (void)directoryContents
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(_directoryContents)
													  target:self
												   arguments:[NSArray array]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)_contentsOfDirectory:(NSString *)dirPath
{
	[self setCurrentOperation:kDirectoryContents];
	
    NSError *error = nil;
	NSArray *array = [myFileManager contentsOfDirectoryAtPath:dirPath error:&error];
	NSMutableArray *packaged = [NSMutableArray arrayWithCapacity:[array count]];
	NSEnumerator *e = [array objectEnumerator];
	NSString *cur;
	
	while (cur = [e nextObject])
	{
		NSString *file = [dirPath stringByAppendingPathComponent:cur];
		NSDictionary *localAttributes = [myFileManager attributesOfItemAtPath:file error:&error];
		
		CKDirectoryListingItem *item = [CKDirectoryListingItem directoryListingItem];
		[item setFilename:cur];
		[item setFileType:[localAttributes objectForKey:NSFileType]];
		[item setReferenceCount:[[localAttributes objectForKey:NSFileReferenceCount] unsignedLongValue]];
		[item setModificationDate:[localAttributes objectForKey:NSFileModificationDate]];
		[item setCreationDate:[localAttributes objectForKey:NSFileCreationDate]];
		[item setSize:[localAttributes objectForKey:NSFileSize]];
		[item setFileOwnerAccountName:[localAttributes objectForKey:NSFileOwnerAccountName]];
		[item setGroupOwnerAccountName:[localAttributes objectForKey:NSFileGroupOwnerAccountName]];
		[item setPosixPermissions:[localAttributes objectForKey:NSFilePosixPermissions]];
		
		if ([item isSymbolicLink])
		{
			NSString *target = [file stringByResolvingSymlinksInPath];
			BOOL isDir;
			[myFileManager fileExistsAtPath:target isDirectory:&isDir];
			if (isDir && ![target hasSuffix:@"/"])
			{
				target = [target stringByAppendingString:@"/"];
			}
			[item setSymbolicLinkTarget:target];
		}
		
		[packaged addObject:item];
	}
	
	[[self client] connectionDidReceiveContents:packaged ofDirectory:dirPath error:nil];
    
	[self setState:CKConnectionIdleState];
}

- (void)_directoryContents
{
	[self _contentsOfDirectory:[self currentDirectory]];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(_contentsOfDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObject:dirPath]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

#pragma mark -

- (void)_checkExistenceOfPath:(NSString *)path
{
  
	[self setCurrentOperation:kDirectoryContents];
	
	BOOL fileExists = [myFileManager fileExistsAtPath: path];
  

	[[self client] connectionDidCheckExistenceOfPath:path pathExists:fileExists error:nil];
}

- (void)checkExistenceOfPath:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"path not specified");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(_checkExistenceOfPath:)
                                                    target:self
                                                 arguments:[NSArray arrayWithObject:path]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionCheckingFileExistenceState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

#pragma mark -
#pragma mark Delegate Methods

- (BOOL)fileManager:(NSFileManager *)manager shouldProceedAfterError:(NSDictionary *)errorInfo
{
	NSString *path = [errorInfo objectForKey:@"Path"];
	NSString *toPath = [errorInfo objectForKey:@"ToPath"];
	NSString *errorString = [errorInfo objectForKey:@"Error"];

    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              errorString, NSLocalizedDescriptionKey,
                              path, NSFilePathErrorKey,
                              toPath, @"ToPath", nil]; // "ToPath" might be nil ... that's OK, it's at the end of the list
    NSError *error = [NSError errorWithDomain:CKFileConnectionErrorDomain code:[self currentOperation] userInfo:userInfo];
    [[self client] connectionDidReceiveError:error];
    
	return NO;
}

@end
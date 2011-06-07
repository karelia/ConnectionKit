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
#import "InterThreadMessaging.h"
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
- (void)fcUploadFile:(NSString *)f toFile:(NSString *)t;
- (void)sendPortMessage:(int)message;
- (void)fcUpload:(CKInternalTransferRecord *)upload
checkRemoteExistence:(NSNumber *)check;
@end

@implementation CKFileConnection

+ (void)load	// registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forName:[self name] URLScheme:@"file"];
    [pool release];
}

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

+ (NSString *)name
{
	return @"File";
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
		[[self client] appendString:LocalizedStringInConnectionKitBundle(@"Connecting...", @"file transcript") toTranscript:CKTranscriptSent];
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
	[[self client] appendString:LocalizedStringInConnectionKitBundle(@"Connected to File System", @"file transcript") toTranscript:CKTranscriptSent];
	[self setState:CKConnectionIdleState];
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

- (void)fcChangeToDirectory:(NSString *)aDirectory
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
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcChangeToDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObjects:aDirectory, nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionChangedDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (NSString *)currentDirectory
{
	return myCurrentDirectory;
}

- (void)createDirectory:(NSString *)dirPath
{
	[self createDirectory:dirPath permissions:0755];
}

- (void)fcCreateDirectory:(NSString *)aName permissions:(NSNumber *)perms
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
	if (![myFileManager createDirectoryAtPath:aName withIntermediateDirectories:NO attributes:fmDictionary error:NULL])
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
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcCreateDirectory:permissions:)
													  target:self
												   arguments:[NSArray arrayWithObjects:dirPath, [NSNumber numberWithUnsignedLong:aPermissions], nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionCreateDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)fcSetPermissions:(NSNumber *)perms forFile:(NSString *)path
{
	[self setCurrentOperation:kSetPermissions];
	
	NSMutableDictionary *attribs = [[myFileManager attributesOfItemAtPath:path error:NULL] mutableCopy];
	[attribs setObject:perms forKey:NSFilePosixPermissions];
	
	NSError *error = nil;
	if (![myFileManager setAttributes:attribs ofItemAtPath:path error:NULL])
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
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcSetPermissions:forFile:)
													  target:self
												   arguments:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedLong:permissions], path, nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionSettingPermissionsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)fcRename:(NSString *)fromPath to:(NSString *)toPath
{
	[self setCurrentOperation:kRename];
	
    [[self client] appendFormat:LocalizedStringInConnectionKitBundle(@"Renaming %@ to %@", @"file transcript")
                   toTranscript:CKTranscriptSent, fromPath, toPath];
	
	NSError *error = nil;	
	if (![myFileManager moveItemAtPath:fromPath toPath:toPath error:NULL])
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
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcRename:to:)
													  target:self
												   arguments:[NSArray arrayWithObjects:fromPath, toPath, nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionAwaitingRenameState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)fcDeleteFile:(NSString *)path
{
	[self setCurrentOperation:kDeleteFile];
	
    [[self client] appendFormat:LocalizedStringInConnectionKitBundle(@"Deleting File %@", @"file transcript")
                   toTranscript:CKTranscriptSent, path];
	
	
	NSError *error = nil;	
	if (![myFileManager removeItemAtPath:path error:NULL])
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
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDeleteFile:)
													  target:self 
												   arguments:[NSArray arrayWithObject:path]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionDeleteFileState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)fcDeleteDirectory:(NSString *)dirPath
{
	[self setCurrentOperation:kDeleteDirectory];
	
	NSError *error = nil;
	if (![myFileManager removeItemAtPath:dirPath error:NULL])
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
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDeleteDirectory:)
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

- (void)fcUpload:(CKInternalTransferRecord *)upload checkRemoteExistence:(NSNumber *)check
{
	NSFileManager *fm = myFileManager;
	BOOL flag = [check boolValue];
	
	[[self client] appendFormat:LocalizedStringInConnectionKitBundle(@"Copying %@ to %@", @"file transcript")
                   toTranscript:CKTranscriptSent, [upload localPath], [upload remotePath]];
		
    if (![fm fileExistsAtPath:[upload localPath]])
    {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  LocalizedStringInConnectionKitBundle(@"File does not exist", @"FileConnection error"), NSLocalizedDescriptionKey, 
                                  [upload localPath], NSFilePathErrorKey, nil];
        NSError *error = [NSError errorWithDomain:CKFileConnectionErrorDomain code:-1 userInfo:userInfo];
        [upload retain];
        [self dequeueUpload];
        // send finished
        
        [[self client] uploadDidFinish:[upload remotePath] error:error];
        
        if ([upload delegateRespondsToTransferDidFinish])
            [[upload delegate] transferDidFinish:[upload userInfo] error:error];
        [upload release];
        [self setState:CKConnectionIdleState];			
        return;
    }
    
	if (flag)
	{
		if ([fm fileExistsAtPath:[upload remotePath]])
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File Already Exists", @"FileConnection error"), NSLocalizedDescriptionKey, 
									  [upload remotePath], NSFilePathErrorKey, nil];
			NSError *error = [NSError errorWithDomain:CKFileConnectionErrorDomain code:kFileExists userInfo:userInfo];
			[upload retain];
			[self dequeueUpload];
			// send finished

			[[self client] uploadDidFinish:[upload remotePath] error:error];
			
            if ([upload delegateRespondsToTransferDidFinish])
				[[upload delegate] transferDidFinish:[upload userInfo] error:error];
			[upload release];
			[self setState:CKConnectionIdleState];			
			return;
		}
	}
	
	[fm removeItemAtPath:[upload remotePath] error:NULL];
	
	if ([upload delegateRespondsToTransferDidBegin])
		[[upload delegate] transferDidBegin:[upload userInfo]];

    [[self client] uploadDidBegin:[upload remotePath]];
	
	FILE *from = fopen([[upload localPath] fileSystemRepresentation], "r"); // Must use -fileSystemRepresentation to handle non-ASCII paths
	FILE *to = fopen([[upload remotePath] fileSystemRepresentation], "a");
	
	// I put these assertions back in; it's better to get an assertion failure than a crash!
	NSAssert(from, @"path from cannot be found");
	NSAssert(to, @"path to cannot be found");
	int fno = fileno(from), tno = fileno(to);
	char bytes[8096];
	int len;
	unsigned long long size = [[[fm attributesOfItemAtPath:[upload localPath] error:NULL] objectForKey:NSFileSize] unsignedLongLongValue];
	unsigned long long sizeDecrementing = size;

	clearerr(from);
	
	// feof() doesn;t seem to work for some reason so we'll just count the byte size of the file
	while (sizeDecrementing > 0) 
	{
		len = read(fno, bytes, 8096);
		len = write(tno, bytes, len);
		sizeDecrementing -= len;
	}
	
	fclose(from);
	fclose(to);
		
	//need to send the amount of bytes transferred.
	

    [[self client] upload:[upload remotePath] didSendDataOfLength:size];
    
	if ([upload delegateRespondsToTransferTransferredData])
		[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:size];
	
	// send 100%
	if ([upload delegateRespondsToTransferProgressedTo])
		[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:100]];

    [[self client] upload:[upload remotePath] didProgressToPercent:[NSNumber numberWithInt:100]];
	
	
	[upload retain];
	[self dequeueUpload];
	
	// send finished
	[[self client] uploadDidFinish:[upload remotePath] error:nil];
    
	if ([upload delegateRespondsToTransferDidFinish])
		[[upload delegate] transferDidFinish:[upload userInfo] error:nil];
	
	[upload release];
	[self setState:CKConnectionIdleState];
}

- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate
{
	NSAssert(localPath && ![localPath isEqualToString:@""], @"localPath is nil!");
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
	NSDictionary *attribs = [myFileManager attributesOfItemAtPath:localPath error:NULL];
	CKTransferRecord *rec = [CKTransferRecord recordWithName:remotePath size:[[attribs objectForKey:NSFileSize] unsignedLongLongValue]];
	CKInternalTransferRecord *upload = [CKInternalTransferRecord recordWithLocal:localPath
																			data:nil
																		  offset:0
																		  remote:remotePath
																		delegate:(delegate) ? delegate : rec
																		userInfo:rec];
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcUpload:checkRemoteExistence:)
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

- (void)fcUploadData:(CKInternalTransferRecord *)upload checkRemoteExistence:(NSNumber *)check
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
	(void) [myFileManager removeItemAtPath:[upload remotePath] error:NULL];
	BOOL success = [myFileManager createFileAtPath:[upload remotePath]
										  contents:[upload data]
										attributes:nil];

	if ([upload delegateRespondsToTransferDidBegin])
		[[upload delegate] transferDidBegin:[upload userInfo]];

    [[self client] uploadDidBegin:[upload remotePath]];
    
	//need to send the amount of bytes transferred.
	unsigned long long size = [[[myFileManager attributesOfItemAtPath:[upload remotePath] error:NULL] objectForKey:NSFileSize] unsignedLongLongValue];

    [[self client] upload:[upload remotePath] didSendDataOfLength:size];
    
	if ([upload delegateRespondsToTransferTransferredData])
		[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:size];
	// send 100%
	if ([upload delegateRespondsToTransferProgressedTo])
		[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:100]];

    [[self client] upload:[upload remotePath] didProgressToPercent:[NSNumber numberWithInt:100]];
	
	NSError *error = nil;
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
	
	CKTransferRecord *rec = [CKTransferRecord recordWithName:remotePath
														size:[data length]];
	CKInternalTransferRecord *upload = [CKInternalTransferRecord recordWithLocal:nil
																			data:data
																		  offset:0
																		  remote:remotePath
																		delegate:delegate ? delegate : rec
																		userInfo:rec];
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcUploadData:checkRemoteExistence:)
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

/*!	Copy the file to the given directory
*/
- (void)fcDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(NSNumber *)aFlag
{
	//BOOL flag = [aFlag boolValue];
	[self setCurrentOperation:kDownloadFile];
	
	CKInternalTransferRecord *download = [self currentDownload];
	
	NSString *name = [remotePath lastPathComponent];

    [[self client] downloadDidBegin:remotePath];
    
	if ([download delegateRespondsToTransferDidBegin])
		[[download delegate] transferDidBegin:[download userInfo]];
	
	if ([[remotePath componentsSeparatedByString:@"/"] count] == 1)
	{
		remotePath = [NSString stringWithFormat:@"%@/%@", [self currentDirectory], remotePath];
	}
	
	NSString *destinationPath = [NSString stringWithFormat:@"%@/%@", dirPath, name];
	NSString *tempPath = nil;
	if ([aFlag boolValue])
	{
		//we were asked to overwrite, we'll do it atomically because we are nice:-)
		//
		if ([myFileManager fileExistsAtPath: destinationPath])
		{
			tempPath = [dirPath stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
			
			if (![myFileManager moveItemAtPath:destinationPath
                                        toPath:tempPath
                                         error:NULL])
			{
				//we failed to move it, we'll fail to copy...
				//
				tempPath = nil;
			}
		}
  }
	
	BOOL success = [myFileManager copyItemAtPath:remotePath toPath: destinationPath error:NULL];
	if (success)
	{
		//we can delete the old file if one was present
		//
		if (tempPath)
			[myFileManager removeItemAtPath:tempPath error:NULL];

		//need to send the amount of bytes transferred.
		NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:remotePath];
        [[self client] download:remotePath didReceiveDataOfLength:[fh seekToEndOfFile]];
		
		[[self client] download:remotePath didProgressToPercent:[NSNumber numberWithInt:100]];
        
		if ([download delegateRespondsToTransferProgressedTo])
			[[download delegate] transfer:[download userInfo] progressedTo:[NSNumber numberWithInt:100]];
		
		[download retain];
		[self dequeueDownload];

        [[self client] downloadDidFinish:remotePath error:nil];
        
		if ([download delegateRespondsToTransferDidFinish])
			[[download delegate] transferDidFinish:[download userInfo] error:nil];
		[download release];
		
	}
	else	// no handler, so we send error message 'manually'
	{
		if (tempPath)
		{
			//restore the file, hopefully this will work:-)
			[myFileManager moveItemAtPath:tempPath toPath:destinationPath error:NULL];
		}
		
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  LocalizedStringInConnectionKitBundle(@"Unable to store data in file", @"FileConnection failed to copy file"), NSLocalizedDescriptionKey,
								  remotePath, NSFilePathErrorKey, nil];
		NSError *error = [NSError errorWithDomain:CKFileConnectionErrorDomain code:[self currentOperation] userInfo:userInfo];
		
		[download retain];
		[self dequeueDownload];

        [[self client] downloadDidFinish:remotePath error:error];
        
		if ([download delegateRespondsToTransferDidFinish])
			[[download delegate] transferDidFinish:[download userInfo] error:error];
		[download release];		
	}
	
	[self setState:CKConnectionIdleState];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDownloadFile:toDirectory:overwrite:)
													  target:self
												   arguments:[NSArray arrayWithObjects:remotePath, dirPath, [NSNumber numberWithBool:flag], nil]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionDownloadingFileState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (CKTransferRecord *)downloadFile:(NSString *)remotePath 
					   toDirectory:(NSString *)dirPath 
						 overwrite:(BOOL)flag
						  delegate:(id)delegate
{
	CKTransferRecord *record = [CKTransferRecord recordWithName:remotePath size:0];
	CKTransferRecord *download = [CKInternalTransferRecord recordWithLocal:[dirPath stringByAppendingPathComponent:[remotePath lastPathComponent]]
																	  data:nil
																	offset:0
																	remote:remotePath
																  delegate:(delegate) ? delegate : record
																  userInfo:record];
	[self queueDownload:download];
	[self downloadFile:remotePath toDirectory:dirPath overwrite:flag];
	return record;
}

- (void)directoryContents
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDirectoryContents)
													  target:self
												   arguments:[NSArray array]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)fcContentsOfDirectory:(NSString *)dirPath
{
	[self setCurrentOperation:kDirectoryContents];
	
	NSArray *array = [myFileManager contentsOfDirectoryAtPath:dirPath error:NULL];
	NSMutableArray *packaged = [NSMutableArray arrayWithCapacity:[array count]];
	NSEnumerator *e = [array objectEnumerator];
	NSString *cur;
	
	while (cur = [e nextObject]) {
		NSString *file = [NSString stringWithFormat:@"%@/%@", dirPath, cur];
		NSMutableDictionary *attribs = [NSMutableDictionary dictionaryWithDictionary:[myFileManager attributesOfItemAtPath:file
                                                                                                                     error:NULL]];
		[attribs setObject:cur forKey:cxFilenameKey];
		if ([[attribs objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
			NSString *target = [file stringByResolvingSymlinksInPath];
			BOOL isDir;
			[myFileManager fileExistsAtPath:target isDirectory:&isDir];
			if (isDir && ![target hasSuffix:@"/"])
			{
				target = [target stringByAppendingString:@"/"];
			}
			[attribs setObject:target forKey:cxSymbolicLinkTargetKey];
		}
		
		[packaged addObject:attribs];
	}
	
	[[self client] connectionDidReceiveContents:packaged ofDirectory:dirPath error:nil];
    
	[self setState:CKConnectionIdleState];
}

- (void)fcDirectoryContents
{
	[self fcContentsOfDirectory:[self currentDirectory]];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcContentsOfDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObject:dirPath]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)fcCheckExistenceOfPath:(NSString *)path
{
  
	[self setCurrentOperation:kDirectoryContents];
	
	BOOL fileExists = [myFileManager fileExistsAtPath: path];
  

	[[self client] connectionDidCheckExistenceOfPath:path pathExists:fileExists error:nil];
}

- (void)checkExistenceOfPath:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"path not specified");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcCheckExistenceOfPath:)
                                                    target:self
                                                 arguments:[NSArray arrayWithObject:path]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionCheckingFileExistenceState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)threadedRecursivelyDownload:(NSDictionary *)ui
{
	CKTransferRecord *root = [ui objectForKey:@"record"];
	NSString *remotePath = [ui objectForKey:@"remote"];
	NSString *localPath = [ui objectForKey:@"local"];
	BOOL flag = [[ui objectForKey:@"overwrite"] boolValue];
	NSEnumerator *e = [[myFileManager subpathsAtPath:remotePath] objectEnumerator];
	NSString *cur;
	BOOL isDir;
	
	while ((cur = [e nextObject]))
	{
		NSString *r = [remotePath stringByAppendingPathComponent:cur];
		NSString *l = [localPath stringByAppendingPathComponent:cur];
		if ([myFileManager fileExistsAtPath:r isDirectory:&isDir] && isDir)
		{
			[myFileManager createDirectoryAtPath:r withIntermediateDirectories:YES attributes:nil error:NULL];
		}
		else
		{
			CKTransferRecord *rec = [self downloadFile:r toDirectory:[l stringByDeletingLastPathComponent] overwrite:flag delegate:nil];
			[CKTransferRecord mergeTextPathRecord:rec withRoot:root];
		}
	}	
	[self setState:CKConnectionIdleState];
}

- (CKTransferRecord *)recursivelyDownload:(NSString *)remotePath
									   to:(NSString *)localPath
								overwrite:(BOOL)flag
{
	CKTransferRecord *root = [CKTransferRecord rootRecordWithPath:remotePath];
	NSDictionary *ui = [NSDictionary dictionaryWithObjectsAndKeys:root, @"record", remotePath, @"remote", localPath, @"local", [NSNumber numberWithBool:flag], @"overwrite", nil];
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(threadedRecursivelyDownload:)
													  target:self
												   arguments:[NSArray arrayWithObject:ui]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionDownloadingFileState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
	return root;
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

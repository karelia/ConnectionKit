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

#import "FileConnection.h"
#import "RunLoopForwarder.h"
#import "InterThreadMessaging.h"
#import "ConnectionThreadManager.h"
#import "CKInternalTransferRecord.h"
#import "CKTransferRecord.h"
#import "AbstractQueueConnection.h"
#import "NSFileManager+Connection.h"
#import "AbstractConnectionProtocol.h"

NSString *FileConnectionErrorDomain = @"FileConnectionErrorDomain";

enum { CONNECT = 4000, COMMAND, ABORT, CANCEL_ALL, DISCONNECT, FORCE_DISCONNECT, KILL_THREAD };		// port messages

@interface FileConnection (Private)
- (void)processInvocations;
- (void)fcUploadFile:(NSString *)f toFile:(NSString *)t;
- (void)sendPortMessage:(int)message;
- (void)fcUpload:(CKInternalTransferRecord *)upload
checkRemoteExistence:(NSNumber *)check;
@end

@implementation FileConnection

+ (void)load	// registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"0", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"file://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[FileConnection class] forTypes:[NSArray arrayWithObjects:port, url, nil]];
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
+ (FileConnection *)connection
{
	FileConnection *c = [[FileConnection alloc] init];
	return [c autorelease];
}

- (id)init
{
	[self initWithHost:LocalizedStringInConnectionKitBundle(@"the File System", @"name of a host to connect to; in this case, the local file system rather than a remote server") port:@"ignored" username:@"ignored" password:@"ignored" error:nil];
	return self;
}

+ (NSString *)name
{
	return @"File";
}

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
{
	FileConnection *c = [[FileConnection alloc] initWithHost:host
														port:port
													username:username
													password:password
													   error:nil];
	return [c autorelease];
}

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
				 error:(NSError **)error
{
	FileConnection *c = [[FileConnection alloc] initWithHost:host
														port:port
													username:username
													password:password
													   error:error];
	return [c autorelease];
}

/*!	Designated Initilizer
*/
- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
			 error:(NSError **)error
{
	port = @"0";
	
	if (self = [super initWithHost:host port:port username:username password:password error:error])
	{
		myCurrentDirectory = [[NSString alloc] initWithString:NSHomeDirectory()];
	}
	return self;
}

- (void)dealloc
{
	[myCurrentDirectory release];
	[super dealloc];
}

+ (NSString *)urlScheme
{
	return @"file";
}

- (void)connect
{
	if ([self transcript])
	{
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:LocalizedStringInConnectionKitBundle(@"Connecting...\n", @"file transcript")
																  attributes:[AbstractConnection sentAttributes]] autorelease]];
	}
	[super connect];
}

- (void)sendCommand:(id)command
{
	[command invoke];
}

- (void)threadedConnect
{
	[super threadedConnect];
	if (_flags.didAuthenticate)
	{
		[_forwarder connection:self didAuthenticateToHost:[self host] error:nil];
	}
	myFileManager = [[NSFileManager alloc] init];
	if ([self transcript])
	{
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:LocalizedStringInConnectionKitBundle(@"Connected to File System\n", @"file transcript") 
																  attributes:[AbstractConnection sentAttributes]] autorelease]];
	}
	[self setState:ConnectionIdleState];
}

- (void)threadedAbort
{
	if (_flags.cancel)
	{
		[_forwarder connectionDidCancelTransfer:self];
	}
	if (_flags.didCancel)
	{
		NSString *remotePath = [self currentUpload] ? [[self currentUpload] remotePath] : [[self currentDownload] remotePath];
		[_forwarder connection:self didCancelTransfer:remotePath];
	}
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
		
	BOOL success = [myFileManager changeCurrentDirectoryPath:aDirectory];
	if (success && _flags.changeDirectory)
	{
		[_forwarder connection:self didChangeToDirectory:aDirectory error:nil];
	}
	
	[myCurrentDirectory autorelease];
	myCurrentDirectory = [aDirectory copy];
	[self setState:ConnectionIdleState];
}

- (void)changeToDirectory:(NSString *)aDirectory	// an absolute directory
{
	NSAssert(aDirectory && ![aDirectory isEqualToString:@""], @"no directory specified");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcChangeToDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObjects:aDirectory, nil]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionChangedDirectoryState
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
	
	if ([self transcript])
	{
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Create Directory %@ (%lo)\n", @"file transcript"), aName, aPermissions] 
																  attributes:[AbstractConnection sentAttributes]] autorelease]];
	}
	
	NSDictionary *fmDictionary = nil;
	if (0 != aPermissions)
	{
		fmDictionary = [NSDictionary dictionaryWithObject:[NSNumber numberWithLong:aPermissions] forKey:NSFilePosixPermissions];
	}
	
	NSError *error = nil;	
	if (![myFileManager createDirectoryAtPath:aName attributes:fmDictionary])
	{
		BOOL exists;
		[myFileManager fileExistsAtPath:aName isDirectory:&exists];
		NSDictionary *ui = [NSDictionary dictionaryWithObjectsAndKeys:
							LocalizedStringInConnectionKitBundle(@"Could not create directory", @"FileConnection create directory error"), NSLocalizedDescriptionKey,
							aName, NSFilePathErrorKey,
							[NSNumber numberWithBool:exists], ConnectionDirectoryExistsKey,
							aName, ConnectionDirectoryExistsFilenameKey, nil];		
		error = [NSError errorWithDomain:FileConnectionErrorDomain code:[self currentOperation] userInfo:ui];
	}
	
	if (_flags.createDirectory)
		[_forwarder connection:self didCreateDirectory:aName error:error];

	[self setState:ConnectionIdleState];
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)aPermissions
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no directory specified");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcCreateDirectory:permissions:)
													  target:self
												   arguments:[NSArray arrayWithObjects:dirPath, [NSNumber numberWithUnsignedLong:aPermissions], nil]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionCreateDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)fcSetPermissions:(NSNumber *)perms forFile:(NSString *)path
{
	[self setCurrentOperation:kSetPermissions];
	
	NSMutableDictionary *attribs = [[myFileManager fileAttributesAtPath:path traverseLink:NO] mutableCopy];
	[attribs setObject:perms forKey:NSFilePosixPermissions];
	
	NSError *error = nil;
	if (![myFileManager changeFileAttributes:attribs atPath:path])
	{
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  LocalizedStringInConnectionKitBundle(@"Could not change file permissions", @"FileConnection set permissions error"), NSLocalizedDescriptionKey,
								  path, NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:FileConnectionErrorDomain code:[self currentOperation] userInfo:userInfo];		
	}
	
	if (_flags.permissions)
		[_forwarder connection:self didSetPermissionsForFile:path error:error];

	[attribs release];
	[self setState:ConnectionIdleState];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"no file/path specified");
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcSetPermissions:forFile:)
													  target:self
												   arguments:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedLong:permissions], path, nil]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionSettingPermissionsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)fcRename:(NSString *)fromPath to:(NSString *)toPath
{
	[self setCurrentOperation:kRename];
	
	if ([self transcript])
	{
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Renaming %@ to %@\n", @"file transcript"), fromPath, toPath] 
																  attributes:[AbstractConnection sentAttributes]] autorelease]];
	}
	
	NSError *error = nil;	
	if (![myFileManager movePath:fromPath toPath:toPath handler:self])
	{
		NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Failed to rename file.", @"Failed to rename file.");
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:localizedDescription, NSLocalizedDescriptionKey, nil];
		error = [NSError errorWithDomain:FileConnectionErrorDomain code:[self currentOperation] userInfo:userInfo];
	}
	
	if (_flags.rename)
		[_forwarder connection:self didRename:fromPath to:toPath error:error];

	[self setState:ConnectionIdleState];
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSAssert(fromPath && ![fromPath isEqualToString:@""], @"fromPath is nil!");
    NSAssert(toPath && ![toPath isEqualToString:@""], @"toPath is nil!");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcRename:to:)
													  target:self
												   arguments:[NSArray arrayWithObjects:fromPath, toPath, nil]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionAwaitingRenameState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)fcDeleteFile:(NSString *)path
{
	[self setCurrentOperation:kDeleteFile];
	
	if ([self transcript])
	{
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Deleting File %@\n", @"file transcript"), path] 
																  attributes:[AbstractConnection sentAttributes]] autorelease]];
	}
	
	NSError *error = nil;	
	if (![myFileManager removeFileAtPath:path handler:self])
	{
		NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Failed to delete file: %@", @"error for deleting a file"), path];
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  localizedDescription, NSLocalizedDescriptionKey, 
								  path, NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:FileConnectionErrorDomain code:kDeleteFile userInfo:userInfo];		
	}
	
	if (_flags.deleteFile)
		[_forwarder connection:self didDeleteFile:path error:error];
	
	[self setState:ConnectionIdleState];
}

- (void)deleteFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"path is nil!");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDeleteFile:)
													  target:self 
												   arguments:[NSArray arrayWithObject:path]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionDeleteFileState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)fcDeleteDirectory:(NSString *)dirPath
{
	[self setCurrentOperation:kDeleteDirectory];
	
	NSError *error = nil;
	if (![myFileManager removeFileAtPath:dirPath handler:self])
	{
		NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Failed to delete directory: %@", @"error for deleting a directory"), dirPath];
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  localizedDescription, NSLocalizedDescriptionKey,
								  dirPath, NSFilePathErrorKey, nil];
		error = [NSError errorWithDomain:FileConnectionErrorDomain code:kDeleteFile userInfo:userInfo];
	}
	
	if (_flags.deleteDirectory)
		[_forwarder connection:self didDeleteDirectory:dirPath error:error];

	[self setState:ConnectionIdleState];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"dirPath is nil!");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDeleteDirectory:)
													  target:self 
												   arguments:[NSArray arrayWithObject:dirPath]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionDeleteDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)recursivelyDeleteDirectory:(NSString *)path
{
	[self deleteDirectory:path];
}

- (void)uploadFile:(NSString *)localPath
{
	[self uploadFile:localPath toFile:[localPath lastPathComponent]];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{	
	[self uploadFile:localPath toFile:remotePath checkRemoteExistence:NO delegate:nil];
}

- (void)fcUpload:(CKInternalTransferRecord *)upload checkRemoteExistence:(NSNumber *)check
{
	NSFileManager *fm = myFileManager;
	BOOL flag = [check boolValue];
	
	if ([self transcript])
	{
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Copying %@ to %@\n", @"file transcript"), [upload localPath], [upload remotePath]] 
																  attributes:[AbstractConnection sentAttributes]] autorelease]];
	}
		
	if (flag)
	{
		if ([fm fileExistsAtPath:[upload remotePath]])
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File Already Exists", @"FileConnection error"), NSLocalizedDescriptionKey, 
									  [upload remotePath], NSFilePathErrorKey, nil];
			NSError *error = [NSError errorWithDomain:FileConnectionErrorDomain code:kFileExists userInfo:userInfo];
			[upload retain];
			[self dequeueUpload];
			// send finished
			if ( _flags.uploadFinished)
				[_forwarder connection:self uploadDidFinish:[upload remotePath] error:error];
			if ([upload delegateRespondsToTransferDidFinish])
				[[upload delegate] transferDidFinish:[upload userInfo] error:error];
			[upload release];
			[self setState:ConnectionIdleState];			
			return;
		}
	}
	
	[fm removeFileAtPath:[upload remotePath] handler:nil];
	
	if ([upload delegateRespondsToTransferDidBegin])
		[[upload delegate] transferDidBegin:[upload userInfo]];
	if (_flags.didBeginUpload)
		[_forwarder connection:self uploadDidBegin:[upload remotePath]];
	
	FILE *from = fopen([[upload localPath] fileSystemRepresentation], "r"); // Must use -fileSystemRepresentation to handle non-ASCII paths
	FILE *to = fopen([[upload remotePath] fileSystemRepresentation], "a");
	
	// I put these assertions back in; it's better to get an assertion failure than a crash!
	NSAssert(from, @"path from cannot be found");
	NSAssert(to, @"path to cannot be found");
	int fno = fileno(from), tno = fileno(to);
	char bytes[8096];
	int len;
	unsigned long long size = [[[fm fileAttributesAtPath:[upload localPath] traverseLink:YES] objectForKey:NSFileSize] unsignedLongLongValue];
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
	
	if (_flags.uploadProgressed)
		[_forwarder connection:self upload:[upload remotePath] sentDataOfLength:size];
	if ([upload delegateRespondsToTransferTransferredData])
		[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:size];
	
	// send 100%
	if ([upload delegateRespondsToTransferProgressedTo])
		[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:100]];
	if (_flags.uploadPercent) 
		[_forwarder connection:self upload:[upload remotePath] progressedTo:[NSNumber numberWithInt:100]];
	
	
	[upload retain];
	[self dequeueUpload];
	
	// send finished
	if ( _flags.uploadFinished)
		[_forwarder connection:self uploadDidFinish:[upload remotePath] error:nil];
	if ([upload delegateRespondsToTransferDidFinish])
		[[upload delegate] transferDidFinish:[upload userInfo] error:nil];
	
	[upload release];
	[self setState:ConnectionIdleState];
}

- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate
{
	NSAssert(localPath && ![localPath isEqualToString:@""], @"localPath is nil!");
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
	NSDictionary *attribs = [myFileManager fileAttributesAtPath:localPath traverseLink:YES];
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
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	[self queueUpload:upload];
	[self queueCommand:cmd];
	return rec;
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(unsigned long long)offset
{
	// Noop, there's no such thing as a partial transfer on a file system since it's instantaneous.
	[self uploadFile:localPath];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	[self uploadFromData:data toFile:remotePath checkRemoteExistence:NO delegate:nil];
}

- (void)fcUploadData:(CKInternalTransferRecord *)upload checkRemoteExistence:(NSNumber *)check
{
	BOOL flag = [check boolValue];
	
	if ([self transcript])
	{
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Writing data to %@\n", @"file transcript"), [upload remotePath]] 
																  attributes:[AbstractConnection sentAttributes]] autorelease]];
	}
	
	if (flag)
	{
		if ([myFileManager fileExistsAtPath:[upload remotePath]])
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File Already Exists", @"FileConnection error"), NSLocalizedDescriptionKey, 
									  [upload remotePath], NSFilePathErrorKey, nil];
			NSError *error = [NSError errorWithDomain:FileConnectionErrorDomain code:kFileExists userInfo:userInfo];
			
			// send finished
			if (_flags.uploadFinished)
				[_forwarder connection:self uploadDidFinish:[upload remotePath] error:error];
			if ([upload delegateRespondsToTransferDidFinish])
				[[upload delegate] transferDidFinish:[upload userInfo] error:error];			
			return;
		}
	}
	(void) [myFileManager removeFileAtPath:[upload remotePath] handler:nil];
	BOOL success = [myFileManager createFileAtPath:[upload remotePath]
										  contents:[upload data]
										attributes:nil];

	if ([upload delegateRespondsToTransferDidBegin])
		[[upload delegate] transferDidBegin:[upload userInfo]];
	if (_flags.didBeginUpload)
		[_forwarder connection:self uploadDidBegin:[upload remotePath]];
	//need to send the amount of bytes transferred.
	unsigned long long size = [[[myFileManager fileAttributesAtPath:[upload remotePath] traverseLink:YES] objectForKey:NSFileSize] unsignedLongLongValue];
	if (_flags.uploadProgressed)
		[_forwarder connection:self upload:[upload remotePath] sentDataOfLength:size];
	if ([upload delegateRespondsToTransferTransferredData])
		[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:size];
	// send 100%
	if ([upload delegateRespondsToTransferProgressedTo])
		[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:100]];
	if (_flags.uploadPercent) 
		[_forwarder connection:self upload:[upload remotePath] progressedTo:[NSNumber numberWithInt:100]];
	
	NSError *error = nil;
	if (!success)
	{
		 NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								   LocalizedStringInConnectionKitBundle(@"Failed to upload data", @"FileConnection copy data error"), NSLocalizedDescriptionKey,
								   [upload remotePath], NSFilePathErrorKey,nil];
		 error = [NSError errorWithDomain:ConnectionErrorDomain code:ConnectionErrorUploading userInfo:userInfo];
	}
	
	// send finished
	if (_flags.uploadFinished)
		[_forwarder connection:self uploadDidFinish:[upload remotePath] error:error];
	if ([upload delegateRespondsToTransferDidFinish])
		[[upload delegate] transferDidFinish:[upload userInfo] error:error];

	[self setState:ConnectionIdleState];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	[self uploadFromData:data toFile:remotePath checkRemoteExistence:flag delegate:nil];
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
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
	return rec;
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	// Noop, there's no such thing as a partial transfer on a file system since it's instantaneous.
	[self uploadFromData:data toFile:remotePath];
}

/*!	Copy the file to the given directory
*/
- (void)fcDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(NSNumber *)aFlag
{
	//BOOL flag = [aFlag boolValue];
	[self setCurrentOperation:kDownloadFile];
	
	CKInternalTransferRecord *download = [self currentDownload];
	
	NSString *name = [remotePath lastPathComponent];
	if (_flags.didBeginDownload)
		[_forwarder connection:self downloadDidBegin: remotePath];
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
			
			if (![myFileManager movePath: destinationPath
												   toPath: tempPath
												  handler: nil])
			{
				//we failed to move it, we'll fail to copy...
				//
				tempPath = nil;
			}
		}
  }
	
	BOOL success = [myFileManager copyPath:remotePath toPath: destinationPath handler:self];
	if (success)
	{
		//we can delete the old file if one was present
		//
		if (tempPath)
			[myFileManager removeFileAtPath: tempPath handler: nil];

		//need to send the amount of bytes transferred.
		if (_flags.downloadProgressed)
		{
			NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:remotePath];
			[_forwarder connection:self download:remotePath receivedDataOfLength:[fh seekToEndOfFile]];
		} 
		
		if (_flags.downloadPercent)
			[_forwarder connection:self download:remotePath progressedTo:[NSNumber numberWithInt:100]];
		if ([download delegateRespondsToTransferProgressedTo])
			[[download delegate] transfer:[download userInfo] progressedTo:[NSNumber numberWithInt:100]];
		
		[download retain];
		[self dequeueDownload];
		if (_flags.downloadFinished)
			[_forwarder connection:self downloadDidFinish:remotePath error:nil];
		if ([download delegateRespondsToTransferDidFinish])
			[[download delegate] transferDidFinish:[download userInfo] error:nil];
		[download release];
		
	}
	else	// no handler, so we send error message 'manually'
	{
		if (tempPath)
		{
			//restore the file, hopefully this will work:-)
			[myFileManager movePath:tempPath toPath:destinationPath handler:nil];
		}
		
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  LocalizedStringInConnectionKitBundle(@"Unable to store data in file", @"FileConnection failed to copy file"), NSLocalizedDescriptionKey,
								  remotePath, NSFilePathErrorKey, nil];
		NSError *error = [NSError errorWithDomain:FileConnectionErrorDomain code:[self currentOperation] userInfo:userInfo];
		
		[download retain];
		[self dequeueDownload];
		if (_flags.downloadFinished)
			[_forwarder connection:self downloadDidFinish:remotePath error:error];
		if ([download delegateRespondsToTransferDidFinish])
			[[download delegate] transferDidFinish:[download userInfo] error:error];
		[download release];		
	}
	
	[self setState:ConnectionIdleState];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDownloadFile:toDirectory:overwrite:)
													  target:self
												   arguments:[NSArray arrayWithObjects:remotePath, dirPath, [NSNumber numberWithBool:flag], nil]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionDownloadingFileState
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

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(unsigned long long)offset
{
	// Noop, there's no such thing as a partial transfer on a file system since it's instantaneous.
	[self downloadFile:remotePath toDirectory:dirPath overwrite:YES];
}

- (void)directoryContents
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDirectoryContents)
													  target:self
												   arguments:[NSArray array]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)fcContentsOfDirectory:(NSString *)dirPath
{
	[self setCurrentOperation:kDirectoryContents];
	
	NSArray *array = [myFileManager directoryContentsAtPath:dirPath];
	NSMutableArray *packaged = [NSMutableArray arrayWithCapacity:[array count]];
	NSEnumerator *e = [array objectEnumerator];
	NSString *cur;
	
	while (cur = [e nextObject]) {
		NSString *file = [NSString stringWithFormat:@"%@/%@", dirPath, cur];
		NSMutableDictionary *attribs = [NSMutableDictionary dictionaryWithDictionary:[myFileManager fileAttributesAtPath:file
																								 traverseLink:NO]];
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
	if (_flags.directoryContents)
	{
		[_forwarder connection:self didReceiveContents:packaged ofDirectory:dirPath error:nil];
	}
	[self setState:ConnectionIdleState];
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
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)fcCheckExistenceOfPath:(NSString *)path
{
  
	[self setCurrentOperation:kDirectoryContents];
	
	BOOL fileExists = [myFileManager fileExistsAtPath: path];
  

	if (_flags.fileCheck)
	{
		[_forwarder connection:self checkedExistenceOfPath:path pathExists:fileExists error:nil];
	}
}

- (void)checkExistenceOfPath:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"path not specified");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcCheckExistenceOfPath:)
                                                    target:self
                                                 arguments:[NSArray arrayWithObject:path]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionCheckingFileExistenceState
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
			[myFileManager recursivelyCreateDirectory:r attributes:nil];
		}
		else
		{
			CKTransferRecord *rec = [self downloadFile:r toDirectory:[l stringByDeletingLastPathComponent] overwrite:flag delegate:nil];
			[CKTransferRecord mergeTextPathRecord:rec withRoot:root];
		}
	}	
	[self setState:ConnectionIdleState];
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
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionDownloadingFileState
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
	NSString *error = [errorInfo objectForKey:@"Error"];

	if (_flags.error)
	{
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  error, NSLocalizedDescriptionKey,
								  path, NSFilePathErrorKey,
								  toPath, @"ToPath", nil]; // "ToPath" might be nil ... that's OK, it's at the end of the list
		NSError *error = [NSError errorWithDomain:FileConnectionErrorDomain code:[self currentOperation] userInfo:userInfo];
		[_forwarder connection:self didReceiveError:error];
	}
	return NO;
}

@end

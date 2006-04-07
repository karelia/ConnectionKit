/*
 
 FileConnection.m
 Marvel
 
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

NSString *FileConnectionErrorDomain = @"FileConnectionErrorDomain";

enum { CONNECT = 0, COMMAND, ABORT, CANCEL_ALL, DISCONNECT, FORCE_DISCONNECT, KILL_THREAD };		// port messages

@implementation FileConnection

+ (void)load
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
	[self initWithHost:@"the File System" port:@"ignored" username:@"ignored" password:@"ignored"];
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
													password:password];
	return [c autorelease];
}

/*!	Designated Initilizer
*/
- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
{
	if (self = [super initWithHost:host port:port username:username password:password])
	{
		myPendingInvocations = [[NSMutableArray array] retain];
		myCurrentDirectory = [[NSString alloc] initWithString:NSHomeDirectory()];
		
		myLock = [[NSLock alloc] init];
		myForwarder = [[RunLoopForwarder alloc] init];
		myPort = [[NSPort port] retain];
		[myPort setDelegate:self];
		
		[NSThread prepareForInterThreadMessages];
		[NSThread detachNewThreadSelector:@selector(runFileConnectionBackgroundThread:) toTarget:self withObject:nil];
	}
	return self;
}

- (void)dealloc
{
	[self sendPortMessage:KILL_THREAD];
	[myPort setDelegate:nil];
	[myPort release];
	[myLock release];
	[myForwarder release];
	
	[myPendingInvocations release];
	[myCurrentDirectory release];
	[super dealloc];
}
#pragma mark -
#pragma mark Threading Support

- (void)runFileConnectionBackgroundThread:(id)notUsed
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	_bgThread = [NSThread currentThread];
	[NSThread prepareForInterThreadMessages];
	// NOTE: this may be leaking ... there are two retains going on here.  Apple bug report #2885852, still open after TWO YEARS!
	// But then again, we can't remove the thread, so it really doesn't mean much.
	[[NSRunLoop currentRunLoop] addPort:myPort forMode:(NSString *)kCFRunLoopCommonModes];
	[[NSRunLoop currentRunLoop] run];
	
	[pool release];
}

- (void)sendPortMessage:(int)aMessage
{
	if (nil != myPort)
	{
		NSPortMessage *message
		= [[NSPortMessage alloc] initWithSendPort:myPort
									  receivePort:myPort components:nil];
		[message setMsgid:aMessage];
		
		@try {
			BOOL sent = [message sendBeforeDate:[NSDate dateWithTimeIntervalSinceNow:15.0]];
			if (!sent)
			{
				if ([AbstractConnection debugEnabled])
					NSLog(@"FileConnection couldn't send message %d", aMessage);
			}
		} @catch (NSException *ex) {
			NSLog(@"%@", ex);
		} @finally {
			[message release];
		} 
	}
}

- (void)handlePortMessage:(NSPortMessage *)portMessage
{
	int message = [portMessage msgid];
	
	switch (message)
	{
		case CONNECT:
		{
			if ( _flags.didConnect )
			{
				[myForwarder connection:self didConnectToHost:_connectionHost];
			}
			_flags.isConnected = YES;
			break;
		}
		case COMMAND:
		{
			[self processInvocations];
			break;
		}
		case ABORT:
			if ( _flags.cancel )
			{
				[myForwarder connectionDidCancelTransfer:self];
			}
			[self processInvocations];
			break;
			
		case CANCEL_ALL:
			[myLock lock];
			[myPendingInvocations removeAllObjects];
			[myLock unlock];
			if ( _flags.cancel )
			{
				[myForwarder connectionDidCancelTransfer:self];
			}
			break;
		case FORCE_DISCONNECT:
		{
			[myLock lock];
			[myPendingInvocations removeAllObjects];
			[myLock unlock];
			if ( _flags.cancel )
			{
				[myForwarder connectionDidCancelTransfer:self];
			}
			_flags.isConnected = NO;
			if (_flags.didDisconnect)
			{
				[myForwarder connection:self didDisconnectFromHost:[self host]];
			}
		}
		break;
		case KILL_THREAD:
		{
			[[NSRunLoop currentRunLoop] removePort:myPort forMode:(NSString *)kCFRunLoopCommonModes];
			break;
		}
	}
}

- (void)setDelegate:(id)delegate
{
	[super setDelegate:delegate];
	[myForwarder setDelegate:delegate];
}

#pragma mark -
#pragma mark Invocation Queue

- (void)processInvocations
{
	NSAssert([NSThread currentThread] == _bgThread, @"Processing Invocations from wrong thread");
	
	[myLock lock];
    while ( (nil != myPendingInvocations) && ([myPendingInvocations count] > 0) )
	{
		NSInvocation *invocation = [myPendingInvocations objectAtIndex:0];
		if ( nil != invocation )
		{
			[invocation retain];
			[myPendingInvocations removeObjectAtIndex:0];
			[invocation invoke];
			[invocation release];
		}
	}
	[myLock unlock];
}

- (void)queueInvocation:(NSInvocation *)inv
{
	[myLock lock];
	[myPendingInvocations addObject:inv];
	[myLock unlock];
	[self sendPortMessage:COMMAND];
}

#pragma mark -
#pragma mark Main Methods

/*!	Basically a no-op, just send the completion method.
*/
- (void)connect
{
	[self sendPortMessage:CONNECT];
}

/*!	Basically a no-op, just send the completion method.
*/

- (void)fcDisconnect
{
	if (_flags.didDisconnect)
	{
		[myForwarder connection:self didDisconnectFromHost:[self host]];
	}
	_flags.isConnected = NO;
}

- (void)disconnect
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDisconnect)
													  target:self
												   arguments:[NSArray array]];
	[self queueInvocation:inv];
}

- (void)forceDisconnect
{
	[self sendPortMessage:FORCE_DISCONNECT];
}

- (void)fcChangeToDirectory:(NSString *)aDirectory
{
	[self setCurrentOperation:kChangeToDirectory];
	
	NSFileManager *fm = [NSFileManager defaultManager];
	
	BOOL success = [fm changeCurrentDirectoryPath:aDirectory];
	if (success && _flags.changeDirectory)
	{
		[_delegate connection:self didChangeToDirectory:aDirectory];
	}
	[myCurrentDirectory autorelease];
	myCurrentDirectory = [aDirectory copy];
}

- (void)changeToDirectory:(NSString *)aDirectory	// an absolute directory
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcChangeToDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObjects:aDirectory, nil]];
	[self queueInvocation:inv];
}

- (NSString *)currentDirectory
{
	return myCurrentDirectory;
}

- (void)createDirectory:(NSString *)aName
{
	[self createDirectory:aName permissions:0];
}

- (void)fcCreateDirectory:(NSString *)aName permissions:(NSNumber *)perms
{
	[self setCurrentOperation:kCreateDirectory];
	unsigned long aPermissions = [perms unsignedLongValue];
	
	NSDictionary *fmDictionary = nil;
	if (0 != aPermissions)
	{
		fmDictionary = [NSDictionary dictionaryWithObject:[NSNumber numberWithLong:aPermissions] forKey:NSFilePosixPermissions];
	}
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL success = [fm createDirectoryAtPath:aName attributes:fmDictionary];
	
	if (success)
	{
		if (_flags.createDirectory)
		{
			[_delegate connection:self didCreateDirectory:aName];
		}
	}
	else
	{
		if (_flags.error)
		{
			BOOL exists;
			[fm fileExistsAtPath:aName isDirectory:&exists];
			NSDictionary *ui = [NSDictionary dictionaryWithObjectsAndKeys:
				@"Could not create directory",
				NSLocalizedDescriptionKey,
				aName,
				NSFilePathErrorKey,
				[NSNumber numberWithBool:exists],
				ConnectionDirectoryExistsKey,
				aName,
				ConnectionDirectoryExistsFilenameKey,
				nil];
			[_delegate connection:self
				  didReceiveError:[NSError errorWithDomain:FileConnectionErrorDomain
													  code:[self currentOperation]
												  userInfo:ui]];
		}
	}
}

- (void)createDirectory:(NSString *)aName permissions:(unsigned long)aPermissions
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcCreateDirectory:permissions:)
													  target:self
												   arguments:[NSArray arrayWithObjects:aName, [NSNumber numberWithUnsignedLong:aPermissions], nil]];
	[self queueInvocation:inv];
}

- (void)fcSetPermissions:(NSNumber *)perms forFile:(NSString *)path
{
	[self setCurrentOperation:kSetPermissions];
	unsigned long permissions = [perms unsignedLongValue];
	
	NSFileManager *fm = [NSFileManager defaultManager];
	
	NSDictionary *attributes = [fm fileAttributesAtPath:path traverseLink:YES];	// TODO: verify link is OK
	
	NSMutableDictionary *newAttr = [NSMutableDictionary dictionaryWithDictionary:attributes];
	
	[newAttr setObject:[NSNumber numberWithUnsignedLong:permissions] forKey:NSFilePosixPermissions];
	BOOL success = [fm changeFileAttributes:newAttr atPath:path];
	
	if (success)
	{
		if (_flags.permissions)
		{
			[_delegate connection:self didSetPermissionsForFile:path];
		}
	}
	else
	{
		if (_flags.error)
		{
			[_delegate connection:self
				  didReceiveError:[NSError errorWithDomain:FileConnectionErrorDomain
													  code:[self currentOperation]
												  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
													  @"Could not change file permissions",
													  NSLocalizedDescriptionKey,
													  path,
													  NSFilePathErrorKey,
													  nil]]];
		}
	}
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcSetPermissions:forFile:)
													  target:self
												   arguments:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedLong:permissions], path, nil]];
	[self queueInvocation:inv];
}

- (void)fcRename:(NSString *)fromPath to:(NSString *)toPath
{
	[self setCurrentOperation:kRename];
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL success = [fm movePath:fromPath toPath:toPath handler:self];
	if (success && _flags.rename)
	{
		[_delegate connection:self didRename:fromPath to:toPath];
	}
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcRename:to:)
													  target:self
												   arguments:[NSArray arrayWithObjects:fromPath, toPath, nil]];
	[self queueInvocation:inv];
}

- (void)fcDeleteFile:(NSString *)path
{
	[self setCurrentOperation:kDeleteFile];
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL success = [fm removeFileAtPath:path handler:self];
	if (success && _flags.deleteFile)
	{
		[_delegate connection:self didDeleteFile:path];
	}
}

- (void)deleteFile:(NSString *)path
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDeleteFile:)
													  target:self 
												   arguments:[NSArray arrayWithObject:path]];
	[self queueInvocation:inv];
}

- (void)fcDeleteDirectory:(NSString *)dirPath
{
	[self setCurrentOperation:kDeleteDirectory];
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL success = [fm removeFileAtPath:dirPath handler:self];
	if (success && _flags.deleteDirectory)
	{
		[_delegate connection:self didDeleteDirectory:dirPath];
	}
}

- (void)deleteDirectory:(NSString *)dirPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDeleteDirectory:)
													  target:self 
												   arguments:[NSArray arrayWithObject:dirPath]];
	[self queueInvocation:inv];
}

/*!	Upload the given file to the working directory.
*/

- (void)fcUploadFile:(NSString *)localPath
{
	[self fcUploadFile:localPath toFile:[myCurrentDirectory stringByAppendingPathComponent:[localPath lastPathComponent]]];
}

- (void)uploadFile:(NSString *)localPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcUploadFile:)
													  target:self
												   arguments:[NSArray arrayWithObject:localPath]];
}

/*!	Copy the given file to the given directory
*/
- (void)fcUploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	[self setCurrentOperation:kUploadFile];
	NSFileManager *fm = [NSFileManager defaultManager];
	if (_flags.didBeginUpload)
	{
		[_delegate connection:self uploadDidBegin:remotePath];
	}
	BOOL success = [fm copyPath:localPath toPath:remotePath handler:self];
	//need to send the amount of bytes transferred.
	if (_flags.uploadProgressed) 
	{
		NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:localPath];
		[_delegate connection:self upload:remotePath sentDataOfLength:[fh seekToEndOfFile]];
	} 
	if (_flags.uploadPercent) 
	{
		[_delegate connection:self upload:remotePath progressedTo:[NSNumber numberWithInt:100]];
	}
	if (success && _flags.uploadFinished)
	{
		[_delegate connection:self uploadDidFinish:remotePath];
	}
	if (!success && _flags.error)
	{
		NSError *err = [NSError errorWithDomain:ConnectionErrorDomain 
										   code:ConnectionErrorUploading 
									   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:remotePath, @"upload", @"Failed to upload file", NSLocalizedDescriptionKey, nil]];
		[_delegate connection:self didReceiveError:err];
	}
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcUploadFile:toFile:)
													  target:self
												   arguments:[NSArray arrayWithObjects:localPath, remotePath, nil]];
	[self queueInvocation:inv];
}


- (void)resumeUploadFile:(NSString *)localPath fileOffset:(long long)offset
{
	// Noop, there's no such thing as a partial transfer on a file system since it's instantaneous.
	[self uploadFile:localPath];
}

- (void)fcUploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	[self setCurrentOperation:kUploadFromData];
	NSFileManager *fm = [NSFileManager defaultManager];
	if (_flags.didBeginUpload)
	{
		[_delegate connection:self uploadDidBegin:remotePath];
	}
	NSString *fullPath = [remotePath hasPrefix:@"/"] ? remotePath : [[fm currentDirectoryPath] stringByAppendingPathComponent:remotePath];
	BOOL success = [fm createFileAtPath:fullPath contents:data attributes:nil];
	//need to send the amount of bytes transferred.
	if (_flags.uploadProgressed) {
		[_delegate connection:self upload:remotePath sentDataOfLength:[data length]];
	} 
	if (_flags.uploadPercent) {
		[_delegate connection:self upload:remotePath progressedTo:[NSNumber numberWithInt:100]];
	}
	if (success && _flags.uploadFinished)
	{
		[_delegate connection:self uploadDidFinish:remotePath];
	}
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcUploadFromData:toFile:)
													  target:self
												   arguments:[NSArray arrayWithObjects:data, remotePath, nil]];
	[self queueInvocation:inv];
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(long long)offset
{
	// Noop, there's no such thing as a partial transfer on a file system since it's instantaneous.
	[self uploadFromData:data toFile:remotePath];
}

/*!	Copy the file to the given directory
*/
- (void)fcDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(NSNumber *)aFlag
{
	BOOL flag = [aFlag boolValue];
	[self setCurrentOperation:kDownloadFile];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *name = [remotePath lastPathComponent];
	if (_flags.didBeginDownload)
	{
		[_delegate connection:self downloadDidBegin:name];
	}
	if ([[remotePath componentsSeparatedByString:@"/"] count] == 1) {
		remotePath = [NSString stringWithFormat:@"%@/%@", [self currentDirectory], remotePath];
	}
	BOOL success = [fm copyPath:remotePath toPath:[NSString stringWithFormat:@"%@/%@", dirPath, name] handler:self];
	if (success)
	{
		//need to send the amount of bytes transferred.
		if (_flags.downloadProgressed) {
			NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:remotePath];
			[_delegate connection:self download:remotePath receivedDataOfLength:[fh seekToEndOfFile]];
		} 
		if (_flags.downloadPercent) {
			[_delegate connection:self download:remotePath progressedTo:[NSNumber numberWithInt:100]];
		}
		if (_flags.downloadFinished)
		{
			[_delegate connection:self downloadDidFinish:name];
		}
	}
	else	// no handler, so we send error message 'manually'
	{
		if (_flags.error)
		{
			[_delegate connection:self
				   didReceiveError:[NSError errorWithDomain:FileConnectionErrorDomain
													   code:[self currentOperation]
												   userInfo:
					   [NSDictionary dictionaryWithObjectsAndKeys:
						   @"Unable to store data in file",
						   NSLocalizedDescriptionKey,
						   remotePath,
						   NSFilePathErrorKey,
						   nil] ]];
		}

	}
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDownloadFile:toDirectory:overwrite:)
													  target:self
												   arguments:[NSArray arrayWithObjects:remotePath, dirPath, [NSNumber numberWithBool:flag], nil]];
	[self queueInvocation:inv];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(long long)offset
{
	// Noop, there's no such thing as a partial transfer on a file system since it's instantaneous.
	[self downloadFile:remotePath toDirectory:dirPath overwrite:YES];
}

- (void)cancelTransfer
{
	[self sendPortMessage:ABORT];
}

- (void)cancelAll
{
	[self sendPortMessage:CANCEL_ALL];
}

- (void)fcDirectoryContents
{
	[self setCurrentOperation:kDirectoryContents];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSArray *array = [fm directoryContentsAtPath:myCurrentDirectory];
	NSMutableArray *packaged = [NSMutableArray arrayWithCapacity:[array count]];
	NSEnumerator *e = [array objectEnumerator];
	NSString *cur;
	
	while (cur = [e nextObject]) {
		NSString *file = [NSString stringWithFormat:@"%@/%@", myCurrentDirectory, cur];
		NSMutableDictionary *attribs = [NSMutableDictionary dictionaryWithDictionary:[fm fileAttributesAtPath:file
																								 traverseLink:NO]];
		[attribs setObject:cur forKey:cxFilenameKey];
		if ([[attribs objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
			NSString *target = [file stringByResolvingSymlinksInPath];
			[attribs setObject:target forKey:cxSymbolicLinkTargetKey];
		}
			
		[packaged addObject:attribs];
	}
	
	if (_flags.directoryContents)
	{
		[_delegate connection:self didReceiveContents:packaged ofDirectory:[fm currentDirectoryPath]];
	}
}

- (void)directoryContents
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDirectoryContents)
													  target:self
												   arguments:[NSArray array]];
	[self queueInvocation:inv];
}

- (void)fcContentsOfDirectory:(NSString *)dirPath
{
	[self setCurrentOperation:kDirectoryContents];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *folder = [fm currentDirectoryPath];
	NSArray *array = [fm directoryContentsAtPath:folder];
	NSMutableArray *packaged = [NSMutableArray arrayWithCapacity:[array count]];
	NSEnumerator *e = [array objectEnumerator];
	NSString *cur;
	
	while (cur = [e nextObject]) {
		NSString *file = [NSString stringWithFormat:@"%@/%@", folder, cur];
		NSMutableDictionary *attribs = [NSMutableDictionary dictionaryWithDictionary:[fm fileAttributesAtPath:file
																								 traverseLink:NO]];
		[attribs setObject:cur forKey:cxFilenameKey];
		if ([[attribs objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
			NSString *target = [file stringByResolvingSymlinksInPath];
			[attribs setObject:target forKey:cxSymbolicLinkTargetKey];
		}
		
		[packaged addObject:attribs];
	}
	if (_flags.directoryContents)
	{
		[_delegate connection:self didReceiveContents:packaged ofDirectory:dirPath];
	}
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcContentsOfDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObject:dirPath]];
	[self queueInvocation:inv];
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
		[_delegate connection:self
			   didReceiveError:[NSError errorWithDomain:FileConnectionErrorDomain
												   code:[self currentOperation]
											   userInfo:
				   [NSDictionary dictionaryWithObjectsAndKeys:error,NSLocalizedDescriptionKey,
												   path, NSFilePathErrorKey, toPath, @"ToPath", nil]]];
		// "ToPath" might be nil ... that's OK, it's at the end of the list
	}
	return NO;
}

@end

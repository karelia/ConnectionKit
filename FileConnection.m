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
	[self initWithHost:@"the File System" port:@"ignored" username:@"ignored" password:@"ignored" error:nil];
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
	if (self = [super initWithHost:host port:port username:username password:password error:error])
	{
		myPendingInvocations = [[NSMutableArray array] retain];
		myCurrentDirectory = [[NSString alloc] initWithString:NSHomeDirectory()];
		myForwarder = [[RunLoopForwarder alloc] init];
		myLock = [[NSLock alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[myInflightInvocation release];
	[myForwarder release];
	[myLock release];
	[myPendingInvocations release];
	[myCurrentDirectory release];
	[super dealloc];
}

+ (NSString *)urlScheme
{
	return @"file";
}

- (void)threadedConnect
{
	myFileManager = [[NSFileManager alloc] init];
	if ( _flags.didConnect )
	{
		[myForwarder connection:self didConnectToHost:_connectionHost];
	}
	_flags.isConnected = YES;
}

- (void)threadedAbort
{
	if ( _flags.cancel )
	{
		[myForwarder connectionDidCancelTransfer:self];
	}
	[self processInvocations];
}

- (void)threadedCancelAll
{
	[myLock lock];
	[myPendingInvocations removeAllObjects];
	[myLock unlock];
	if ( _flags.cancel )
	{
		[myForwarder connectionDidCancelTransfer:self];
	}
}

- (void)threadedDisconnect
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

- (void)setDelegate:(id)delegate
{
	[super setDelegate:delegate];
	[myForwarder setDelegate:delegate];
}

#pragma mark -
#pragma mark Invocation Queue

- (void)processInvocations
{ 
	if ([self isConnected])
	{
		[myLock lock];
		KTLog(StateMachineDomain, KTLogDebug, @"Checking invocation queue");
		while ( (nil != myPendingInvocations) && ([myPendingInvocations count] > 0) && !myInflightInvocation)
		{
			myInflightInvocation = [myPendingInvocations objectAtIndex:0];
			if ( nil != myInflightInvocation )
			{
				[myInflightInvocation retain];
				[myPendingInvocations removeObjectAtIndex:0];
				KTLog(StateMachineDomain, KTLogDebug, @"Invoking %@", NSStringFromSelector([myInflightInvocation selector]));
				[myInflightInvocation invoke];
				[myInflightInvocation release];
				myInflightInvocation = nil;
			}
			[NSThread sleepUntilDate:[NSDate distantPast]];
		}
		[myLock unlock];
	}
}

- (void)queueInvocation:(NSInvocation *)inv
{
	[myLock lock];
	KTLog(QueueDomain, KTLogDebug, @"Queuing %@", NSStringFromSelector([inv selector]));
	[myPendingInvocations addObject:inv];
	[myLock unlock];
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processInvocations];
}

#pragma mark -
#pragma mark Main Methods

/*!	Basically a no-op, just send the completion method.
*/
- (void)connect
{
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedConnect];
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
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedDisconnect];
}

- (void)fcChangeToDirectory:(NSString *)aDirectory
{
	[self setCurrentOperation:kChangeToDirectory];
		
	BOOL success = [myFileManager changeCurrentDirectoryPath:aDirectory];
	if (success && _flags.changeDirectory)
	{
		[myForwarder connection:self didChangeToDirectory:aDirectory];
	}
	[myCurrentDirectory autorelease];
	myCurrentDirectory = [[myFileManager currentDirectoryPath] copy];
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
	BOOL success = [myFileManager createDirectoryAtPath:aName attributes:fmDictionary];
	
	if (success)
	{
		if (_flags.createDirectory)
		{
			[myForwarder connection:self didCreateDirectory:aName];
		}
	}
	else
	{
		if (_flags.error)
		{
			BOOL exists;
			[myFileManager fileExistsAtPath:aName isDirectory:&exists];
			NSDictionary *ui = [NSDictionary dictionaryWithObjectsAndKeys:
				LocalizedStringInThisBundle(@"Could not create directory", @"FileConnection create directory error"),
				NSLocalizedDescriptionKey,
				aName,
				NSFilePathErrorKey,
				[NSNumber numberWithBool:exists],
				ConnectionDirectoryExistsKey,
				aName,
				ConnectionDirectoryExistsFilenameKey,
				nil];
			[myForwarder connection:self
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
	
	NSTask *chmod = [[NSTask alloc] init];
	[chmod setLaunchPath:@"/bin/chmod"];
	[chmod setArguments:[NSArray arrayWithObjects:[NSString stringWithFormat:@"%lo", permissions], path, nil]];
	[chmod launch];
	while ([chmod isRunning])
	{
		[NSThread sleepUntilDate:[NSDate distantPast]];
	}
	
	BOOL success = [chmod terminationStatus] == 0;
	[chmod release];
	
	if (success)
	{
		if (_flags.permissions)
		{
			[myForwarder connection:self didSetPermissionsForFile:path];
		}
	}
	else
	{
		if (_flags.error)
		{
			[myForwarder connection:self
				  didReceiveError:[NSError errorWithDomain:FileConnectionErrorDomain
													  code:[self currentOperation]
												  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
													  LocalizedStringInThisBundle(@"Could not change file permissions", @"FileConnection set permissions error"),
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
	
	BOOL success = [myFileManager movePath:fromPath toPath:toPath handler:self];
	if (success && _flags.rename)
	{
		[myForwarder connection:self didRename:fromPath to:toPath];
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
	
	NSTask *rm = [[NSTask alloc] init];
	[rm setLaunchPath:@"/bin/rm"];
	[rm setArguments:[NSArray arrayWithObjects:@"-f", path, nil]];
	[rm launch];
	while ([rm isRunning])
	{
		[NSThread sleepUntilDate:[NSDate distantPast]];
	}
	
	BOOL success = [rm terminationStatus] == 0;
	if (success && _flags.deleteFile)
	{
		[myForwarder connection:self didDeleteFile:path];
	}
	[rm release];
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
	
	NSTask *rm = [[NSTask alloc] init];
	[rm setLaunchPath:@"/bin/rm"];
	[rm setArguments:[NSArray arrayWithObjects:@"-rf", dirPath, nil]];
	[rm launch];
	while ([rm isRunning])
	{
		[NSThread sleepUntilDate:[NSDate distantPast]];
	}
	
	BOOL success = [rm terminationStatus] == 0;
	if (success && _flags.deleteDirectory)
	{
		[myForwarder connection:self didDeleteDirectory:dirPath];
	}
	[rm release];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcDeleteDirectory:)
													  target:self 
												   arguments:[NSArray arrayWithObject:dirPath]];
	[self queueInvocation:inv];
}

- (void)recursivelyDeleteDirectory:(NSString *)path
{
	[self deleteDirectory:path];
}

/*!	Upload the given file to the working directory.
*/

- (void)fcUploadFile:(NSString *)localPath
{
	NSString *remotePath = [myCurrentDirectory stringByAppendingPathComponent:[localPath lastPathComponent]];
	CKInternalTransferRecord *rec = [CKInternalTransferRecord recordWithLocal:localPath
																		 data:nil
																	   offset:0
																	   remote:remotePath
																	 delegate:nil
																	 userInfo:nil];
	[self fcUpload:rec
		checkRemoteExistence:[NSNumber numberWithBool:NO]];
}

- (void)uploadFile:(NSString *)localPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcUploadFile:)
													  target:self
												   arguments:[NSArray arrayWithObject:localPath]];
	[self queueInvocation:inv];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	CKInternalTransferRecord *rec = [CKInternalTransferRecord recordWithLocal:localPath
																		 data:nil
																	   offset:0
																	   remote:remotePath
																	 delegate:nil
																	 userInfo:nil];
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcUpload:checkRemoteExistence:)
													  target:self
												   arguments:[NSArray arrayWithObjects:rec, [NSNumber numberWithBool:NO], nil]];
	[self queueInvocation:inv];
}

- (void)fcUpload:(CKInternalTransferRecord *)upload
checkRemoteExistence:(NSNumber *)check
{
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL flag = [check boolValue];
	
	if (flag)
	{
		if ([fm fileExistsAtPath:[upload remotePath]])
		{
			NSError *error = [NSError errorWithDomain:FileConnectionErrorDomain
												 code:kFileExists
											 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"File Already Exists", @"FileConnection error"), 
												 NSLocalizedDescriptionKey, 
												 [upload remotePath],
												 NSLocalizedFailureReasonErrorKey, nil]];
			if ([upload delegateRespondsToError])
			{
				[[upload delegate] transfer:[upload userInfo] receivedError:error];
			}
			if (_flags.error)
			{
				[_forwarder connection:self didReceiveError:error];
			}
			return;
		}
	}
	[fm removeFileAtPath:[upload remotePath] handler:nil];
	NSTask *cp = [[NSTask alloc] init];
	[cp setStandardError: [NSPipe pipe]]; //this will get the unit test to pass, else we get an error in the log, and since we already return an error...
	[cp setLaunchPath:@"/bin/cp"];
	[cp setArguments:[NSArray arrayWithObjects:@"-rf", [upload localPath], [upload remotePath], nil]];
	[cp setCurrentDirectoryPath:[self currentDirectory]];
	[cp launch];
	while ([cp isRunning])
	{
		[NSThread sleepUntilDate:[NSDate distantPast]];
	}
	BOOL success = YES;
	if ([cp terminationStatus] != 0)
	{
		success = NO;
	}
	[cp release];
	if ([upload delegateRespondsToTransferDidBegin])
	{
		[[upload delegate] transferDidBegin:[upload userInfo]];
	}
	if (_flags.didBeginUpload)
	{
		[myForwarder connection:self uploadDidBegin:[upload remotePath]];
	}
	//need to send the amount of bytes transferred.
	unsigned long long size = [[[fm fileAttributesAtPath:[upload localPath] traverseLink:YES] objectForKey:NSFileSize] unsignedLongLongValue];
	if (_flags.uploadProgressed)
	{
		[myForwarder connection:self upload:[upload remotePath] sentDataOfLength:size];
	}
	if ([upload delegateRespondsToTransferTransferredData])
	{
		[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:size];
	}
	// send 100%
	if ([upload delegateRespondsToTransferProgressedTo])
	{
		[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:100]];
	}
	if (_flags.uploadPercent) 
	{
		[myForwarder connection:self upload:[upload remotePath] progressedTo:[NSNumber numberWithInt:100]];
	}
	// send finishe
	if (success && _flags.uploadFinished)
	{
		[myForwarder connection:self uploadDidFinish:[upload remotePath]];
	}
	if (success && [upload delegateRespondsToTransferDidFinish])
	{
		[[upload delegate] transferDidFinish:[upload userInfo]];
	}
	if (!success)
	{
		NSError *err = [NSError errorWithDomain:ConnectionErrorDomain 
										   code:ConnectionErrorUploading 
									   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[upload remotePath], @"upload", LocalizedStringInThisBundle(@"Failed to upload file", @"FileConnection copy file error"), NSLocalizedDescriptionKey, nil]];
		if (_flags.error)
		{
			[myForwarder connection:self didReceiveError:err];
		}
		if ([upload delegateRespondsToError])
		{
			[[upload delegate] transfer:[upload userInfo] receivedError:err];
		}
	}
}

- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSDictionary *attribs = [fm fileAttributesAtPath:localPath traverseLink:YES];
	CKTransferRecord *rec = [CKTransferRecord recordWithName:remotePath size:[[attribs objectForKey:NSFileSize] unsignedLongLongValue]];
	CKInternalTransferRecord *upload = [CKInternalTransferRecord recordWithLocal:localPath
																			data:nil
																		  offset:0
																		  remote:remotePath
																		delegate:rec
																		userInfo:rec];
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcUpload:checkRemoteExistence:)
													  target:self
												   arguments:[NSArray arrayWithObjects:upload, [NSNumber numberWithBool:flag], nil]];
	[self queueInvocation:inv];
	return rec;
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(unsigned long long)offset
{
	// Noop, there's no such thing as a partial transfer on a file system since it's instantaneous.
	[self uploadFile:localPath];
}

- (void)fcUploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	[self setCurrentOperation:kUploadFromData];
	
	if (_flags.didBeginUpload)
	{
		[myForwarder connection:self uploadDidBegin:remotePath];
	}
	NSString *fullPath = [remotePath hasPrefix:@"/"] ? remotePath : [[myFileManager currentDirectoryPath] stringByAppendingPathComponent:remotePath];
	BOOL success = [myFileManager createFileAtPath:fullPath contents:data attributes:nil];
	
	//need to send the amount of bytes transferred.
	if (_flags.uploadProgressed) {
		[myForwarder connection:self upload:remotePath sentDataOfLength:[data length]];
	} 
	if (_flags.uploadPercent) {
		[myForwarder connection:self upload:remotePath progressedTo:[NSNumber numberWithInt:100]];
	}
	if (success && _flags.uploadFinished)
	{
		[myForwarder connection:self uploadDidFinish:remotePath];
	}
	if (!success && _flags.error)
	{
		NSError *err = [NSError errorWithDomain:ConnectionErrorDomain 
										   code:ConnectionErrorUploading 
									   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:remotePath, @"upload", LocalizedStringInThisBundle(@"Failed to upload data", @"FileConnection copy from data error"), NSLocalizedDescriptionKey, nil]];
		[myForwarder connection:self didReceiveError:err];
	}
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcUploadFromData:toFile:)
													  target:self
												   arguments:[NSArray arrayWithObjects:data, remotePath, nil]];
	[self queueInvocation:inv];
}

- (void)fcUploadData:(CKInternalTransferRecord *)upload checkRemoteExistence:(NSNumber *)check
{
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL flag = [check boolValue];
	
	if (flag)
	{
		if ([fm fileExistsAtPath:[upload remotePath]])
		{
			NSError *error = [NSError errorWithDomain:FileConnectionErrorDomain
												 code:kFileExists
											 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"File Already Exists", @"FileConnection error"), 
												 NSLocalizedDescriptionKey, 
												 [upload remotePath],
												 NSLocalizedFailureReasonErrorKey, nil]];
			if ([upload delegateRespondsToError])
			{
				[[upload delegate] transfer:[upload userInfo] receivedError:error];
			}
			if (_flags.error)
			{
				[_forwarder connection:self didReceiveError:error];
			}
			return;
		}
	}
	[fm removeFileAtPath:[upload remotePath] handler:nil];
	[fm createFileAtPath:[upload remotePath]
				contents:[upload data]
			  attributes:nil];
	if ([upload delegateRespondsToTransferDidBegin])
	{
		[[upload delegate] transferDidBegin:[upload userInfo]];
	}
	if (_flags.didBeginUpload)
	{
		[myForwarder connection:self uploadDidBegin:[upload remotePath]];
	}
	//need to send the amount of bytes transferred.
	unsigned long long size = [[[fm fileAttributesAtPath:[upload remotePath] traverseLink:YES] objectForKey:NSFileSize] unsignedLongLongValue];
	if (_flags.uploadProgressed)
	{
		[myForwarder connection:self upload:[upload remotePath] sentDataOfLength:size];
	}
	if ([upload delegateRespondsToTransferTransferredData])
	{
		[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:size];
	}
	// send 100%
	if ([upload delegateRespondsToTransferProgressedTo])
	{
		[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:100]];
	}
	if (_flags.uploadPercent) 
	{
		[myForwarder connection:self upload:[upload remotePath] progressedTo:[NSNumber numberWithInt:100]];
	}
	// send finished
	if (_flags.uploadFinished)
	{
		[myForwarder connection:self uploadDidFinish:[upload remotePath]];
	}
	if ([upload delegateRespondsToTransferDidFinish])
	{
		[[upload delegate] transferDidFinish:[upload userInfo]];
	}
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
	[self queueInvocation:inv];
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
	
	NSString *name = [remotePath lastPathComponent];
	if (_flags.didBeginDownload)
	{
		[myForwarder connection:self downloadDidBegin: remotePath];
	}
	if ([[remotePath componentsSeparatedByString:@"/"] count] == 1) {
		remotePath = [NSString stringWithFormat:@"%@/%@", [self currentDirectory], remotePath];
	}
  
  NSString *destinationPath = [NSString stringWithFormat:@"%@/%@", dirPath, name];
  NSString *tempPath = nil;
  if ([aFlag boolValue])
  {
    //we were asked to overwrite, we'll do it atomically because we are nice:-)
    //
    if ([[NSFileManager defaultManager] fileExistsAtPath: destinationPath])
    {
      tempPath = [dirPath stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]];
      
      if (![[NSFileManager defaultManager] movePath: destinationPath
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
		if (_flags.downloadProgressed) {
			NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:remotePath];
			[myForwarder connection:self download:remotePath receivedDataOfLength:[fh seekToEndOfFile]];
		} 
		if (_flags.downloadPercent) {
			[myForwarder connection:self download:remotePath progressedTo:[NSNumber numberWithInt:100]];
		}
		if (_flags.downloadFinished)
		{
			[myForwarder connection:self downloadDidFinish: remotePath];
		}
	}
	else	// no handler, so we send error message 'manually'
	{
    if (tempPath)
    {
      //restore the file, hopefully this will work:-)
      //
      [[NSFileManager defaultManager] movePath: tempPath
                                        toPath: destinationPath
                                       handler: nil];
    }
    
		if (_flags.error)
		{
			[myForwarder connection:self
				   didReceiveError:[NSError errorWithDomain:FileConnectionErrorDomain
													   code:[self currentOperation]
												   userInfo:
					   [NSDictionary dictionaryWithObjectsAndKeys:
						   LocalizedStringInThisBundle(@"Unable to store data in file", @"FileConnection failed to copy file"),
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

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(unsigned long long)offset
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
			[attribs setObject:target forKey:cxSymbolicLinkTargetKey];
		}
		
		[packaged addObject:attribs];
	}
	if (_flags.directoryContents)
	{
		[myForwarder connection:self didReceiveContents:packaged ofDirectory:dirPath];
	}
}

- (void)fcDirectoryContents
{
	[self fcContentsOfDirectory:[self currentDirectory]];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcContentsOfDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObject:dirPath]];
	[self queueInvocation:inv];
}

- (void)fcCheckExistenceOfPath:(NSString *)path
{
  
	[self setCurrentOperation:kDirectoryContents];
	
	BOOL fileExists = [myFileManager fileExistsAtPath: path];
  

	if (_flags.fileCheck)
	{
		[myForwarder connection: self 
		 checkedExistenceOfPath: path
					 pathExists: fileExists];
	}
}

- (void)checkExistenceOfPath:(NSString *)path
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(fcCheckExistenceOfPath:)
                                                    target:self
                                                 arguments:[NSArray arrayWithObject:path]];
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
		[myForwarder connection:self
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

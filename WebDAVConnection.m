/*
 Copyright (c) 2004-2006, Greg Hulands <ghulands@mac.com>
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

#import "WebDAVConnection.h"
#import "AbstractConnection.h"
#import "DAVDirectoryContentsRequest.h"
#import "DAVCreateDirectoryRequest.h"
#import "DAVUploadFileRequest.h"
#import "DAVDeleteRequest.h"
#import "DAVResponse.h"
#import "DAVDirectoryContentsResponse.h"
#import "DAVCreateDirectoryResponse.h"
#import "DAVUploadFileResponse.h"
#import "DAVDeleteResponse.h"
#import "NSData+Connection.h"
#import "CKHTTPFileDownloadRequest.h"
#import "CKHTTPFileDownloadResponse.h"
#import "CKInternalTransferRecord.h"
#import "CKTransferRecord.h"
#import "NSString+Connection.h"

NSString *WebDAVErrorDomain = @"WebDAVErrorDomain";

@implementation WebDAVConnection

#pragma mark class methods

+ (void)load	// registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"80", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"webdav://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[WebDAVConnection class] forTypes:[NSArray arrayWithObjects:port, url, nil]];
	[pool release];
}

+ (NSString *)name
{
	return @"WebDAV";
}

#pragma mark init methods

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
				 error:(NSError **)error
{
	WebDAVConnection *c = [[self alloc] initWithHost:host
                                                port:port
                                            username:username
                                            password:password
											   error:error];
	return [c autorelease];
}

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
			 error:(NSError **)error
{
	if (!username || [username length] == 0 || !password || [password length] == 0)
	{
		if (error)
		{
			NSError *err = [NSError errorWithDomain:WebDAVErrorDomain
											   code:ConnectionNoUsernameOrPassword
										   userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInConnectionKitBundle(@"Username and Password are required for WebDAV connections", @"No username or password")
																				forKey:NSLocalizedDescriptionKey]];
			*error = err;
		}
		[self release];
		return nil;
	}
	
	if (!port || [port isEqualToString:@""])
	{
		port = @"80";
	}
	
	if (self = [super initWithHost:host
                              port:port
                          username:username
                          password:password
							 error:error])
	{
		
	}
	return self;
}

- (void)dealloc
{
	[myCurrentDirectory release];
	[myDownloadHandle release];
	[super dealloc];
}

+ (NSString *)urlScheme
{
	return @"webdav";
}

#pragma mark -
#pragma mark Stream Overrides

- (void)processResponse:(CKHTTPResponse *)response
{
	KTLog(ProtocolDomain, KTLogDebug, @"%@", response);
	switch (GET_STATE)
	{
		case ConnectionAwaitingDirectoryContentsState:
		{
			DAVDirectoryContentsResponse *dav = (DAVDirectoryContentsResponse *)response;
			NSError *error = nil;
			NSString *localizedDescription = nil;
			NSArray *contents = [NSArray array];
			switch ([dav code])
			{
				case 200:
				case 207: //multi-status
				{
					contents = [dav directoryContents];
					[self cacheDirectory:[dav path] withContents:contents];
					break;
				}
				case 404:
				{		
					localizedDescription = [NSString stringWithFormat: @"%@: %@", LocalizedStringInConnectionKitBundle(@"There is no WebDAV access to the directory", @"No WebDAV access to the specified path"), [dav path]];
					break;
				}
				default: 
				{
					localizedDescription = LocalizedStringInConnectionKitBundle(@"Unknown Error Occurred", @"WebDAV Error");
					break;
				}
			}
			if (_flags.directoryContents)
			{
				if (localizedDescription)
				{
					NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
											  localizedDescription, NSLocalizedDescriptionKey,
											  [dav path], NSFilePathErrorKey,
											  [dav className], @"DAVResponseClass", nil];				
					error = [NSError errorWithDomain:WebDAVErrorDomain code:[dav code] userInfo:userInfo];
				}
				NSString *dirPath = [dav path];
				if ([dirPath hasSuffix:@"/"])
					dirPath = [dirPath substringToIndex:[dirPath length] - 1];				
				[_forwarder connection:self didReceiveContents:contents ofDirectory:dirPath error:error];
			}
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionCreateDirectoryState:
		{
			DAVCreateDirectoryResponse *dav = (DAVCreateDirectoryResponse *)response;
			NSError *error = nil;
			NSString *localizedDescription = nil;
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			
			switch ([dav code])
			{
				case 201: 
				{
					break; //No Error
				}					
				case 403:
				{		
					localizedDescription = LocalizedStringInConnectionKitBundle(@"The server does not allow the creation of directories at the current location", @"WebDAV Create Directory Error");
						//we fake the directory exists as this is usually the case if it is the root directory
					[userInfo setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
					break;
				}
				case 405:
				{		
					if (!_flags.isRecursiveUploading)
					{
						localizedDescription = LocalizedStringInConnectionKitBundle(@"The directory already exists", @"WebDAV Create Directory Error");
						[userInfo setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
					}
					break;
				}
				case 409:
				{
					localizedDescription = LocalizedStringInConnectionKitBundle(@"An intermediate directory does not exist and needs to be created before the current directory", @"WebDAV Create Directory Error");
					break;
				}
				case 415:
				{
					localizedDescription = LocalizedStringInConnectionKitBundle(@"The body of the request is not supported", @"WebDAV Create Directory Error");
					break;
				}
				case 507:
				{
					localizedDescription = LocalizedStringInConnectionKitBundle(@"Insufficient storage space available", @"WebDAV Create Directory Error");
					break;
				}
				default: 
				{
					localizedDescription = LocalizedStringInConnectionKitBundle(@"An unknown error occured", @"WebDAV Create Directory Error");
					break;
				}
			}
			if (_flags.createDirectory)
			{
				if (localizedDescription)
				{
					[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
					[userInfo setObject:[dav className] forKey:@"DAVResponseClass"];
					[userInfo setObject:[[dav request] description] forKey:@"DAVRequest"];
					[userInfo setObject:[(DAVCreateDirectoryRequest *)[dav request] path] forKey:NSFilePathErrorKey];
					error = [NSError errorWithDomain:WebDAVErrorDomain code:[dav code] userInfo:userInfo];
				}
				[_forwarder connection:self didCreateDirectory:[dav directory] error:error];
			}
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionUploadingFileState:
		{
			DAVUploadFileResponse *dav = (DAVUploadFileResponse *)response;
			bytesTransferred = 0;
			bytesToTransfer = 0;
			transferHeaderLength = 0;
			
			NSError *error = nil;
			
			switch ([dav code])
			{
				case 409:
				{		
					NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
											  LocalizedStringInConnectionKitBundle(@"Parent Folder does not exist", @"WebDAV Uploading Error"), NSLocalizedDescriptionKey,
											  [dav className], @"DAVResponseClass",
											  [[self currentUpload] remotePath], NSFilePathErrorKey, nil];
					error = [NSError errorWithDomain:WebDAVErrorDomain code:[dav code] userInfo:userInfo];
					break;
				}
				default:
					break;
			}
			
			CKInternalTransferRecord *upload = [[self currentUpload] retain];
			[self dequeueUpload];
			
			if (_flags.uploadFinished)
				[_forwarder connection:self uploadDidFinish:[upload remotePath] error:error];
			if ([upload delegateRespondsToTransferDidFinish])
				[[upload delegate] transferDidFinish:[upload delegate] error:error];
			
			[upload release];
			
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionDeleteFileState:
		{
			DAVDeleteResponse *dav = (DAVDeleteResponse *)response;
			NSError *error = nil;
			
			switch ([dav code])
			{
				case 200:
				case 201:
				case 204:
				{
					//No error
					break;
				}
				default:
				{
					NSString *localizedDescription = [NSString stringWithFormat:@"%@: %@", LocalizedStringInConnectionKitBundle(@"Failed to delete file", @"WebDAV File Deletion Error"), [self currentDeletion]]; 
					NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
											  localizedDescription, NSLocalizedDescriptionKey,
											  [self currentDeletion], NSFilePathErrorKey,
											  [[dav request] description], @"DAVRequest",
											  [dav className], @"DAVResponseClass", nil];
					error = [NSError errorWithDomain:WebDAVErrorDomain code:[dav code] userInfo:userInfo];
				}
			}
			NSString *deletionPath = [[self currentDeletion] retain];
			[self dequeueDeletion];
			
			if (_flags.deleteFile)
				[_forwarder connection:self didDeleteFile:deletionPath error:error];
			
			[deletionPath release];
			
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionDeleteDirectoryState:
		{
			DAVDeleteResponse *dav = (DAVDeleteResponse *)response;
			NSError *error = nil;
			
			switch ([dav code])
			{
				case 200:
				case 201:
				case 204:
				{
					break; //No error
				}
				default:
				{
					NSString *localizedDescription = [NSString stringWithFormat:@"%@: %@", LocalizedStringInConnectionKitBundle(@"Failed to delete directory", @"WebDAV Directory Deletion Error"), [self currentDeletion]];
					NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
											  localizedDescription, NSLocalizedDescriptionKey,
											  [self currentDeletion], NSFilePathErrorKey,
											  [[dav request] description], @"DAVRequest",
											  [dav className], @"DAVResponseClass", nil];
					error = [NSError errorWithDomain:WebDAVErrorDomain code:[dav code] userInfo:userInfo];
				}
			}
			
			NSString *deletionPath = [[self currentDeletion] retain];			
			[self dequeueDeletion];
			
			if (_flags.deleteDirectory)
				[_forwarder connection:self didDeleteDirectory:deletionPath error:error];
			
			[deletionPath release];
			
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionAwaitingRenameState:
		{
			if (_flags.rename)
				[_forwarder connection:self didRename:[_fileRenames objectAtIndex:0] to:[_fileRenames objectAtIndex:1] error:nil];
			[_fileRenames removeObjectAtIndex:0];
			[_fileRenames removeObjectAtIndex:0];
			[self setState:ConnectionIdleState];
			break;
		}
		default: break;
	}
}

- (void)initiatingNewRequest:(CKHTTPRequest *)req withPacket:(NSData *)packet
{
	// if we are uploading or downloading set up the transfer sizes
	if (GET_STATE == ConnectionUploadingFileState)
	{
		transferHeaderLength = [req headerLength];
		bytesToTransfer = [packet length] - transferHeaderLength;
		bytesTransferred = 0;
		CKInternalTransferRecord *upload = [self currentUpload];
		
		if (_flags.didBeginUpload)
		{
			[_forwarder connection:self
					uploadDidBegin:[upload remotePath]];
		}
		if ([upload delegateRespondsToTransferDidBegin])
		{
			[[upload delegate] transferDidBegin:[upload userInfo]];
		}
	}
	if (GET_STATE == ConnectionDownloadingFileState)
	{
		bytesToTransfer = 0;
		bytesTransferred = 0;
		CKInternalTransferRecord *download = [self currentDownload];
		
		if (_flags.didBeginDownload)
		{
			[_forwarder connection:self
				  downloadDidBegin:[download remotePath]];
		}
		if ([download delegateRespondsToTransferDidBegin])
		{
			[[download delegate] transferDidBegin:[download userInfo]];
		}
	}
}

- (BOOL)processBufferWithNewData:(NSData *)data
{
	if (GET_STATE == ConnectionDownloadingFileState)
	{
		CKInternalTransferRecord *download = [self currentDownload];
		if (bytesToTransfer == 0)
		{
			NSDictionary *headers = [DAVResponse headersWithData:myResponseBuffer];
			NSString *length = [headers objectForKey:@"Content-Length"];
			
			if (length)
			{
				NSScanner *scanner = [NSScanner scannerWithString:length];
				long long daBytes = 0;
				[scanner scanLongLong:&daBytes];
				bytesToTransfer = daBytes;
				
				[(CKTransferRecord *)[download userInfo] setSize:daBytes];
				
				NSFileManager *fm = [NSFileManager defaultManager];
				BOOL isDir;
				if ([fm fileExistsAtPath:[download localPath] isDirectory:&isDir] && !isDir)
				{
					[fm removeFileAtPath:[download localPath] handler:nil];
				}
				[fm createFileAtPath:[download localPath]
							contents:nil
						  attributes:nil];
				[myDownloadHandle release];
				myDownloadHandle = [[NSFileHandle fileHandleForWritingAtPath:[download localPath]] retain];
				
				// file data starts after the header
				NSRange headerRange = [myResponseBuffer rangeOfData:[[NSString stringWithString:@"\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
				NSString *header = [[myResponseBuffer subdataWithRange:NSMakeRange(0, headerRange.location)] descriptionAsUTF8String];
				
				if ([self transcript])
				{
					[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n\n", header] 
																			  attributes:[AbstractConnection receivedAttributes]] autorelease]];
				}
				
				unsigned start = headerRange.location + headerRange.length;
				unsigned len = [myResponseBuffer length] - start;
				NSData *fileData = [myResponseBuffer subdataWithRange:NSMakeRange(start,len)];
				[myDownloadHandle writeData:fileData];
				[myResponseBuffer setLength:0];
				
				bytesTransferred += [fileData length];
				
				if (_flags.downloadProgressed)
				{
					[_forwarder connection:self download:[download remotePath] receivedDataOfLength:[fileData length]];
				}
				if ([download delegateRespondsToTransferTransferredData])
				{
					[[download delegate] transfer:[download userInfo] transferredDataOfLength:[fileData length]];
				}
				
				int percent = (100 * bytesTransferred) / bytesToTransfer;
				if (_flags.downloadPercent)
				{
					[_forwarder connection:self download:[download remotePath] progressedTo:[NSNumber numberWithInt:percent]];
				}
				if ([download delegateRespondsToTransferProgressedTo])
				{
					[[download delegate] transfer:[download userInfo] progressedTo:[NSNumber numberWithInt:percent]];
				}
				lastPercent = percent;
			}
		}
		else  //add the data at the end of the file
		{
			[myDownloadHandle writeData:data];
			[myResponseBuffer setLength:0]; 
			bytesTransferred += [data length];
			
			if (_flags.downloadProgressed)
			{
				[_forwarder connection:self download:[download remotePath] receivedDataOfLength:[data length]];
			}
			if ([download delegateRespondsToTransferTransferredData])
			{
				[[download delegate] transfer:[download userInfo] transferredDataOfLength:[data length]];
			}
			
			int percent = (100 * bytesTransferred) / bytesToTransfer;
			if (percent != lastPercent)
			{
				if (_flags.downloadPercent)
				{
					[_forwarder connection:self download:[download remotePath] progressedTo:[NSNumber numberWithInt:percent]];
				}
				if ([download delegateRespondsToTransferProgressedTo])
				{
					[[download delegate] transfer:[download userInfo] progressedTo:[NSNumber numberWithInt:percent]];
				}
				lastPercent = percent;
			}
		}
		
		
		//check for completion, if the file is really small, then the transfer might be complete on the first pass
		//through this method, so check for completion everytime
		//
		if (bytesTransferred >= bytesToTransfer)  //sometimes more data is received than required (i assume on small size file)
		{
			[myDownloadHandle closeFile];
			[myDownloadHandle release];
			myDownloadHandle = nil;
			
			[download retain];
			[self dequeueDownload];
			
			if (_flags.downloadFinished)
			{
				[_forwarder connection:self downloadDidFinish:[download remotePath] error:nil];
			}
			if ([download delegateRespondsToTransferDidFinish])
			{
				[[download delegate] transferDidFinish:[download userInfo] error:nil];
			}
			[download release];
			
			[myCurrentRequest release];
			myCurrentRequest = nil;
			
			[self setState:ConnectionIdleState];
		}
		return NO;
	}
	return YES;
}

- (void)closeStreams
{
	bytesTransferred = 0;
	[super closeStreams];
}

#pragma mark -
#pragma mark Abstract Connection Protocol

- (void)threadedConnect
{
	[myCurrentDirectory autorelease];
	myCurrentDirectory = [[NSString alloc] initWithString:@"/"];
	[super threadedConnect];
	
	if (_flags.didAuthenticate)
	{
		[_forwarder connection:self didAuthenticateToHost:[self host] error:nil];
	}
}

- (void)davDidChangeToDirectory:(NSString *)dirPath
{
	[myCurrentDirectory autorelease];
	myCurrentDirectory = [dirPath copy];
	if (_flags.changeDirectory)
	{
		[_forwarder connection:self didChangeToDirectory:dirPath error:nil];
	}
	[myCurrentRequest release];
	myCurrentRequest = nil;
	[self setState:ConnectionIdleState];
}

- (void)changeToDirectory:(NSString *)dirPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(davDidChangeToDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObjects: dirPath, nil]];
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

- (NSString *)rootDirectory
{
	return nil;
}

- (void)createDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no directory specified");
	
	DAVCreateDirectoryRequest *req = [DAVCreateDirectoryRequest createDirectoryWithPath:dirPath];
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionCreateDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	//we don't support setting permissions
	[self createDirectory:dirPath];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"no file/path specified");
	//no op
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSAssert(fromPath && ![fromPath isEqualToString:@""], @"fromPath is nil!");
    NSAssert(toPath && ![toPath isEqualToString:@""], @"toPath is nil!");
	
	fromPath = [fromPath stringByStandardizingHTTPPath];
	toPath = [toPath stringByStandardizingHTTPPath];
	
	CKHTTPRequest *req = [CKHTTPRequest requestWithMethod:@"MOVE" uri:fromPath];
	
	//Set the destination path. Some WebDAV servers require this be a full HTTP url, so if we don't have one as the host already, we'll format it as one.
	NSString *destinationPath = [[self host] stringByAppendingURLComponent:toPath];
	if (![destinationPath hasPrefix:@"http://"] && ![destinationPath hasPrefix:@"https://"])
		destinationPath = [@"http://" stringByAppendingURLComponent:destinationPath];
	[req setHeader:destinationPath  forKey:@"Destination"];
	
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionAwaitingRenameState
											  dependant:nil
											   userInfo:nil];
	[self queueRename:fromPath];
	[self queueRename:toPath];
	[self queueCommand:cmd];
}

- (void)deleteFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"path is nil!");

	DAVDeleteRequest *req = [DAVDeleteRequest deleteFileWithPath:path];
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionDeleteFileState
											  dependant:nil
											   userInfo:nil];
	[self queueDeletion:path];
	[self queueCommand:cmd];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"dirPath is nil!");
	
	DAVDeleteRequest *req = [DAVDeleteRequest deleteFileWithPath:dirPath];
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionDeleteDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueDeletion:dirPath];
	[self queueCommand:cmd];
}

- (void)uploadFile:(NSString *)localPath
{
	[self uploadFile:localPath 
			  toFile:[[myCurrentDirectory encodeLegally] stringByAppendingPathComponent:[localPath lastPathComponent]]];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	[self uploadFile:localPath toFile:remotePath checkRemoteExistence:NO delegate:nil];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	[self uploadFile:localPath toFile:remotePath checkRemoteExistence:flag delegate:nil];
}

- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate
{
	NSAssert(localPath && ![localPath isEqualToString:@""], @"localPath is nil!");
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
	NSDictionary *attribs = [[NSFileManager defaultManager] fileAttributesAtPath:localPath traverseLink:YES];
	CKTransferRecord *transfer = [CKTransferRecord recordWithName:remotePath size:[[attribs objectForKey:NSFileSize] unsignedLongLongValue]];
	CKInternalTransferRecord *record = [CKInternalTransferRecord recordWithLocal:localPath
																			data:nil
																		  offset:0
																		  remote:remotePath
																		delegate:delegate ? delegate : transfer
																		userInfo:transfer];
	[transfer setUpload:YES];
	[transfer setObject:localPath forKey:QueueUploadLocalFileKey];
	[transfer setObject:remotePath forKey:QueueUploadRemoteFileKey];
	
	DAVUploadFileRequest *req = [DAVUploadFileRequest uploadWithFile:localPath filename:remotePath];
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	
	
	[self queueUpload:record];
	[self queueCommand:cmd];
	
	return transfer;
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(unsigned long long)offset
{
	// we don't support upload resumption
	[self uploadFile:localPath];
}

- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	[self uploadFile:localPath toFile:remotePath];
}

- (CKTransferRecord *)resumeUploadFile:(NSString *)localPath 
								toFile:(NSString *)remotePath 
							fileOffset:(unsigned long long)offset
							  delegate:(id)delegate
{
	return [self uploadFile:localPath toFile:remotePath checkRemoteExistence:NO delegate:delegate];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	[self uploadFromData:data toFile:remotePath checkRemoteExistence:NO delegate:nil];
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
	
	CKTransferRecord *transfer = [CKTransferRecord recordWithName:remotePath size:[data length]];
	CKInternalTransferRecord *record = [CKInternalTransferRecord recordWithLocal:nil
																			data:data
																		  offset:0
																		  remote:remotePath
																		delegate:delegate ? delegate : transfer
																		userInfo:transfer];
	[transfer setUpload:YES];
	[transfer setObject:remotePath forKey:QueueUploadRemoteFileKey];
	
	DAVUploadFileRequest *req = [DAVUploadFileRequest uploadWithData:data filename:remotePath];
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	
	[self queueUpload:record];
	[self queueCommand:cmd];
	
	return transfer;
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	// we don't support upload resumption
	[self uploadFromData:data toFile:remotePath];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	[self downloadFile:remotePath toDirectory:dirPath overwrite:YES delegate:nil];
}

- (CKTransferRecord *)downloadFile:(NSString *)remotePath 
					   toDirectory:(NSString *)dirPath 
						 overwrite:(BOOL)flag
						  delegate:(id)delegate
{
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"no remotePath");
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
	NSString *localPath = [dirPath stringByAppendingPathComponent:[remotePath lastPathComponent]];
	CKTransferRecord *transfer = [CKTransferRecord recordWithName:remotePath size:0];
	CKInternalTransferRecord *record = [CKInternalTransferRecord recordWithLocal:localPath
																			data:nil
																		  offset:0
																		  remote:remotePath
																		delegate:delegate ? delegate : transfer
																		userInfo:transfer];
	[transfer setObject:remotePath forKey:QueueDownloadRemoteFileKey];
	[transfer setObject:localPath forKey:QueueDownloadDestinationFileKey];
	[transfer setUpload:NO];
	
	CKHTTPFileDownloadRequest *r = [CKHTTPFileDownloadRequest downloadRemotePath:remotePath to:dirPath];
	ConnectionCommand *cmd = [ConnectionCommand command:r
											 awaitState:ConnectionIdleState
											  sentState:ConnectionDownloadingFileState
											  dependant:nil
											   userInfo:nil];
	[self queueDownload:record];
	[self queueCommand:cmd];
	
	return transfer;
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(unsigned long long)offset
{
	[self downloadFile:remotePath toDirectory:dirPath overwrite:YES];
}

- (CKTransferRecord *)resumeDownloadFile:(NSString *)remotePath
							 toDirectory:(NSString *)dirPath
							  fileOffset:(unsigned long long)offset
								delegate:(id)delegate
{
	return [self downloadFile:remotePath toDirectory:dirPath overwrite:YES delegate:delegate];
}

- (void)davDirectoryContents:(NSString *)dir
{
	CKHTTPRequest *r = [DAVDirectoryContentsRequest directoryContentsForPath:dir != nil ? dir : myCurrentDirectory];
	[myCurrentRequest autorelease];
	myCurrentRequest = [r retain];
	[self sendCommand:r];
}

- (void)directoryContents
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(davDirectoryContents:)
													  target:self
												   arguments:[NSArray array]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv 
											 awaitState:ConnectionIdleState
											  sentState:ConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
	NSArray *cachedContents = [self cachedContentsWithDirectory:dirPath];
	if (cachedContents)
	{
		[_forwarder connection:self didReceiveContents:cachedContents ofDirectory:dirPath error:nil];
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CKDoesNotRefreshCachedListings"])
		{
			return;
		}		
	}		
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(davDirectoryContents:)
													  target:self
												   arguments:[NSArray arrayWithObject:dirPath]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv 
											 awaitState:ConnectionIdleState
											  sentState:ConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

#pragma mark -
#pragma mark Stream Overrides


- (void)stream:(id<OutputStream>)stream sentBytesOfLength:(unsigned)length
{
	[super stream:stream sentBytesOfLength:length]; // call http
	if (length == 0) return;
	if (GET_STATE == ConnectionUploadingFileState)
	{
		if (transferHeaderLength > 0)
		{
			if (length <= transferHeaderLength)
			{
				transferHeaderLength -= length;
			}
			else
			{
				length -= transferHeaderLength;
				transferHeaderLength = 0;
				bytesTransferred += length;
			}
		}
		else
		{
			bytesTransferred += length;
		}
		CKInternalTransferRecord *upload = [self currentUpload];
		
		if (bytesToTransfer > 0)
		{
			int percent = (100 * bytesTransferred) / bytesToTransfer;
			if (percent != lastPercent)
			{
				if (_flags.uploadPercent)
				{
					[_forwarder connection:self 
									upload:[[self currentUpload] remotePath]
							  progressedTo:[NSNumber numberWithInt:percent]];
				}
				if ([upload delegateRespondsToTransferProgressedTo])
				{
					[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:percent]];
				}
				lastPercent = percent;
			}
		}
		if (_flags.uploadProgressed)
		{
			[_forwarder connection:self 
							upload:[[self currentUpload] remotePath]
				  sentDataOfLength:length];
		}
		if ([upload delegateRespondsToTransferTransferredData])
		{
			[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:length];
		}
	}
}

@end

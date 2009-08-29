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

#import "CKWebDAVConnection.h"
#import "CKAbstractConnection.h"
#import "CKDAVDirectoryContentsRequest.h"
#import "CKDAVCreateDirectoryRequest.h"
#import "CKDAVUploadFileRequest.h"
#import "CKDAVDeleteRequest.h"
#import "CKDAVResponse.h"
#import "CKDAVDirectoryContentsResponse.h"
#import "CKDAVCreateDirectoryResponse.h"
#import "CKDAVUploadFileResponse.h"
#import "CKDAVDeleteResponse.h"
#import "NSData+Connection.h"
#import "CKHTTPFileDownloadRequest.h"
#import "CKHTTPFileDownloadResponse.h"
#import "CKInternalTransferRecord.h"
#import "CKTransferRecord.h"
#import "NSString+Connection.h"

NSString *WebDAVErrorDomain = @"WebDAVErrorDomain";

@implementation CKWebDAVConnection

#pragma mark class methods

+ (void)load	// registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	//Register all URL Schemes and the protocol.
	NSEnumerator *URLSchemeEnumerator = [[self URLSchemes] objectEnumerator];
	NSString *URLScheme;
	while ((URLScheme = [URLSchemeEnumerator nextObject]))
		[[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forProtocol:[self protocol] URLScheme:URLScheme];
	
    [pool release];
}

+ (CKProtocol)protocol
{
	return CKWebDAVProtocol;
}

+ (NSArray *)URLSchemes
{
	return [NSArray arrayWithObjects:@"webdav", @"http", nil];
}

#pragma mark init methods

- (void)dealloc
{
	[myCurrentDirectory release];
	[myDownloadHandle release];
	[super dealloc];
}

#pragma mark -
#pragma mark Stream Overrides

- (void)processResponse:(CKHTTPResponse *)response
{
	KTLog(CKProtocolDomain, KTLogDebug, @"%@", response);
	switch (GET_STATE)
	{
		case CKConnectionAwaitingDirectoryContentsState:
		{
			CKDAVDirectoryContentsResponse *dav = (CKDAVDirectoryContentsResponse *)response;
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
            [[self client] connectionDidReceiveContents:contents ofDirectory:dirPath error:error];
            
			[self setState:CKConnectionIdleState];
			break;
		}
		case CKConnectionCreateDirectoryState:
		{
			CKDAVCreateDirectoryResponse *dav = (CKDAVCreateDirectoryResponse *)response;
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
					if (!_isRecursiveUploading)
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
			
            if (localizedDescription)
            {
                [userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
                [userInfo setObject:[dav className] forKey:@"DAVResponseClass"];
                [userInfo setObject:[[dav request] description] forKey:@"DAVRequest"];
                [userInfo setObject:[(CKDAVCreateDirectoryRequest *)[dav request] path] forKey:NSFilePathErrorKey];
                error = [NSError errorWithDomain:WebDAVErrorDomain code:[dav code] userInfo:userInfo];
            }
            [[self client] connectionDidCreateDirectory:[dav directory] error:error];
            
			[self setState:CKConnectionIdleState];
			break;
		}
		case CKConnectionUploadingFileState:
		{
			CKDAVUploadFileResponse *dav = (CKDAVUploadFileResponse *)response;
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
			
			[[self client] uploadDidFinish:[upload remotePath] error:error];

			if ([upload delegateRespondsToTransferDidFinish])
				[[upload delegate] transferDidFinish:[upload delegate] error:error];
			
			[upload release];
			
			[self setState:CKConnectionIdleState];
			break;
		}
		case CKConnectionDownloadingFileState:
		{
			CKInternalTransferRecord *downloadInfo = [[self currentDownload] retain];
			[self dequeueDownload];
			
			CKTransferRecord *record = (CKTransferRecord *)[downloadInfo userInfo];
			[[self client] downloadDidFinish:[record remotePath] error:nil];

			if ([downloadInfo delegateRespondsToTransferDidFinish])
				[[downloadInfo delegate] transferDidFinish:[downloadInfo userInfo] error:nil];
			
			[downloadInfo release];
			break;
		}
		case CKConnectionDeleteFileState:
		{
			CKDAVDeleteResponse *dav = (CKDAVDeleteResponse *)response;
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
			
			[[self client] connectionDidDeleteFile:deletionPath error:error];
			
			[deletionPath release];
			
			[self setState:CKConnectionIdleState];
			break;
		}
		case CKConnectionDeleteDirectoryState:
		{
			CKDAVDeleteResponse *dav = (CKDAVDeleteResponse *)response;
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
			
			[[self client] connectionDidDeleteDirectory:deletionPath error:error];
			
			[deletionPath release];
			
			[self setState:CKConnectionIdleState];
			break;
		}
		case CKConnectionAwaitingRenameState:
		{
			[[self client] connectionDidRename:[_fileRenames objectAtIndex:0] to:[_fileRenames objectAtIndex:1] error:nil];
			[_fileRenames removeObjectAtIndex:0];
			[_fileRenames removeObjectAtIndex:0];
			[self setState:CKConnectionIdleState];
			break;
		}
		default: 
			break;
	}
	
	[self setState:CKConnectionIdleState];	
}

- (void)initiatingNewRequest:(CKHTTPRequest *)req withPacket:(NSData *)packet
{
	// if we are uploading or downloading set up the transfer sizes
	if (GET_STATE == CKConnectionUploadingFileState)
	{
		transferHeaderLength = [req headerLength];
		bytesToTransfer = [req contentLength];//[packet length] - transferHeaderLength;
		bytesTransferred = 0;
		CKInternalTransferRecord *upload = [self currentUpload];
		
		[[self client] uploadDidBegin:[upload remotePath]];
		
		if ([upload delegateRespondsToTransferDidBegin])
		{
			[[upload delegate] transferDidBegin:[upload userInfo]];
		}
	}
	if (GET_STATE == CKConnectionDownloadingFileState)
	{
		bytesToTransfer = 0;
		bytesTransferred = 0;
		CKInternalTransferRecord *download = [self currentDownload];
		
		[[self client] downloadDidBegin:[download remotePath]];
		
		if ([download delegateRespondsToTransferDidBegin])
		{
			[[download delegate] transferDidBegin:[download userInfo]];
		}
	}
}

- (BOOL)processBufferWithNewData:(NSData *)data
{
	//If we don't have any authorization, we cannot possibly be downloading. If the initial command we send to the WebDAV server is a download, our state will be downloading, but we will not have authorized. We must allow authorization!
	BOOL hasAuthorized = (_basicAccessAuthorizationHeader || _currentAuth);
	
	if (hasAuthorized && GET_STATE == CKConnectionDownloadingFileState)
	{
		CKInternalTransferRecord *download = [self currentDownload];
		if (bytesToTransfer == 0)
		{
			NSDictionary *headers = [CKHTTPResponse headersWithData:myResponseBuffer];
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
					[fm removeItemAtPath:[download localPath] error:nil];
				}
				[fm createFileAtPath:[download localPath]
							contents:nil
						  attributes:nil];
				[myDownloadHandle release];
				myDownloadHandle = [[NSFileHandle fileHandleForWritingAtPath:[download localPath]] retain];
				
				// file data starts after the header
				NSRange headerRange = [myResponseBuffer rangeOfData:[[NSString stringWithString:@"\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
				NSString *header = [[myResponseBuffer subdataWithRange:NSMakeRange(0, headerRange.location)] descriptionAsUTF8String];
				
				[[self client] appendLine:header toTranscript:CKTranscriptReceived];
				
				unsigned start = headerRange.location + headerRange.length;
				unsigned len = [myResponseBuffer length] - start;
				NSData *fileData = [myResponseBuffer subdataWithRange:NSMakeRange(start,len)];
				[myDownloadHandle writeData:fileData];
				[myResponseBuffer setLength:0];
				
				bytesTransferred += [fileData length];
				
				[[self client] download:[download remotePath] didReceiveDataOfLength:[fileData length]];
				
				if ([download delegateRespondsToTransferTransferredData])
				{
					[[download delegate] transfer:[download userInfo] transferredDataOfLength:[fileData length]];
				}
				
				int percent = (bytesToTransfer == 0) ? 0 : (100 * bytesTransferred) / bytesToTransfer;
				[[self client] download:[download remotePath] didProgressToPercent:[NSNumber numberWithInt:percent]];
				
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
			
			[[self client] download:[download remotePath] didReceiveDataOfLength:[data length]];
			
			if ([download delegateRespondsToTransferTransferredData])
			{
				[[download delegate] transfer:[download userInfo] transferredDataOfLength:[data length]];
			}
			
			int percent = (100 * bytesTransferred) / bytesToTransfer;
			if (percent != lastPercent)
			{
				[[self client] download:[download remotePath] didProgressToPercent:[NSNumber numberWithInt:percent]];
				
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
			return YES;
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
}

- (void)davDidChangeToDirectory:(NSString *)dirPath
{
	[myCurrentDirectory autorelease];
	myCurrentDirectory = [dirPath copy];
	
	[[self client] connectionDidChangeToDirectory:dirPath error:nil];
	
	[myCurrentRequest release];
	myCurrentRequest = nil;
	[self setState:CKConnectionIdleState];
}

- (void)changeToDirectory:(NSString *)dirPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(davDidChangeToDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObjects: dirPath, nil]];
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

- (NSString *)rootDirectory
{
	return nil;
}

- (void)createDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no directory specified");
	
	CKDAVCreateDirectoryRequest *req = [CKDAVCreateDirectoryRequest createDirectoryWithPath:dirPath];
	CKConnectionCommand *cmd = [CKConnectionCommand command:req
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionCreateDirectoryState
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
	NSString *destinationPath = [[[[self request] URL] host] stringByAppendingURLComponent:toPath];
	if (![destinationPath hasPrefix:@"http://"] && ![destinationPath hasPrefix:@"https://"])
		destinationPath = [@"http://" stringByAppendingURLComponent:destinationPath];
	[req setHeader:destinationPath  forKey:@"Destination"];
	
	CKConnectionCommand *cmd = [CKConnectionCommand command:req
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionAwaitingRenameState
											  dependant:nil
											   userInfo:nil];
	[self queueRename:fromPath];
	[self queueRename:toPath];
	[self queueCommand:cmd];
}

- (void)deleteFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"path is nil!");

	CKDAVDeleteRequest *req = [CKDAVDeleteRequest deleteFileWithPath:path];
	CKConnectionCommand *cmd = [CKConnectionCommand command:req
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionDeleteFileState
											  dependant:nil
											   userInfo:nil];
	[self queueDeletion:path];
	[self queueCommand:cmd];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"dirPath is nil!");
	
	CKDAVDeleteRequest *req = [CKDAVDeleteRequest deleteFileWithPath:dirPath];
	CKConnectionCommand *cmd = [CKConnectionCommand command:req
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionDeleteDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueDeletion:dirPath];
	[self queueCommand:cmd];
}

- (CKTransferRecord *)_uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate
{
	NSAssert(localPath && ![localPath isEqualToString:@""], @"localPath is nil!");
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
	NSDictionary *attribs = [[NSFileManager defaultManager] attributesOfItemAtPath:localPath error:nil];
	CKTransferRecord *transfer = [CKTransferRecord uploadRecordForConnection:self 
															 sourceLocalPath:localPath
													   destinationRemotePath:remotePath
																		size:[[attribs objectForKey:NSFileSize] unsignedLongLongValue] 
																 isDirectory:NO];
	CKInternalTransferRecord *record = [CKInternalTransferRecord recordWithLocal:localPath
																			data:nil
																		  offset:0
																		  remote:remotePath
																		delegate:delegate ? delegate : transfer
																		userInfo:transfer];
	
	CKDAVUploadFileRequest *req = [CKDAVUploadFileRequest uploadWithFile:localPath filename:remotePath];
	CKConnectionCommand *cmd = [CKConnectionCommand command:req
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	
	
	[self queueUpload:record];
	[self queueCommand:cmd];
	
	return transfer;
}

- (CKTransferRecord *)resumeUploadFile:(NSString *)localPath 
								toFile:(NSString *)remotePath 
							fileOffset:(unsigned long long)offset
							  delegate:(id)delegate
{
	return [self _uploadFile:localPath toFile:remotePath checkRemoteExistence:NO delegate:delegate];
}

- (CKTransferRecord *)uploadFromData:(NSData *)data
							  toFile:(NSString *)remotePath 
				checkRemoteExistence:(BOOL)flag
							delegate:(id)delegate
{
	NSAssert(data, @"no data");	// data should not be nil, but it shoud be OK to have zero length!
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
	CKTransferRecord *transfer = [CKTransferRecord uploadRecordForConnection:self
															 sourceLocalPath:@""
													   destinationRemotePath:remotePath
																		size:[data length] 
																 isDirectory:NO];
	CKInternalTransferRecord *record = [CKInternalTransferRecord recordWithLocal:nil
																			data:data
																		  offset:0
																		  remote:remotePath
																		delegate:delegate ? delegate : transfer
																		userInfo:transfer];
	
	CKDAVUploadFileRequest *req = [CKDAVUploadFileRequest uploadWithData:data filename:remotePath];
	CKConnectionCommand *cmd = [CKConnectionCommand command:req
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	
	[self queueUpload:record];
	[self queueCommand:cmd];
	
	return transfer;
}

- (CKTransferRecord *)downloadFile:(NSString *)remotePath 
					   toDirectory:(NSString *)dirPath 
						 overwrite:(BOOL)flag
						  delegate:(id)delegate
{
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"no remotePath");
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
	NSString *localPath = [dirPath stringByAppendingPathComponent:[remotePath lastPathComponent]];
	CKTransferRecord *transfer = [CKTransferRecord downloadRecordForConnection:self
															  sourceRemotePath:remotePath
														  destinationLocalPath:localPath
																		  size:0 
																   isDirectory:NO];
	CKInternalTransferRecord *record = [CKInternalTransferRecord recordWithLocal:localPath
																			data:nil
																		  offset:0
																		  remote:remotePath
																		delegate:delegate ? delegate : transfer
																		userInfo:transfer];

	CKHTTPFileDownloadRequest *r = [CKHTTPFileDownloadRequest downloadRemotePath:remotePath to:dirPath];
	CKConnectionCommand *cmd = [CKConnectionCommand command:r
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionDownloadingFileState
											  dependant:nil
											   userInfo:nil];
	[self queueDownload:record];
	[self queueCommand:cmd];
	
	return transfer;
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
	CKHTTPRequest *r = [CKDAVDirectoryContentsRequest directoryContentsForPath:dir != nil ? dir : myCurrentDirectory];
	[myCurrentRequest autorelease];
	myCurrentRequest = [r retain];
	[self sendCommand:r];
}

- (void)directoryContents
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(davDirectoryContents:)
													  target:self
												   arguments:[NSArray array]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv 
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
	//Users can explicitly request we not cache directory listings. Are we allowed to?
	BOOL cachingDisabled = [[NSUserDefaults standardUserDefaults] boolForKey:CKDoesNotCacheDirectoryListingsKey];
	if (!cachingDisabled)
	{
		//We're allowed to cache directory listings. Return a cached listing if possible.
		NSArray *cachedContents = [self cachedContentsWithDirectory:dirPath];
		if (cachedContents)
		{
			[[self client] connectionDidReceiveContents:cachedContents ofDirectory:dirPath error:nil];
			
			//By default, we automatically refresh the cached listings after returning the cached version. Users can explicitly request we not do this.
			if ([[NSUserDefaults standardUserDefaults] boolForKey:CKDoesNotRefreshCachedListingsKey])
				return;
		}		
	}
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(davDirectoryContents:)
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
#pragma mark Stream Overrides


- (void)stream:(id<OutputStream>)stream sentBytesOfLength:(unsigned)length
{
	[super stream:stream sentBytesOfLength:length]; // call http
	if (length == 0) return;
	if (GET_STATE == CKConnectionUploadingFileState)
	{
		if (transferHeaderLength > 0)
		{
			//If we only sent the header (or part of it), there's we haven't send any data yet.
			if (length <= transferHeaderLength)
				return;
			
			length -= transferHeaderLength;
			transferHeaderLength = 0;
			bytesTransferred += length;
		}
		else
			bytesTransferred += length;
				
		CKInternalTransferRecord *upload = [self currentUpload];
		
		if (bytesToTransfer > 0)
		{
			int percent = (100 * bytesTransferred) / bytesToTransfer;
			if (percent != lastPercent)
			{
				[[self client] upload:[[self currentUpload] remotePath] didProgressToPercent:[NSNumber numberWithInt:percent]];
				
				if ([upload delegateRespondsToTransferProgressedTo])
				{
					[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:percent]];
				}
				lastPercent = percent;
			}
		}
		
        [[self client] upload:[[self currentUpload] remotePath] didSendDataOfLength:length];
		
		if ([upload delegateRespondsToTransferTransferredData])
		{
			[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:length];
		}
	}
}

@end
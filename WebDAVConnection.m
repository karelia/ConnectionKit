/*
 Copyright (c) 2004-2006, Greg Hulands <ghulands@framedphotographics.com>
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

NSString *WebDAVErrorDomain = @"WebDAVErrorDomain";

@implementation WebDAVConnection

#pragma mark class methods

+ (void)load
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
										   userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInThisBundle(@"Username and Password are required for WebDAV connections", @"No username or password")
																				forKey:NSLocalizedDescriptionKey]];
			*error = err;
		}
		[self release];
		return nil;
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
	switch (GET_STATE)
	{
		case ConnectionAwaitingDirectoryContentsState:
		{
			DAVDirectoryContentsResponse *dav = (DAVDirectoryContentsResponse *)response;
			NSString *err = nil;
			switch ([dav code])
			{
				case 200:
				case 207: //multi-status
				{
					NSArray *contents = [dav directoryContents];
					[self cacheDirectory:[dav path] withContents:contents];
					if (_flags.directoryContents)
					{
						[_forwarder connection:self didReceiveContents:contents ofDirectory:[dav path]];
					}
					break;
				}
				case 404:
				{		
					err = [NSString stringWithFormat: @"%@: %@", LocalizedStringInThisBundle(@"There is no WebDAV access to the directory", @"No WebDAV access to the specified path"), [dav path]];
				}
				default: 
				{
					err = LocalizedStringInThisBundle(@"Unknown Error Occurred", @"WebDAV Error");
				}
			}
			if (err)
			{
				if (_flags.error)
				{
					NSMutableDictionary *ui = [NSMutableDictionary dictionaryWithObject:err forKey:NSLocalizedDescriptionKey];
					[ui setObject:[dav className] forKey:@"DAVResponseClass"];
					NSError *error = [NSError errorWithDomain:WebDAVErrorDomain
														 code:[dav code]
													 userInfo:ui];
					[_forwarder connection:self didReceiveError:error];
				}
			}				
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionCreateDirectoryState:
		{
			DAVCreateDirectoryResponse *dav = (DAVCreateDirectoryResponse *)response;
			NSString *err = nil;
			NSMutableDictionary *ui = [NSMutableDictionary dictionary];
			
			switch ([dav code])
			{
				case 201: 
				{
					if (_flags.createDirectory)
					{
						[_forwarder connection:self didCreateDirectory:[dav directory]];
					}
					break;
				}
				case 403:
				{		
					err = LocalizedStringInThisBundle(@"The server does not allow the creation of directories at the current location", @"WebDAV Create Directory Error");
						//we fake the directory exists as this is usually the case if it is the root directory
					[ui setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
					break;
				}
				case 405:
				{		
					err = LocalizedStringInThisBundle(@"The directory already exists", @"WebDAV Create Directory Error");
					[ui setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
					break;
				}
				case 409:
				{
					err = LocalizedStringInThisBundle(@"An intermediate directory does not exist and needs to be created before the current directory", @"WebDAV Create Directory Error");
					break;
				}
				case 415:
				{
					err = LocalizedStringInThisBundle(@"The body of the request is not supported", @"WebDAV Create Directory Error");
					break;
				}
				case 507:
				{
					err = LocalizedStringInThisBundle(@"Insufficient storage space available", @"WebDAV Create Directory Error");
					break;
				}
				default: 
				{
					err = LocalizedStringInThisBundle(@"An unknown error occured", @"WebDAV Create Directory Error");
					break;
				}
			}
			if (err)
			{
				if (_flags.error)
				{
					[ui setObject:err forKey:NSLocalizedDescriptionKey];
					[ui setObject:[dav className] forKey:@"DAVResponseClass"];
					[ui setObject:[[dav request] description] forKey:@"DAVRequest"];
					[ui setObject:[dav directory] forKey:@"directory"];
					NSError *error = [NSError errorWithDomain:WebDAVErrorDomain
														 code:[dav code]
													 userInfo:ui];
					[_forwarder connection:self didReceiveError:error];
				}
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
			
			switch ([dav code])
			{
				case 200:
				case 201:
				case 204:
				{
					if (_flags.uploadFinished)
					{
						[_forwarder connection:self
							   uploadDidFinish:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey]];
					}
					break;
				}
				case 409:
				{		
					if (_flags.error)
					{
						NSMutableDictionary *ui = [NSMutableDictionary dictionaryWithObject:LocalizedStringInThisBundle(@"Parent Folder does not exist", @"WebDAV Uploading Error")
																					 forKey:NSLocalizedDescriptionKey];
						[ui setObject:[dav className] forKey:@"DAVResponseClass"];
						
						NSError *err = [NSError errorWithDomain:WebDAVErrorDomain
														   code:[dav code]
													   userInfo:ui];
						[_forwarder connection:self didReceiveError:err];
					}
				}
					break;
			}
			[self dequeueUpload];
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionDeleteFileState:
		{
			DAVDeleteResponse *dav = (DAVDeleteResponse *)response;
			switch ([dav code])
			{
				case 200:
				case 201:
				case 204:
				{
					if (_flags.deleteFile)
					{
						[_forwarder connection:self didDeleteFile:[self currentDeletion]];
					}
					break;
				}
				default:
				{
					if (_flags.error)
					{
						NSMutableDictionary *ui = [NSMutableDictionary dictionary];
						[ui setObject:[NSString stringWithFormat:@"%@: %@", LocalizedStringInThisBundle(@"Failed to delete file", @"WebDAV File Deletion Error"), [self currentDeletion]] forKey:NSLocalizedDescriptionKey];
						[ui setObject:[[dav request] description] forKey:@"DAVRequest"];
						[ui setObject:[dav className] forKey:@"DAVResponseClass"];
						
						NSError *err = [NSError errorWithDomain:WebDAVErrorDomain
														   code:[dav code]
													   userInfo:ui];
						[_forwarder connection:self didReceiveError:err];
					}
				}
			}
			[self dequeueDeletion];
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionDeleteDirectoryState:
		{
			DAVDeleteResponse *dav = (DAVDeleteResponse *)response;
			switch ([dav code])
			{
				case 200:
				case 201:
				case 204:
				{
					if (_flags.deleteDirectory)
					{
						[_forwarder connection:self didDeleteDirectory:[self currentDeletion]];
					}
					break;
				}
				default:
				{
					if (_flags.error)
					{
						NSMutableDictionary *ui = [NSMutableDictionary dictionary];
						[ui setObject:[NSString stringWithFormat:@"%@: %@", LocalizedStringInThisBundle(@"Failed to delete directory", @"WebDAV Directory Deletion Error"), [self currentDeletion]] forKey:NSLocalizedDescriptionKey];
						[ui setObject:[[dav request] description] forKey:@"DAVRequest"];
						[ui setObject:[dav className] forKey:@"DAVResponseClass"];
						
						NSError *err = [NSError errorWithDomain:WebDAVErrorDomain
														   code:[dav code]
													   userInfo:ui];
						[_forwarder connection:self didReceiveError:err];
					}
				}
			}
			[self dequeueDeletion];
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
		if (_flags.didBeginUpload)
		{
			[_forwarder connection:self
					uploadDidBegin:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey]];
		}
	}
	if (GET_STATE == ConnectionDownloadingFileState)
	{
		bytesToTransfer = 0;
		bytesTransferred = 0;
		
		if (_flags.didBeginDownload)
		{
			[_forwarder connection:self
				  downloadDidBegin:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey]];
		}
	}
}

- (BOOL)processBufferWithNewData:(NSData *)data
{
	if (GET_STATE == ConnectionDownloadingFileState)
	{
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
				
				NSDictionary *download = [self currentDownload];
				NSFileManager *fm = [NSFileManager defaultManager];
				BOOL isDir;
				if ([fm fileExistsAtPath:[download objectForKey:QueueDownloadDestinationFileKey] isDirectory:&isDir] && !isDir)
				{
					[fm removeFileAtPath:[download objectForKey:QueueDownloadDestinationFileKey] handler:nil];
				}
				[fm createFileAtPath:[download objectForKey:QueueDownloadDestinationFileKey]
							contents:nil
						  attributes:nil];
				[myDownloadHandle release];
				myDownloadHandle = [[NSFileHandle fileHandleForWritingAtPath:[download objectForKey:QueueDownloadDestinationFileKey]] retain];
				
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
					[_forwarder connection:self download:[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey] receivedDataOfLength:[fileData length]];
				}
				
				if (_flags.downloadPercent)
				{
					int percent = (100 * bytesTransferred) / bytesToTransfer;
					[_forwarder connection:self download:[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey] progressedTo:[NSNumber numberWithInt:percent]];
					lastPercent = percent;
				}
			}
		}
		else  //add the data at the end of the file
		{
			[myDownloadHandle writeData:data];
			[myResponseBuffer setLength:0]; 
			bytesTransferred += [data length];
			
			if (_flags.downloadProgressed)
			{
				[_forwarder connection:self download:[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey] receivedDataOfLength:[data length]];
			}
			
			if (_flags.downloadPercent)
			{
				int percent = (100 * bytesTransferred) / bytesToTransfer;
				if (percent != lastPercent)
				{
					[_forwarder connection:self download:[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey] progressedTo:[NSNumber numberWithInt:percent]];
					lastPercent = percent;
				}
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
			
			if (_flags.downloadFinished)
			{
				[_forwarder connection:self downloadDidFinish:[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey]];
			}
			[myCurrentRequest release];
			myCurrentRequest = nil;
			[self dequeueDownload];
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

- (void)davDidChangeToDirectory:(NSString *)dirPath
{
	[myCurrentDirectory autorelease];
	myCurrentDirectory = [dirPath copy];
	if (_flags.changeDirectory)
	{
		[_forwarder connection:self didChangeToDirectory:dirPath];
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
	//no op
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSAssert((nil != fromPath), @"fromPath is nil!");
    NSAssert((nil != toPath), @"toPath is nil!");
	
}

- (void)deleteFile:(NSString *)path
{
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
	[self uploadFile:localPath toFile:[myCurrentDirectory stringByAppendingPathComponent:[localPath lastPathComponent]]];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	DAVUploadFileRequest *req = [DAVUploadFileRequest uploadWithFile:localPath filename:remotePath];
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	NSMutableDictionary *attribs = [NSMutableDictionary dictionary];
	[attribs setObject:localPath forKey:QueueUploadLocalFileKey];
	[attribs setObject:remotePath forKey:QueueUploadRemoteFileKey];
	
	[self queueUpload:attribs];
	[self queueCommand:cmd];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	// currently we aren't checking remote existence
	[self uploadFile:localPath toFile:remotePath];
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(long long)offset
{
	// we don't support upload resumption
	[self uploadFile:localPath];
}

- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(long long)offset
{
	[self uploadFile:localPath toFile:remotePath];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	DAVUploadFileRequest *req = [DAVUploadFileRequest uploadWithData:data filename:remotePath];
	ConnectionCommand *cmd = [ConnectionCommand command:req
											 awaitState:ConnectionIdleState
											  sentState:ConnectionUploadingFileState
											  dependant:nil
											   userInfo:nil];
	NSMutableDictionary *attribs = [NSMutableDictionary dictionary];
	[attribs setObject:data forKey:QueueUploadLocalDataKey];
	[attribs setObject:remotePath forKey:QueueUploadRemoteFileKey];
	
	[self queueUpload:attribs];
	[self queueCommand:cmd];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	// we don't support checking remote existence
	[self uploadFromData:data toFile:remotePath];
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(long long)offset
{
	// we don't support upload resumption
	[self uploadFromData:data toFile:remotePath];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	CKHTTPFileDownloadRequest *r = [CKHTTPFileDownloadRequest downloadRemotePath:remotePath to:dirPath];
	ConnectionCommand *cmd = [ConnectionCommand command:r
											 awaitState:ConnectionIdleState
											  sentState:ConnectionDownloadingFileState
											  dependant:nil
											   userInfo:nil];
	NSMutableDictionary *attribs = [NSMutableDictionary dictionary];
	[attribs setObject:remotePath forKey:QueueDownloadRemoteFileKey];
	[attribs setObject:[dirPath stringByAppendingPathComponent:[remotePath lastPathComponent]] forKey:QueueDownloadDestinationFileKey];
	[self queueDownload:attribs];
	[self queueCommand:cmd];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(long long)offset
{
	[self downloadFile:remotePath toDirectory:dirPath overwrite:YES];
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
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(davDirectoryContents:)
													  target:self
												   arguments:[NSArray arrayWithObject:dirPath]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv 
											 awaitState:ConnectionIdleState
											  sentState:ConnectionAwaitingDirectoryContentsState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
	NSArray *cachedContents = [self cachedContentsWithDirectory:dirPath];
	if (cachedContents)
	{
		[_forwarder connection:self didReceiveContents:cachedContents ofDirectory:dirPath];
	}
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
				transferHeaderLength = 0;
				length -= transferHeaderLength;
			}
		}
		else
		{
			bytesTransferred += length;
		}
			
		if (_flags.uploadPercent)
		{
			if (bytesToTransfer > 0)
			{
				int percent = (100 * bytesTransferred) / bytesToTransfer;
				[_forwarder connection:self 
								upload:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey]
						  progressedTo:[NSNumber numberWithInt:percent]];
			}
		}
		if (_flags.uploadProgressed)
		{
			[_forwarder connection:self 
							upload:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey]
				  sentDataOfLength:length];
		}
	}
}

@end

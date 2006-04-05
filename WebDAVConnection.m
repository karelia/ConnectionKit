/*
 Copyright (c) 2004, Greg Hulands <ghulands@framedphotographics.com>
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
#import "DAVRequest.h"
#import "DAVDirectoryContentsRequest.h"
#import "DAVCreateDirectoryRequest.h"
#import "DAVUploadFileRequest.h"
#import "DAVResponse.h"
#import "DAVDirectoryContentsResponse.h"
#import "DAVCreateDirectoryResponse.h"
#import "DAVUploadFileResponse.h"
#import "NSData+Connection.h"

NSString *WebDAVErrorDomain = @"WebDAVErrorDomain";

@implementation WebDAVConnection

#pragma mark class methods

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"80", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"http://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
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
{
	WebDAVConnection *c = [[self alloc] initWithHost:host
                                                port:port
                                            username:username
                                            password:password];
	return [c autorelease];
}

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
{
	if (self = [super initWithHost:host
                              port:port
                          username:username
                          password:password])
	{
		myResponseBuffer = [[NSMutableData data] retain];
		NSData *authData = [[NSString stringWithFormat:@"%@:%@", username, password] dataUsingEncoding:NSUTF8StringEncoding];
		myAuthorization = [[NSString stringWithFormat:@"Basic %@", [authData base64Encoding]] retain];
	}
	return self;
}

- (void)dealloc
{
	[self sendPortMessage:KILL_THREAD];
	[myCurrentRequest release];
	[myCurrentDirectory release];
	[myResponseBuffer release];
	[super dealloc];
}

#pragma mark -
#pragma mark Stream Overrides

- (void)handlePortMessage:(NSPortMessage *)portMessage
{
    int message = [portMessage msgid];
	
	switch (message)
	{
		case CONNECT:
		{
			[super handlePortMessage:portMessage];
			_flags.isConnected = YES;
			[self setState:ConnectionIdleState];
			if (_flags.didConnect)
			{
				[_forwarder connection:self didConnectToHost:[self host]];
			}
			break;
		}
		default: [super handlePortMessage:portMessage];
	}
}

- (void)processReceivedData:(NSData *)data
{
	[myResponseBuffer appendData:data];
	NSRange responseRange = [DAVResponse canConstructResponseWithData:myResponseBuffer];
	if (responseRange.location != NSNotFound)
	{
		NSData *packetData = [myResponseBuffer subdataWithRange:responseRange];
		DAVResponse *response = [DAVResponse responseWithRequest:myCurrentRequest data:packetData];
		[myResponseBuffer replaceBytesInRange:responseRange withBytes:NULL length:0];
		
		if ([AbstractConnection debugEnabled])
		{
			NSLog(@"WebDAV Received:\n%@", response);
		}
		
		if ([self transcript])
		{
			[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", [response description]] 
																	  attributes:[AbstractConnection receivedAttributes]] autorelease]];
			[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", [response formattedResponse]] 
																	  attributes:[AbstractConnection dataAttributes]] autorelease]];
		}
		
		if ([response code] == 401)
		{
			if (myAuthorization != nil)
			{
				// the user or password supplied is bad
				if (_flags.badPassword)
				{
					[_forwarder connectionDidSendBadPassword:self];
					[self setState:ConnectionNotConnectedState];
					if (_flags.didDisconnect)
					{
						[_forwarder connection:self didDisconnectFromHost:[self host]];
					}
				}
			}
			else
			{
				if ([self transcript])
				{
					[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"Connection needs Authorization\n"] 
																			  attributes:[AbstractConnection sentAttributes]] autorelease]];
				}
				// need to append authorization
				NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
				NSCharacterSet *quote = [NSCharacterSet characterSetWithCharactersInString:@"\""];
				NSString *auth = [[response headerForKey:@"WWW-Authenticate"] stringByTrimmingCharactersInSet:ws];
				NSScanner *scanner = [NSScanner scannerWithString:auth];
				NSString *authMethod = nil;
				NSString *realm = nil;
				[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&authMethod];
				[scanner scanUpToString:@"Realm\"" intoString:nil];
				[scanner scanUpToCharactersFromSet:quote intoString:&realm];
				
				if ([authMethod isEqualToString:@"Basic"])
				{
					NSString *authString = [NSString stringWithFormat:@"%@:%@", [self username], [self password]];
					NSData *authData = [authString dataUsingEncoding:NSUTF8StringEncoding];
					[myAuthorization autorelease];
					myAuthorization = [[authData base64Encoding] retain];
					//resend the request with auth
					[self sendCommand:myCurrentRequest];
					return;
				}
				else
				{
					if ([self transcript])
					{
						[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"WebDAVConnection only supports Basic Authentication!\n"] 
																				  attributes:[AbstractConnection sentAttributes]] autorelease]];
					}
					@throw [NSException exceptionWithName:NSInternalInconsistencyException
												   reason:@"Only Basic Authentication is supported at the moment"
												 userInfo:nil];
				}
			}
		}
		
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
						if (_flags.directoryContents)
						{
							[_forwarder connection:self didReceiveContents:[dav directoryContents] ofDirectory:[dav path]];
						}
						break;
					}
					default: 
					{
						err = @"Unknown Error Occurred";
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
						err = @"The server does not allow the creation of directories at the current location";
						//we fake the directory exists as this is usually the case if it is the root directory
						[ui setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
						break;
					}
					case 405:
					{		
						err = @"The directory already exists";
						[ui setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
						break;
					}
					case 409:
					{
						err = @"An intermediate directory does not exist and needs to be created before the current directory";
						break;
					}
					case 415:
					{
						err = @"The body of the request is not supported";
						break;
					}
					case 507:
					{
						err = @"Insufficient storage space available";
						break;
					}
					default: 
					{
						err = @"An unknown error occured";
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
							NSMutableDictionary *ui = [NSMutableDictionary dictionaryWithObject:@"Parent Folder does not exist" forKey:NSLocalizedDescriptionKey];
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
			}
			default: break;
		}
	}
}

- (void)sendCommand:(id)command
{
	if ([command isKindOfClass:[DAVRequest class]])
	{
		DAVRequest *req = [(DAVRequest *)command retain];
		[myCurrentRequest release];
		myCurrentRequest = req;
		
		//make sure we set the host name and set anything else which is needed
		[req setHeader:[self host] forKey:@"Host"];
		[req setHeader:@"Keep-Alive" forKey:@"Connection"];
		if (myAuthorization)
		{
			[req setHeader:myAuthorization forKey:@"Authorization"];
		}
		
		if (myDAVFlags.isInReconnection)
		{
			[self performSelector:@selector(sendCommand:) withObject:command afterDelay:0.2];
			return;
		}
		if (myDAVFlags.needsReconnection)
		{
			myDAVFlags.isInReconnection = YES;
			[self openStreamsToPort:[[self port] intValue]];
			[self scheduleStreamsOnRunLoop];
			
			while (myDAVFlags.isInReconnection)
			{
				[self performSelector:@selector(sendCommand:) withObject:command afterDelay:0.2];
				return;
			}
		}
		
		if ([self transcript])
		{
			[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", [req description]] 
																	  attributes:[AbstractConnection sentAttributes]] autorelease]];
		}
		
		NSData *packet = [req serialized];
		// if we are uploading or downloading set up the transfer sizes
		if (GET_STATE == ConnectionUploadingFileState)
		{
			bytesToTransfer = [packet length];
			bytesTransferred = 0;
			
			if (_flags.didBeginUpload)
			{
				[_forwarder connection:self
						uploadDidBegin:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey]];
			}
		}
		if (GET_STATE == ConnectionDownloadingFileState)
		{
			bytesToTransfer = [packet length];
			bytesTransferred = 0;
			
			if (_flags.didBeginDownload)
			{
				[_forwarder connection:self
					  downloadDidBegin:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey]];
			}
			
		}
		if ([AbstractConnection debugEnabled])
		{
			NSLog(@"WebDAV Sending:\n%@", req);
		}
		[self sendData:packet];
	}
	else 
	{
		//we are an invocation
		NSInvocation *inv = (NSInvocation *)command;
		[inv invoke];
	}
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
	
}

- (void)deleteDirectory:(NSString *)dirPath
{
	
}

- (void)uploadFile:(NSString *)localPath
{
	[self uploadFile:localPath toFile:[myCurrentDirectory stringByAppendingPathComponent:[localPath lastPathComponent]]];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	//[self uploadFile:localPath toFile:remotePath checkRemoteExistence:NO];
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
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"WebDAV does not currently support downloading"
								 userInfo:nil];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(long long)offset
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"WebDAV does not currently support downloading"
								 userInfo:nil];
}

- (void)davDirectoryContents:(NSString *)dir
{
	DAVRequest *r = [DAVDirectoryContentsRequest directoryContentsForPath:dir != nil ? dir : myCurrentDirectory];
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
}

- (void)checkExistenceOfPath:(NSString *)path
{
	
}

#pragma mark -
#pragma mark Stream Overrides

- (void)handleReceiveStreamEvent:(NSStreamEvent)theEvent
{
	switch (theEvent) 
	{
		case NSStreamEventEndEncountered: 
		{
			// we don't want to notify the delegate we were disconnected as we want to appear to be a persistent connection
			[self closeStreams];
			myDAVFlags.needsReconnection = YES;
			break;
		}
		case NSStreamEventOpenCompleted:
		{
			if (!_flags.isConnected)
			{
				[super handleReceiveStreamEvent:theEvent];
			}
			else
			{
				myDAVFlags.needsReconnection = NO;
				myDAVFlags.isInReconnection = NO;
			}
			break;
		}
		default:
			[super handleReceiveStreamEvent:theEvent];
	}
}

- (void)handleSendStreamEvent:(NSStreamEvent)theEvent
{
	switch (theEvent) 
	{
		case NSStreamEventEndEncountered: 
		{
			// we don't want to notify the delegate we were disconnected as we want to appear to be a persistent connection
			[self closeStreams];
			myDAVFlags.needsReconnection = YES;
			break;
		}
		case NSStreamEventOpenCompleted:
		{
			if (!_flags.isConnected)
			{
				[super handleSendStreamEvent:theEvent];
			}
			else
			{
				myDAVFlags.needsReconnection = NO;
				myDAVFlags.isInReconnection = NO;
			}
			break;
		}
		default:
			[super handleSendStreamEvent:theEvent];
	}
}

- (void)stream:(id<OutputStream>)stream readBytesOfLength:(unsigned)length
{
	if (GET_STATE == ConnectionDownloadingFileState)
	{
		bytesTransferred += length;
		if (_flags.downloadPercent)
		{
			int percent = (bytesTransferred * 100) / bytesToTransfer;
			[_forwarder connection:self 
						  download:[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey]
					  progressedTo:[NSNumber numberWithInt:percent]];
		}
		if (_flags.downloadProgressed)
		{
			[_forwarder connection:self
						  download:[[self currentDownload] objectForKey:QueueDownloadRemoteFileKey]
			  receivedDataOfLength:length];
		}
	}
}

- (void)stream:(id<OutputStream>)stream sentBytesOfLength:(unsigned)length
{
	if (GET_STATE == ConnectionUploadingFileState)
	{
		bytesTransferred += length;
		if (_flags.uploadPercent)
		{
			int percent = (bytesTransferred * 100) / bytesToTransfer;
			[_forwarder connection:self 
							upload:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey]
					  progressedTo:[NSNumber numberWithInt:percent]];
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

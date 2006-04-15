/*
 Copyright (c) 2005, Greg Hulands <ghulands@framedphotographics.com>
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

#import "SFTPConnection.h"
#import "RunLoopForwarder.h"
#import "SFTPStream.h"

NSString *SFTPException = @"SFTPException";
NSString *SFTPErrorDomain = @"SFTPErrorDomain";

NSString *SFTPTemporaryDataUploadFileKey = @"SFTPTemporaryDataUploadFileKey";
NSString *SFTPRenameFromKey = @"from";
NSString *SFTPRenameToKey = @"to";
NSString *SFTPTransferSizeKey = @"size";

const unsigned int kSFTPBufferSize = 2048;

@interface SFTPConnection (Private)

+ (NSString *)escapedPathStringWithString:(NSString *)str;
- (void)sendCommand:(NSString *)cmd;
- (void)parseResponse:(NSString *)cmd;

@end

static NSArray *sftpPrompts = nil;
static NSArray *sftpErrors = nil;

@implementation SFTPConnection

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"22", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"sftp://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	NSDictionary *url2 = [NSDictionary dictionaryWithObjectsAndKeys:@"ssh://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[SFTPConnection class] forTypes:[NSArray arrayWithObjects:port, url, url2, nil]];
	
	sftpPrompts = [[NSArray alloc] initWithObjects:@"sftp> ", nil];
	sftpErrors = [[NSArray alloc] initWithObjects:@"Permission denied", @"Couldn't ", @"Secure connection ", @"No address associated with", @"Connection refused", @"Request for subsystem", @"Cannot download", @"ssh_exchange_identification", @"Operation timed out", @"no address associated with", @"REMOTE HOST IDENTIFICATION HAS CHANGED", nil];
	[pool release];
}

+ (NSString *)name
{
	return @"SFTP";
}

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
{
	return [[[SFTPConnection alloc] initWithHost:host
										   port:port
									   username:username
									   password:password] autorelease];
}

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
{
	if (self = [super initWithHost:host port:port username:username password:password]) {
		_inputBuffer = [[NSMutableString alloc] init];
		_sentTransferBegan = NO;
	}
	return self;
}

- (void)dealloc
{
	[_inputBuffer release];
	[_sftp release];
	[_currentDir release];
	[super dealloc];
}

#pragma mark -
#pragma mark Connection Overrides

- (long long)transferSpeed
{
	return _transferSpeed;
}

- (void)connect
{		
	[self emptyCommandQueue];
	[self sendPortMessage:CONNECT];
}

- (void)disconnect
{
	[self sendPortMessage:DISCONNECT];
}

- (void)forceDisconnect
{
	[self sendPortMessage:FORCE_DISCONNECT];
}

- (void)handlePortMessage:(NSPortMessage *)message
{
	unsigned msg = [message msgid];
	switch (msg) {
		case CONNECT: {
			NSMutableArray *args = [NSMutableArray arrayWithCapacity:2];
			[args addObject:[NSString stringWithFormat:@"-oPort=%@", [self port]]];
			[args addObject:[NSString stringWithFormat:@"%@@%@", [self username], [self host]]];
			[self closeStreams];
			
			_sftp = [[SFTPStream alloc] initWithArguments:args];
			
			[self setSendStream:_sftp];
			[self setReceiveStream:_sftp];
			
			[_sftp setDelegate:self];			
			[_sftp scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
			[_sftp open];
		}
		break;
		case DISCONNECT: {
			[self queueCommand:[ConnectionCommand command:@"quit"
											   awaitState:ConnectionIdleState
												sentState:ConnectionSentQuitState
												dependant:nil
												 userInfo:nil]];
			[self checkQueue];
		} break;
		case FORCE_DISCONNECT: {
			[self closeStreams];
			if (_flags.didDisconnect) 
				[_forwarder connection:self didDisconnectFromHost:[self host]];
			break;
		}
		default:
			[super handlePortMessage:message];
	}
}

- (void)closeStreams
{
	[_sftp setDelegate:nil];
	[super closeStreams];
}

- (void)runloopForwarder:(RunLoopForwarder *)rlw returnedValue:(void *)value 
{
	if (GET_STATE == ConnectionNotConnectedState) {
		//we are only ever going to get a BOOL response to validate the connection
		BOOL authorizeConnection = (BOOL)*((BOOL *)value);
		if (authorizeConnection)
		{
			[self sendCommand:@"yes"];
			[self setState:ConnectionAwaitingCurrentDirectoryState];
			[self sendCommand:@"pwd"];
			_flags.isConnected = YES;
			if (_flags.didConnect)
			{
				[_forwarder connection:self didConnectToHost:[self host]];
			}
		}
		else 
		{
			[self sendCommand:@"no"];
		}
	}
}

#pragma mark -
#pragma mark Buffer Utilities

- (BOOL)bufferMatchesAtLeastOneString:(NSArray *)strings
{
	NSEnumerator *promptEnumerator = [strings objectEnumerator];
	NSString *prompt;
	NSRange promptRange;
	
	while (prompt = [promptEnumerator nextObject]) {
		promptRange = [_inputBuffer rangeOfString:prompt];
		if (promptRange.location != NSNotFound) {
			[_inputBuffer deleteCharactersInRange:NSMakeRange(0, promptRange.location + promptRange.length)];
			return YES;
		}
	}
	return NO;
}

- (NSRange)rangeInBufferMatchingAtLeastOneString:(NSArray *)strings
{
	NSEnumerator *promptEnumerator = [strings objectEnumerator];
	NSString *prompt;
	NSRange promptRange;
	
	while (prompt = [promptEnumerator nextObject]) {
		promptRange = [_inputBuffer rangeOfString:prompt];
		if (promptRange.location != NSNotFound) {
			return promptRange;
		}
	}
	return NSMakeRange(NSNotFound, 0);
}

- (BOOL)bufferContainsPasswordPrompt
{
	NSArray *possiblePrompts = [NSArray arrayWithObjects:@"Password:", @"password:", nil];
	return [self bufferMatchesAtLeastOneString:possiblePrompts];
}

- (BOOL)bufferContainsCommandPrompt
{
	NSEnumerator *promptEnumerator = [sftpPrompts objectEnumerator];
	NSString *prompt;
	NSRange promptRange;
	
	while (prompt = [promptEnumerator nextObject]) {
		promptRange = [_inputBuffer rangeOfString:prompt];
		if (promptRange.location != NSNotFound) {
			return YES;
		}
	}
	return NO;
}

- (BOOL)bufferContainsError
{
	NSEnumerator *errorEnumerator = [sftpErrors objectEnumerator];
	NSString *error;
	NSRange errorRange;
	
	while (error = [errorEnumerator nextObject]) 
	{
		errorRange = [_inputBuffer rangeOfString:error];
		if (errorRange.location != NSNotFound) 
		{
			// now delete the error from the buffer to the next sftp prompt
			NSRange promptLoc =[_inputBuffer rangeOfString:[sftpPrompts objectAtIndex:0] 
												   options:NSLiteralSearch 
													 range:NSMakeRange(errorRange.location, [_inputBuffer length] - errorRange.location)];
			if (promptLoc.location != NSNotFound)
			{
				[_inputBuffer deleteCharactersInRange:NSMakeRange(0,promptLoc.location - 1)];
			}
			return YES;
		}
	}
	return NO;
}

- (void)removeCommandPromptFromBuffer
{
	NSEnumerator *promptEnumerator = [sftpPrompts objectEnumerator];
	NSString *prompt;
	NSRange promptRange;
	
	while (prompt = [promptEnumerator nextObject]) {
		promptRange = [_inputBuffer rangeOfString:prompt];
		if (promptRange.location != NSNotFound) {
			[_inputBuffer deleteCharactersInRange:NSMakeRange(0, promptRange.location + promptRange.length)];
			return;
		}
	}
	return;
}

- (NSRange)locationOfCommandPromptInBuffer
{
	NSEnumerator *promptEnumerator = [sftpPrompts objectEnumerator];
	NSString *prompt;
	NSRange promptRange;
	
	while (prompt = [promptEnumerator nextObject]) {
		promptRange = [_inputBuffer rangeOfString:prompt];
		if (promptRange.location != NSNotFound) {
			return promptRange;
		}
	}
	return NSMakeRange(NSNotFound,0);
}

- (void)emptyBuffer
{
	[_inputBuffer deleteCharactersInRange:NSMakeRange(0, [_inputBuffer length])];
}

- (void)getProgress:(int *)progress transferred:(long long*)bytes speed:(long long*)speed eta:(long*)eta
{
	//the buffer could contain the transfer message part so we need to go line by line to find the status
	NSRange newLinePosition = NSMakeRange(0, MIN(511, [_inputBuffer length]));
	int prog = 0; 
	long long spd = 0, amount = 0;
	long time = 0;
		
	NSString *line = [NSString stringWithString:[_inputBuffer substringWithRange:newLinePosition]];
	while ([line length] == 0) {
		[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]]; //give the process a breather
		NSData *myData = [self availableData];
		
		[_inputBuffer appendString:[[[NSString alloc] initWithData:myData
														  encoding:NSASCIIStringEncoding] autorelease]];
		newLinePosition = NSMakeRange(0, MIN(511, [_inputBuffer length]));
		line = [NSString stringWithString:[_inputBuffer substringWithRange:newLinePosition]];
	}
	[_inputBuffer deleteCharactersInRange:newLinePosition];
	NSRange progressLoc = [line rangeOfString:@":"]; //we use the : because that is not allowed in the path name and will only appear in the eta
	//NSLog(@"line %d: %@", [line length], line);
	if (progressLoc.location != NSNotFound) {
		NSArray *bits = [line componentsSeparatedByString:@" "];
		NSEnumerator *e = [bits objectEnumerator];
		NSString *cur;
		NSMutableArray *worthWhileData = [NSMutableArray array];
		
		while(cur = [e nextObject]) {
			if (![cur isEqualToString:@""] && isdigit([cur characterAtIndex:0]))
				[worthWhileData addObject:cur];
		}
		e = [worthWhileData objectEnumerator];
		//NSLog(@"%@", worthWhileData);
		while (cur = [e nextObject]) {
			NSScanner *scanner = [NSScanner scannerWithString:cur];
			
			if ([cur rangeOfString:@"%"].location != NSNotFound) {
				//percent
				float pc = 0.0;
				[scanner scanFloat:&pc];
				prog = (int)floorf(pc);
				
			} else if ([cur rangeOfString:@"/s"].location != NSNotFound) {
				//speed
				float sp = 0.0;
				NSString *formatter;
				[scanner scanFloat:&sp];
				[scanner scanUpToString:@" " intoString:&formatter];
				long long multiplier = 1;
				char power = [formatter characterAtIndex:0];
				if (power == 'K') multiplier = 1024;
				if (power == 'M') multiplier = 1024 * 1024;
				if (power == 'G') multiplier = 1024 * 1024 * 1024;
				spd = sp * multiplier;
			} else if ([cur rangeOfString:@":"].location != NSNotFound) {
				//eta
				NSArray *ts = [cur componentsSeparatedByString:@":"];
				int hrs = 0, mins = 0, secs = 0;
				if ([ts count] == 3) {
					hrs = [[ts objectAtIndex:0] intValue];
					mins = [[ts objectAtIndex:1] intValue];
					secs = [[ts objectAtIndex:2] intValue];
				} else if ([ts count] == 2) {
					mins = [[ts objectAtIndex:0] intValue];
					secs = [[ts objectAtIndex:1] intValue];
				} 
				time = (hrs * 3600) + (mins * 60) + secs;
				
			} else {
				//size transferred.
				int s = 0;
				NSString *formatter = nil;
				[scanner scanInt:&s];
				if (![scanner isAtEnd])
					[scanner scanUpToString:@" " intoString:&formatter];
				long long multiplier = 1;
				
				if (s > 0 && formatter != nil && [formatter length] > 0) {
					char power = [formatter characterAtIndex:0];
					if (power == 'K') multiplier = 1024;
					if (power == 'M') multiplier = 1024 * 1024;
					if (power == 'G') multiplier = 1024 * 1024 * 1024;
				}
				
				amount = s * multiplier;
			}
		}
	}
		
	if (progress != NULL) *progress = prog;
	if (bytes != NULL) *bytes = amount;
	if (speed != NULL) *speed = spd;
	if (eta != NULL) *eta = time;
}

#pragma mark -
#pragma mark State Machine

- (void)processReceivedData:(NSData *)data
{
	NSString *str = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];	
	[_inputBuffer appendString:str];
	
	int trys = 5;
	
	//we wait 5 times of no data
	while (trys >= 0) {
		NSData *bufData = [self availableData];
		if ([bufData length] > 0) {
			NSString *buf = [[[NSString alloc] initWithData:bufData encoding:NSUTF8StringEncoding] autorelease];
			[_inputBuffer appendString:buf];
		} else {
			trys--;
		}
		[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
	}
	
	if (GET_STATE != ConnectionUploadingFileState &&
		GET_STATE != ConnectionDownloadingFileState &&
		GET_STATE != ConnectionAwaitingDirectoryContentsState) 
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:str
																  attributes:[AbstractConnection receivedAttributes]] autorelease]];
	
	switch (GET_STATE) {
		case ConnectionNotConnectedState: {
			if ([self bufferContainsPasswordPrompt]) {
				[self setState:ConnectionSentPasswordState];
				//we don't want to display the password
				[self sendData:[[NSString stringWithFormat:@"%@\n", [self password]] dataUsingEncoding:NSUTF8StringEncoding]];
				[self appendToTranscript:[[[NSAttributedString alloc] initWithString:@"#####"
																		  attributes:[AbstractConnection sentAttributes]] autorelease]];
			} else if ([self rangeInBufferMatchingAtLeastOneString:[NSArray arrayWithObjects:@"Are you sure you want to continue connecting (yes/no)?", @"@@@", nil]].location != NSNotFound) {
				//need to authenticate the host. Should we really default to yes?
				KTLog(ProtocolDomain, KTLogDebug, @"Connecting to unknown host. Awaiting repsonse from delegate");
				if (_flags.authorizeConnection) {
					NSRange msgRange = [_inputBuffer rangeOfString:@"Are you sure you want to continue connecting (yes/no)?"];
					while (msgRange.location == NSNotFound)
					{
						[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
						NSData *bufData = [self availableData];
						if ([bufData length] > 0) {
							NSString *buf = [[[NSString alloc] initWithData:bufData encoding:NSUTF8StringEncoding] autorelease];
							[_inputBuffer appendString:buf];
						} 
						msgRange = [_inputBuffer rangeOfString:@"Are you sure you want to continue connecting (yes/no)?"];
					}
					NSString *message = [_inputBuffer substringToIndex:msgRange.location];
					[_forwarder connection:self 
				 authorizeConnectionToHost:[self host] 
								   message:[NSString stringWithFormat:@"%@\nDo you wish to authorize the connection?", message]];
				} else if (_flags.error) {
					NSError *err = [NSError errorWithDomain:SFTPErrorDomain
													   code:SFTPErrorPermissionDenied
												   userInfo:[NSDictionary dictionaryWithObject:@"Failed to Authorize Connection" forKey:NSLocalizedDescriptionKey]];
					[_forwarder connection:self didReceiveError:err];
					[self forceDisconnect];
				} else {
					KTLog(ProtocolDomain, KTLogInfo, @"Delegate does not implement connection:authorizeConnectionToHost:message: to authorize the connection"); 
					[self forceDisconnect];
				}
			} else if ([self bufferContainsCommandPrompt]) {
				//ssh authorized keys validated us
				KTLog(ProtocolDomain, KTLogInfo, @"Validated via ssh's authorized_keys");
				[self setState:ConnectionAwaitingCurrentDirectoryState];
				[self sendCommand:@"pwd"];
				_flags.isConnected = YES;
				if (_flags.didConnect)
					[_forwarder connection:self didConnectToHost:[self host]];
			} else if ([self bufferContainsError]){
				if (_flags.error) {
					NSError *err = [NSError errorWithDomain:SFTPErrorDomain
													   code:SFTPError
												   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"Unable to connect to host", NSLocalizedDescriptionKey, nil]];
					[_forwarder connection:self didReceiveError:err];
					[_inputBuffer deleteCharactersInRange:NSMakeRange(0,[_inputBuffer length])];
				}
			} else {
				[_inputBuffer deleteCharactersInRange:NSMakeRange(0,[_inputBuffer length])];
			}
		} break;
		case ConnectionSentPasswordState: {
			if ([self bufferContainsCommandPrompt]) {
				[self setState:ConnectionAwaitingCurrentDirectoryState];
				[self sendCommand:@"pwd"];
				if (_flags.didConnect)
					[_forwarder connection:self didConnectToHost:[self host]];
			} else if ([self bufferContainsPasswordPrompt]) {
				if (_flags.badPassword) {
					[_forwarder connectionDidSendBadPassword:self];
				}
			} else if ([self bufferContainsError]){
				if (_flags.error) {
					NSError *err = [NSError errorWithDomain:SFTPErrorDomain
													   code:SFTPErrorBadPassword
												   userInfo:nil];
					[_forwarder connection:self didReceiveError:err];
				}
			}
			break;
		}
		case ConnectionAwaitingDirectoryContentsState: {
			if ([self bufferContainsError]){
				if (_flags.error) {
					NSError *err = [NSError errorWithDomain:SFTPErrorDomain
													   code:SFTPErrorDirectoryContents
												   userInfo:nil];
					[_forwarder connection:self didReceiveError:err];
				}
			} else if ([self bufferContainsCommandPrompt]) {
				NSRange promptLoc = [self locationOfCommandPromptInBuffer];
				//delete the first prompt then wait for the last one after the listing
				//[_inputBuffer deleteCharactersInRange:NSMakeRange(0, promptLoc.location + promptLoc.length)];
				
				[_inputBuffer appendString:[[[NSString alloc] initWithData:[self availableData]
																  encoding:NSASCIIStringEncoding] autorelease]];
				
				while ((promptLoc = [self locationOfCommandPromptInBuffer]).location == NSNotFound) {
					[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
					[_inputBuffer appendString:[[[NSString alloc] initWithData:[self availableData]
																	  encoding:NSASCIIStringEncoding] autorelease]];
				}
				NSString *listing = [_inputBuffer substringWithRange:NSMakeRange(0, promptLoc.location)];
				
				[self appendToTranscript:[[[NSAttributedString alloc] initWithString:listing
																		  attributes:[AbstractConnection dataAttributes]] autorelease]];
				KTLog(ParsingDomain, KTLogDebug, @"%@", listing);
				
				NSArray *files = [NSFileManager attributedFilesFromListing:listing];
				
				if (_flags.directoryContents)
					[_forwarder connection:self
						didReceiveContents:files
							   ofDirectory:[self currentDirectory]];
				[self emptyBuffer];
				//[_inputBuffer appendString:@"sftp> "];
				[self setState:ConnectionIdleState];
			} 
			break;
		}
		case ConnectionAwaitingCurrentDirectoryState: {
			NSRange remoteDirLoc = [_inputBuffer rangeOfString:@"Remote working directory: "];
			if (remoteDirLoc.location != NSNotFound) {
				NSRange eol = [_inputBuffer rangeOfString:@"\r\n" options:NSLiteralSearch range:NSMakeRange(remoteDirLoc.location, [_inputBuffer length] - remoteDirLoc.location)];
				if (eol.location != NSNotFound)
					eol = [_inputBuffer rangeOfString:@"\n" options:NSLiteralSearch range:NSMakeRange(remoteDirLoc.location, [_inputBuffer length] - remoteDirLoc.location)];
				NSString *dir = [_inputBuffer substringWithRange:NSMakeRange(remoteDirLoc.location + remoteDirLoc.length, eol.location - (remoteDirLoc.location + remoteDirLoc.length) - 1)];
				[_currentDir autorelease];
				_currentDir = [dir copy];
				[self emptyBuffer];
				//[_inputBuffer appendString:@"sftp> "];
				if (_flags.changeDirectory)
					[_forwarder connection:self didChangeToDirectory:_currentDir];
				[self setState:ConnectionIdleState];
			}
			break;
		}
		case ConnectionChangingDirectoryState:
		{
			if ([self bufferContainsError]){
				if (_flags.error) {
					//NSLog(@"buffer = %@", _inputBuffer);
					NSError *err = [NSError errorWithDomain:SFTPErrorDomain
													   code:SFTPErrorPermissionDenied
												   userInfo:nil];
					[_forwarder connection:self didReceiveError:err];
				}
			} else if ([self bufferContainsCommandPrompt]) {
				[self setState:ConnectionIdleState];
			}
				
			break;
		}
		case ConnectionUploadingFileState:
		{
			if ([self bufferContainsError]) 
			{
				if (_flags.error) 
				{
					NSError *err = [NSError errorWithDomain:SFTPErrorDomain 
													   code:ConnectionErrorUploading 
												   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey], @"upload", @"Failed to upload file", NSLocalizedDescriptionKey, nil]];
					[_forwarder connection:self didReceiveError:err];
				}
				/*
					We don't simulate the uploading finishing as the UI will need to handle the failure in the error delegate method
				 */
				
				// continue with the queue
				[self dequeueUpload];
				[self setState:ConnectionIdleState];
			}
			else
			{
				int percent = 0;
				long long amount;
				long eta;
				
				[self getProgress:&percent transferred:&amount speed:&_transferSpeed eta:&eta];
				if (percent == 0 && !_sentTransferBegan) {
					_transferSize = [[[self currentUpload] objectForKey:SFTPTransferSizeKey] unsignedLongLongValue];
					if (_flags.didBeginUpload)
						[_forwarder connection:self uploadDidBegin:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey]];
					_progressiveTransfer = 0;
					_sentTransferBegan = YES;
				}
				//NSLog(@"%3d %%", percent);
				// we can't be guaranteed that it is exact to the byte count so work it out off the percent.
				unsigned long long bytes = (percent/100.0) * _transferSize;
				unsigned long long diff = bytes - _progressiveTransfer;
				_progressiveTransfer = amount;
				if (percent > 0 && _flags.uploadPercent)
					[_forwarder connection:self 
									upload:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey]
							  progressedTo:[NSNumber numberWithInt:percent]];
				if (_flags.uploadProgressed)
					[_forwarder connection:self 
									upload:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey] 
						  sentDataOfLength:diff];
				
				if (percent == 100) {
					if (_progressiveTransfer != _transferSize) {
						// fix up an difference
						diff = bytes - _progressiveTransfer;
						if (_flags.uploadProgressed)
						{
							[_forwarder connection:self 
											upload:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey] 
								  sentDataOfLength:diff];
						}
					}
					//reset the values
					_transferSize = 0;
					_progressiveTransfer = 0;
					_sentTransferBegan = NO;
					
					if (_flags.uploadFinished)
						[_forwarder connection:self uploadDidFinish:[[self currentUpload] objectForKey:QueueUploadRemoteFileKey]];
					//delete the temp data file if we uploaded a blob of data
					if ([[self currentUpload] objectForKey:SFTPTemporaryDataUploadFileKey]) {
						[[NSFileManager defaultManager] removeFileAtPath:[[self currentUpload] objectForKey:SFTPTemporaryDataUploadFileKey]
																 handler:nil];
					}
					[self dequeueUpload];
					[self setState:ConnectionIdleState];
				}
			}
			break;
		}
		case ConnectionDownloadingFileState:
		{
			int percent;
			long long amount;
			long eta;
			[self getProgress:&percent transferred:&amount speed:&_transferSpeed eta:&eta];
			NSDictionary *download = [self currentDownload];
			
			if (percent == 0) {
				if (_flags.didBeginDownload)
					[_forwarder connection:self downloadDidBegin:[download objectForKey:QueueDownloadRemoteFileKey]];
				_progressiveTransfer = 0;
			} 
			
			NSString *tmpDiff = [NSString stringWithFormat:@"%lld", amount - _progressiveTransfer];
			int diff = [tmpDiff intValue];
			
			_progressiveTransfer = amount;
			
			if (_flags.downloadPercent)
				[_forwarder connection:self 
							  download:[download objectForKey:QueueDownloadRemoteFileKey]
						  progressedTo:[NSNumber numberWithInt:percent]];
			if (_flags.downloadProgressed)
				[_forwarder connection:self
							  download:[download objectForKey:QueueDownloadRemoteFileKey]
				  receivedDataOfLength:(int)diff];
			
			if (percent == 100) {
				if (_flags.downloadFinished)
					[_forwarder connection:self downloadDidFinish:[download objectForKey:QueueDownloadRemoteFileKey]];
				[self dequeueDownload];
				[self setState:ConnectionIdleState];
			}
			break;
		}
		case ConnectionSettingPermissionsState:
		{
			if ([self bufferContainsCommandPrompt]) {
				if (_flags.permissions)
					[_forwarder connection:self didSetPermissionsForFile:[self currentPermissionChange]];
				[self dequeuePermissionChange];
				
				[self removeCommandPromptFromBuffer];
				[self setState:ConnectionIdleState];
			}
			break;
		}
		case ConnectionCreateDirectoryState:
		{
			//get the command from the history - it will be mkdir
			NSString *cmd = [[self lastCommand] command];
			NSString *folderName = [cmd substringFromIndex:6]; // "mkdir "
			if ([self bufferContainsError]){
				if (_flags.error) {
					// This is most likely because the directory exists. Not sure what the message would be if it was permission denied
					NSError *err = [NSError errorWithDomain:SFTPErrorDomain
													   code:SFTPErrorPermissionDenied
												   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], ConnectionDirectoryExistsKey, folderName, ConnectionDirectoryExistsFilenameKey, nil]];
					[_forwarder connection:self didReceiveError:err];
				}
			}
			[self emptyBuffer];
			if (_flags.createDirectory)
			{
				[_forwarder connection:self didCreateDirectory:folderName];
			}
				
			//[_inputBuffer appendString:@"sftp> "];
			[self setState:ConnectionIdleState];
			break;
		}
		case ConnectionAwaitingRenameState:
		{
			if ([self bufferContainsCommandPrompt]) {
				if (_flags.rename) {
					NSDictionary *rename = [self currentRename];
					[_forwarder connection:self didRename:[rename objectForKey:SFTPRenameFromKey] to:[rename objectForKey:SFTPRenameToKey]];
				}
				[self dequeueRename];
				[self setState:ConnectionIdleState];
			}
			break;
		}
		case ConnectionDeleteFileState:
		{
			if ([self bufferContainsCommandPrompt]) {
				if (_flags.deleteFile)
					[_forwarder connection:self didDeleteFile:[self currentDeletion]];
				[self dequeueDeletion];
				[self emptyBuffer];
				[_inputBuffer appendString:@"sftp> "];
				[self setState:ConnectionIdleState];
			}
			break;
		}
		case ConnectionDeleteDirectoryState:
		{
			if ([self bufferContainsCommandPrompt]) {
				if (_flags.deleteDirectory)
					[_forwarder connection:self didDeleteDirectory:[self currentDeletion]];
				[self dequeueDeletion];
				[self setState:ConnectionIdleState];
			}
			break;
		}
		case ConnectionSentQuitState:
		{
			_flags.isConnected = NO;
			if (_flags.didDisconnect)
				[_forwarder connection:self didDisconnectFromHost:[self host]];
			[self performSelector:@selector(closeStreams) withObject:nil afterDelay:0.1];
			break;
		}
	}
}

- (void)sendCommand:(NSString *)cmd
{
	KTLog(ProtocolDomain, KTLogDebug, @">> %@", cmd);
	
	NSString *formattedCommand = [NSString stringWithFormat:@"%@\n", cmd];
	NSString *prompttedCommand = [NSString stringWithFormat:@"sftp> %@\n", cmd];
	[self appendToTranscript:[[[NSAttributedString alloc] initWithString:prompttedCommand
															  attributes:[AbstractConnection sentAttributes]] autorelease]];
	
	[self sendData:[formattedCommand dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark -
#pragma mark Connection Commands 

- (void)changeToDirectory:(NSString *)dirPath
{
	ConnectionCommand *pwd = [ConnectionCommand command:@"pwd"
											 awaitState:ConnectionIdleState
											  sentState:ConnectionAwaitingCurrentDirectoryState
											  dependant:nil
											   userInfo:nil];
	ConnectionCommand *cd = [ConnectionCommand command:[NSString stringWithFormat:@"cd %@", [SFTPConnection escapedPathStringWithString:dirPath]]
											awaitState:ConnectionIdleState
											 sentState:ConnectionChangingDirectoryState
											 dependant:pwd
											  userInfo:nil];
	[self queueCommand:cd];
	[self queueCommand:pwd];
}

- (NSString *)currentDirectory
{
	return _currentDir;
}

- (NSString *)rootDirectory
{
	return nil;
}

- (void)createDirectory:(NSString *)dirPath
{
	[self queueCommand:[ConnectionCommand command:[NSString stringWithFormat:@"mkdir %@", [SFTPConnection escapedPathStringWithString:dirPath]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionCreateDirectoryState
										dependant:nil
										 userInfo:nil]];
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	ConnectionCommand *chmod = [ConnectionCommand command:[NSString stringWithFormat:@"chmod %lo %@", permissions, [SFTPConnection escapedPathStringWithString:dirPath]]
											   awaitState:ConnectionIdleState
												sentState:ConnectionSettingPermissionsState
												dependant:nil
												 userInfo:nil];
	ConnectionCommand *mkdir = [ConnectionCommand command:[NSString stringWithFormat:@"mkdir %@", [SFTPConnection escapedPathStringWithString:dirPath]]
											   awaitState:ConnectionIdleState
												sentState:ConnectionCreateDirectoryState
												dependant:chmod
												 userInfo:nil];
	[self queuePermissionChange:dirPath];
	[self queueCommand:mkdir];
	[self queueCommand:chmod];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	[self queuePermissionChange:path];
	[self queueCommand:[ConnectionCommand command:[NSString stringWithFormat:@"chmod %lo %@", permissions, [SFTPConnection escapedPathStringWithString:path]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionSettingPermissionsState
										dependant:nil
										 userInfo:nil]];
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	[self queueRename:[NSDictionary dictionaryWithObjectsAndKeys:fromPath, SFTPRenameFromKey, toPath, SFTPRenameToKey, nil]];
	[self queueCommand:[ConnectionCommand command:[NSString stringWithFormat:@"rename %@ %@", [SFTPConnection escapedPathStringWithString:fromPath], [SFTPConnection escapedPathStringWithString:toPath]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionAwaitingRenameState
										dependant:nil
										 userInfo:nil]];
}

- (void)deleteFile:(NSString *)path
{
	[self queueDeletion:path];
	[self queueCommand:[ConnectionCommand command:[NSString stringWithFormat:@"rm %@", [SFTPConnection escapedPathStringWithString:path]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionDeleteFileState
										dependant:nil
										 userInfo:nil]];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	[self queueDeletion:dirPath];
	[self queueCommand:[ConnectionCommand command:[NSString stringWithFormat:@"rmdir %@", [SFTPConnection escapedPathStringWithString:dirPath]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionDeleteDirectoryState
										dependant:nil
										 userInfo:nil]];
}

- (void)uploadFile:(NSString *)localPath
{
	[self uploadFile:localPath toFile:[localPath lastPathComponent]];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	NSMutableDictionary *upload = [NSMutableDictionary dictionary];
	[upload setObject:localPath forKey:QueueUploadLocalFileKey];
	[upload setObject:remotePath forKey:QueueUploadRemoteFileKey];
	NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:localPath];
	[upload setObject:[NSNumber numberWithUnsignedLongLong:[fh seekToEndOfFile]] forKey:SFTPTransferSizeKey];
	[self queueUpload:upload];
	
	[self queueCommand:[ConnectionCommand command:[NSString stringWithFormat:@"put %@ %@", [SFTPConnection escapedPathStringWithString:localPath], [SFTPConnection escapedPathStringWithString:remotePath]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionUploadingFileState
										dependant:nil
										 userInfo:nil]];
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(long long)offset
{
	//we don't support resuming over sftp
	[self uploadFile:localPath];
}

- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(long long)offset
{
	//we don't support resuming over sftp
	[self uploadFile:localPath toFile:remotePath];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	//write the data to a temp file and upload to remote path
	CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
	CFStringRef uuidStr = CFUUIDCreateString(kCFAllocatorDefault, uuid);
	CFRelease(uuid);
	[(NSString *)uuidStr autorelease];
	NSString *tmpFile = [NSString stringWithFormat:@"/tmp/sftp_%@.tmp", uuidStr];
	
	if (![data writeToFile:tmpFile atomically:YES]) {
		KTLog(ProtocolDomain, KTLogFatal, @"Failed to write data to tmp file %@", tmpFile);
	}
	
	NSMutableDictionary *upload = [NSMutableDictionary dictionary];
	[upload setObject:tmpFile forKey:QueueUploadLocalFileKey];
	[upload setObject:remotePath forKey:QueueUploadRemoteFileKey];
	[upload setObject:tmpFile forKey:SFTPTemporaryDataUploadFileKey];
	[upload setObject:[NSNumber numberWithUnsignedInt:[data length]] forKey:SFTPTransferSizeKey];
	[self queueUpload:upload];
	
	
	[self queueCommand:[ConnectionCommand command:[NSString stringWithFormat:@"put %@ %@", [SFTPConnection escapedPathStringWithString:tmpFile], [SFTPConnection escapedPathStringWithString:remotePath]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionUploadingFileState
										dependant:nil
										 userInfo:nil]];
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(long long)offset
{
	//we don't support resuming over sftp
	[self uploadFromData:data toFile:remotePath];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	NSString *remoteFileName = [remotePath lastPathComponent];
	NSString *localFile = [NSString stringWithFormat:@"%@/%@", dirPath, remoteFileName];
	if (!flag)
	{
		if ([[NSFileManager defaultManager] fileExistsAtPath:localFile])
		{
			if (_flags.error) {
				NSError *error = [NSError errorWithDomain:FTPErrorDomain
													 code:FTPDownloadFileExists
												 userInfo:[NSDictionary dictionaryWithObject:@"Local File already exists" forKey:NSLocalizedDescriptionKey]];
				[_forwarder connection:self didReceiveError:error];
			}
		}
	}
	NSMutableDictionary *download = [NSMutableDictionary dictionary];
	[download setObject:remotePath forKey:QueueDownloadRemoteFileKey];
	[download setObject:localFile forKey:QueueDownloadDestinationFileKey];
	[self queueDownload:download];
	
	[self queueCommand:[ConnectionCommand command:[NSString stringWithFormat:@"get %@ %@", [SFTPConnection escapedPathStringWithString:remotePath], [SFTPConnection escapedPathStringWithString:localFile]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionDownloadingFileState
										dependant:nil
										 userInfo:nil]];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(long long)offset
{
	//we don't support resuming over sftp
	[self downloadFile:remotePath toDirectory:dirPath overwrite:YES];
}

- (void)cancelTransfer
{
	
}

- (void)cancelAll
{
	
}

- (void)directoryContents
{
	[self queueCommand:[ConnectionCommand command:@"ls -l"
									   awaitState:ConnectionIdleState
										sentState:ConnectionAwaitingDirectoryContentsState
										dependant:nil
										 userInfo:nil]];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	[self queueCommand:[ConnectionCommand command:[NSString stringWithFormat:@"ls -l %@", [SFTPConnection escapedPathStringWithString:dirPath]]
									   awaitState:ConnectionIdleState
										sentState:ConnectionAwaitingDirectoryContentsState
										dependant:nil
										 userInfo:nil]];
}

+ (NSString *)escapedPathStringWithString:(NSString *)str
{
	if ([str rangeOfString:@" "].location != NSNotFound)
		return [NSString stringWithFormat:@"\"%@\"", str];
	return str;
}
@end




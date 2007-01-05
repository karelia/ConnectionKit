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
 
#import "FTPConnection.h"

#import "ConnectionThreadManager.h"
#import "RunLoopForwarder.h"
#import "CKInternalTransferRecord.h"
#import "CKTransferRecord.h"
#import "NSObject+Connection.h"

#import <sys/types.h> 
#import <sys/socket.h> 
#import <netinet/in.h>

NSString *FTPErrorDomain = @"FTPErrorDomain";

// 500 ms.
const double kDelegateNotificationTheshold = 0.5;

@interface CKTransferRecord (Internal)
- (void)setSize:(unsigned long long)size;
@end

@interface FTPConnection (Private)

- (NSArray *)parseLines:(NSString *)line;
- (void)closeDataConnection;
- (void)handleDataReceivedEvent:(NSStreamEvent)eventCode;
- (void)handleDataSendStreamEvent:(NSStreamEvent)eventCode;
- (void)closeDataStreams;
- (void)openDataStreamsToHost:(NSHost *)aHost port:(int)aPort;
- (ConnectionCommand *)pushDataConnectionOnCommandQueue;
- (ConnectionCommand *)nextAvailableDataConnectionType;
- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  orData:(NSData *)data 
						  offset:(unsigned long long)offset 
					  remotePath:(NSString *)remotePath
			checkRemoteExistence:(BOOL)flag
						delegate:(id)delegate;

- (NSFileHandle *)writeHandle;
- (void)setWriteHandle:(NSFileHandle *)aWriteHandle;
- (NSFileHandle *)readHandle;
- (void)setReadHandle:(NSFileHandle *)aReadHandle;
- (NSData *)readData;
- (void)setReadData:(NSData *)aReadData;
- (NSString *)currentPath;
- (void)setCurrentPath:(NSString *)aCurrentPath;

- (BOOL)isAboveNotificationTimeThreshold:(NSDate *)date;

- (NSString *)setupEPRTConnection; //returns the command after creating a socket
- (NSString *)setupActiveConnection; //return the cmmand after creating a socket

- (void)setDataInputStreamAndOpen:(NSInputStream *)iStream outputStream:(NSOutputStream *)oStream socket:(CFSocketNativeHandle)socket;
- (void)prepareAndOpenDataStreams;

@end

void dealWithConnectionSocket(CFSocketRef s, CFSocketCallBackType type, 
							  CFDataRef address, const void *data, void *info);

@implementation FTPConnection

// load or initialize?
// http://www.cocoabuilder.com/archive/message/2003/3/19/86306

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"21", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"ftp://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[FTPConnection class] forTypes:[NSArray arrayWithObjects:port, url, nil]];
	[pool release];
}

+ (NSString *)name
{
	return @"FTP";
}

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
				 error:(NSError **)error
{
	FTPConnection *c = [[FTPConnection alloc] initWithHost:host
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
			NSError *err = [NSError errorWithDomain:FTPErrorDomain
											   code:ConnectionNoUsernameOrPassword
										   userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInThisBundle(@"Username and Password are required for FTP connections", @"No username or password")
																				forKey:NSLocalizedDescriptionKey]];
			*error = err;
		}
		[self release];
		return nil;
	}
	
	if (self = [super initWithHost:host port:port username:username password:password error:error])
	{
		[self setState:ConnectionNotConnectedState];
		
		// These are never replaced during the lifetime of this object so we don't bother with accessor methods
		_dataBuffer = [[NSMutableData data] retain];
		_commandBuffer = [[NSMutableString alloc] initWithString:@""];
		
		_serverSupport.canUseActive = YES;
		_serverSupport.canUseEPRT = YES;
		_serverSupport.canUsePASV = YES;
		_serverSupport.canUseEPSV = YES;
		
		_serverSupport.hasSize = NO;
		_flags.isConnected = NO;
	}
	return self;
}

- (void)dealloc
{
	[self closeDataStreams];
	[_buffer release];
	[_commandBuffer release];
	[_dataBuffer release];
	[_writeHandle release];
	[self setReadHandle:nil];
	[self setWriteHandle:nil];
	[self setReadData:nil];
	[self setCurrentPath:nil];
	[_rootPath release];
	[_lastNotified release];

	[super dealloc];
}

+ (NSString *)urlScheme
{
	return @"ftp";
}

#pragma mark -
#pragma mark Commands

/*!	Called from the background thread.
*/
- (void)sendCommand:(id)command
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	if ([command isKindOfClass:[NSInvocation class]])
	{
		[command invoke];
		return;
	}
	
	if ([command isEqualToString:@"DATA_CON"])
	{
		ConnectionCommand *cmd = [self nextAvailableDataConnectionType];
		[self pushCommandOnHistoryQueue:cmd];
		command = [cmd command];
		_state = [cmd sentState];
		[self closeDataConnection];
	}
	
	if ([command isEqualToString:@"EPRT"]) 
	{
		_serverSupport.isActiveDataConn = YES;
		command = [self setupEPRTConnection];
	} 
	else if ([command isEqualToString:@"PORT"]) 
	{
		_serverSupport.isActiveDataConn = YES;
		command = [self setupActiveConnection];
	} 
	else if ([command isEqualToString:@"EPSV"])
	{
		_serverSupport.isActiveDataConn = NO;
	}
	else if ([command isEqualToString:@"PASV"])
	{
		_serverSupport.isActiveDataConn = NO;
	}
	else if ([command isEqualToString:@"LIST -FA"] && _serverSupport.isMicrosoft)
	{
		command = @"LIST";
	}

	NSString *formattedCommand = [NSString stringWithFormat:@"%@\r\n", command];

	if ([self transcript])
	{
		NSString *commandToEcho = command;
		if ([command rangeOfString:@"PASS"].location != NSNotFound)
		{
			if (![defaults boolForKey:@"AllowPasswordToBeLogged"])
			{
				commandToEcho = [NSString stringWithFormat:@"PASS %C%C%C%C%C", 0x2022, 0x2022, 0x2022, 0x2022, 0x2022];
			}
		}
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", commandToEcho] attributes:[AbstractConnection sentAttributes]] autorelease]];
	}
	
	NSString *loggableCommand = command;
	if ([command rangeOfString:@"PASS"].location != NSNotFound)
	{
		if (![defaults boolForKey:@"AllowPasswordToBeLogged"])
		{
			loggableCommand = @"PASS ####";
		}
	}
		
	KTLog(ProtocolDomain, KTLogDebug, @">> %@", loggableCommand);

	if ([formattedCommand rangeOfString:@"RETR"].location != NSNotFound)
	{
		CKInternalTransferRecord *download = [self currentDownload];
		if (_flags.didBeginDownload)
		{
			[_forwarder connection:self downloadDidBegin:[download remotePath]];
		}
		if ([download delegateRespondsToTransferDidBegin])
		{
			[[download delegate] transferDidBegin:[download userInfo]];
		}
	}
	if ([formattedCommand rangeOfString:@"STOR"].location != NSNotFound)
	{
		CKInternalTransferRecord *download = [self currentDownload];
		if (_flags.didBeginUpload)
		{
			[_forwarder connection:self uploadDidBegin:[download remotePath]];
		}
		if ([download delegateRespondsToTransferDidBegin])
		{
			[[download delegate] transferDidBegin:[download userInfo]];
		}
	}
	
	[self sendData:[formattedCommand dataUsingEncoding:NSUTF8StringEncoding]];
}

/*!	The main communication between the foreground thread and the background thread.  Called by EITHER thread.
*/

/*!	Parse the response received from the server.  Called from the background thread.
*/
- (void)parseCommand:(NSString *)command
{
	NSScanner *scanner = [NSScanner scannerWithString:command];
	int code;
	[scanner scanInt:&code];
	
	// we need to consume everything until 'xxx '
	NSMutableString *buffer = [NSMutableString stringWithFormat:@"%@\n", command];
	BOOL atEnd = NO;
	NSRange r;
	NSString *strCode = [NSString stringWithFormat:@"%d ", code];
	
	if (![command hasPrefix:strCode])
	{
		if ((r = [_commandBuffer rangeOfString:strCode]).location != NSNotFound) {
			[buffer appendString:_commandBuffer];
			//need to drop out of the commandBuffer up to the new line.
			NSRange newLineRange;
			NSRange toEnd = NSMakeRange(r.location, [_commandBuffer length] - r.location);
			
			if ((newLineRange = [_commandBuffer rangeOfString:@"\r\n" 
													  options:NSCaseInsensitiveSearch 
														range:toEnd]).location != NSNotFound
				|| (newLineRange = [_commandBuffer rangeOfString:@"\n"
														 options:NSCaseInsensitiveSearch
														   range:toEnd]).location != NSNotFound)
				[_commandBuffer deleteCharactersInRange:NSMakeRange(0,newLineRange.location+newLineRange.length)];
			atEnd = YES;
		}
		else
		{
			[buffer appendString:_commandBuffer];
			[_commandBuffer deleteCharactersInRange:NSMakeRange(0, [_commandBuffer length])];
		}
		
		while (atEnd == NO)
		{
			[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
			NSData *data = [self availableData];
			
			if ([data length] > 0)
			{
				NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
				if (line)
					[buffer appendString:line];
				
				if ([line rangeOfString:strCode].location != NSNotFound)
					atEnd = YES;
				
				[line release];
			}
		}
	}

	if ([self transcript])
	{
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:([buffer hasSuffix:@"\n"] ? @"%@" : @"%@\n"), buffer] attributes:[AbstractConnection receivedAttributes]] autorelease]];
	}
	
	KTLog(ProtocolDomain, KTLogDebug, @"<< %@", command);
	
	switch (code)
	{
#pragma mark 100 series codes
		case 110: //restart file transfer marker reply 
		{
			//this was never called in testing so I don't know if it works properly
			//MARK uuuu = ssss (u user s server)
			if (GET_STATE == ConnectionUploadingFileState)
			{
				CKInternalTransferRecord *d = [self currentUpload];
				NSString *file = [d localPath];	// actual path to file, or destination name if from data
				NSString *remoteFile = [d remotePath];
				unsigned long long offset = [d offset];
				NSData *data = [d data];
				unsigned chunkLength = 0;
				const uint8_t bytes [kStreamChunkSize];
				_transferSent = 0;
				_transferCursor = offset;
				_transferLastPercent = 0;

				if (nil != data)	// use data.  (Note that data only can be as big as an insigned in, not a long long)
				{
					[self setReadData:data];
					[self setReadHandle:nil];		// make sure we're not also trying to read from file

					// Calculate size to transfer is total data size minus offset
					_transferSize = [data length] - offset;

					chunkLength = MAX([data length] - offset, kStreamChunkSize);						
					[data getBytes:&bytes range:NSMakeRange(offset, chunkLength)];
				}
				else	// use file
				{
					[self setReadData:nil];		// make sure we're not also trying to read from data
					[self setReadHandle:[NSFileHandle fileHandleForReadingAtPath:file]];
					NSAssert((nil != _readHandle), @"_readHandle is nil!");
					
					// Calculate size to transfer is total file size minus offset
					_transferSize = [[[[NSFileManager defaultManager] fileAttributesAtPath:file traverseLink:YES] objectForKey:NSFileSize] longLongValue] - offset;

					[_readHandle seekToFileOffset:offset]; 
					NSData *chunk = [_readHandle readDataOfLength:kStreamChunkSize];
					[chunk getBytes:&bytes];
					chunkLength = [chunk length];		// actual length of bytes read
				}
				
				//kick start the transfer
				[_dataSendStream write:bytes maxLength:chunkLength];
				_transferSent += chunkLength;
				_transferCursor += chunkLength;
				
				if (_flags.uploadProgressed)
				{
					[_forwarder connection:self upload:remoteFile sentDataOfLength:chunkLength];
				}
				if ([d delegateRespondsToTransferTransferredData])
				{
					[[d delegate] transfer:[d userInfo] transferredDataOfLength:chunkLength];
				}
				
				int percent = (float)_transferSent / ((float)_transferSize * 1.0);
				if (percent > _transferLastPercent)
				{
					if (_flags.uploadPercent)
					{
						[_forwarder connection:self upload:remoteFile progressedTo:[NSNumber numberWithInt:percent]];	// send message if we have increased %
					}
					if ([d delegateRespondsToTransferProgressedTo])
					{
						[[d delegate] transfer:[d userInfo] progressedTo:[NSNumber numberWithInt:percent]];
					}
				}
				_transferLastPercent = percent;
			}
			else if (GET_STATE == ConnectionDownloadingFileState)
			{
				
			}
			
			break;
		}
		case 120:
		{
			if (GET_STATE == ConnectionNotConnectedState)
			{
				if (_flags.error) {
					NSError *error = [NSError errorWithDomain:FTPErrorDomain 
														 code:code
													 userInfo:[NSDictionary dictionaryWithObjectsAndKeys: LocalizedStringInThisBundle(@"FTP Service Unavailable", @"FTP no service"), 
														 NSLocalizedDescriptionKey,
														 command, NSLocalizedFailureReasonErrorKey,
														 _connectionHost, @"host", nil]];
					[_forwarder connection:self didReceiveError:error];
				}
				[self setState:ConnectionNotConnectedState]; //don't really need.
			}
			break;
		}
		case 125: // Windows ftp server returns this code for starting a directory contents.
		{
			/*if (GET_STATE == ConnectionAwaitingDirectoryContentsState) 
			{
				KTLog(ProtocolDomain, KTLogDebug, @"Getting Directory Contents");
				break;
			}
			break;*/
		}
		case 150: //con about to open
		{
			if (GET_STATE == ConnectionUploadingFileState)
			{
				CKInternalTransferRecord *d = [self currentUpload];
				NSString *file = [d localPath];	// actual path to file, or destination name if from data
				NSString *remoteFile = [d remotePath];
				NSData *data = [d data];
				unsigned chunkLength = 0;
				const uint8_t *bytes;
				_transferLastPercent = 0;
				_transferSent = 0;
				_transferCursor = 0;
								
				if (nil != data)	// use data.  (Note that data only can be as big as an insigned in, not a long long)
				{
					[self setReadData:data];
					[self setReadHandle:nil];		// make sure we're not also trying to read from file
					
					_transferSize = [data length];
					chunkLength = MIN(_transferSize, kStreamChunkSize);						
					bytes = (uint8_t *)[data bytes];
				}
				else	// use file
				{
					[self setReadData:nil];		// make sure we're not also trying to read from data
					if (![[NSFileManager defaultManager] fileExistsAtPath:file])
					{
						NSString *str = [NSString stringWithFormat:@"File doesn't exist: %@", file];
						NSAssert(NO, str);
					}
					[self setReadHandle:[NSFileHandle fileHandleForReadingAtPath:file]];
					NSAssert((nil != _readHandle), @"_readHandle is nil!");
					NSData *chunk = [_readHandle readDataOfLength:kStreamChunkSize];
					bytes = (uint8_t *)[chunk bytes];
					chunkLength = [chunk length];		// actual length of bytes read

					NSNumber *size = [[[NSFileManager defaultManager] fileAttributesAtPath:file traverseLink:YES] objectForKey:NSFileSize];
					_transferSize = [size longValue];
				}
				
				//kick start the transfer
				[_dataSendStream write:bytes maxLength:chunkLength];
				_transferSent += chunkLength;
				_transferCursor += chunkLength;
				
				
				if ([d delegateRespondsToTransferTransferredData])
				{
					[[d delegate] transfer:[d userInfo] transferredDataOfLength:chunkLength];
				}
				
				if (_flags.uploadProgressed)
				{
					[_forwarder connection:self upload:remoteFile sentDataOfLength:chunkLength];
				}
				
				int percent = (float)_transferSent / ((float)_transferSize * 1.0);
				if (percent > _transferLastPercent)
				{
					if (_flags.uploadPercent)
					{
						[_forwarder connection:self upload:remoteFile progressedTo:[NSNumber numberWithInt:percent]];	// send message if we have increased %
					}
					if ([d delegateRespondsToTransferProgressedTo])
					{
						[[d delegate] transfer:[d userInfo] progressedTo:[NSNumber numberWithInt:percent]];
					}
				}
				_transferLastPercent = percent;
			}
			else if (GET_STATE == ConnectionDownloadingFileState)
			{
				CKInternalTransferRecord *download = [self currentDownload];
				NSFileManager *fm = [NSFileManager defaultManager];
				[fm removeFileAtPath:[download localPath] handler:nil];
				[fm createFileAtPath:[download localPath]
							contents:nil
						  attributes:nil];
				[self setWriteHandle:[NSFileHandle fileHandleForWritingAtPath:[download localPath]]];
				//start to read in the data to kick start it
				uint8_t *buf = (uint8_t *)malloc(sizeof(uint8_t) * kStreamChunkSize);
				int len = [_dataReceiveStream read:buf maxLength:kStreamChunkSize];
				if (len >= 0) {
					[_writeHandle writeData:[NSData dataWithBytesNoCopy:buf length:len freeWhenDone:NO]];
					_transferSent = len;
					
					if (_flags.downloadProgressed)
					{
						[_forwarder connection:self download:[download remotePath] receivedDataOfLength:len];
					}
					if ([download delegateRespondsToTransferTransferredData])
					{
						[[download delegate] transfer:[download userInfo] transferredDataOfLength:len];
					}
					int percent = (float)_transferSent / ((float)_transferSize * 1.0);
					if (_flags.downloadPercent)
					{
						[_forwarder connection:self download:[download remotePath] progressedTo:[NSNumber numberWithInt:percent]];
					}
					if ([download delegateRespondsToTransferProgressedTo])
					{
						[[download delegate] transfer:[download userInfo] progressedTo:[NSNumber numberWithInt:percent]];
					}
				}
// end this doesn't look right				
				//need to get the transfer size
				// 150 Opening connection (1652084 bytes)
				NSScanner *sizeScanner = [NSScanner scannerWithString:command];
				NSCharacterSet *bracketSet = [NSCharacterSet characterSetWithCharactersInString:@"()"];
				[sizeScanner scanUpToCharactersFromSet:bracketSet intoString:nil];
				if ( [sizeScanner scanLocation] < [command length] )
				{
					[sizeScanner setScanLocation:[sizeScanner scanLocation] + 1];
					[sizeScanner scanLongLong:&_transferSize];
				}
				else
				{
					_transferSize = LONG_MAX;
				}
				if ([[download delegate] isKindOfClass:[CKTransferRecord class]])
				{
					[(CKTransferRecord *)[download delegate] setSize:_transferSize];
				}
				
				free(buf);
			}
			else
			{
				//we'll clean the buffer
				[_buffer setLength:0];
			}
			break;
		}
#pragma mark 200 series codes
		case 200: //command OK
		{
			if (GET_STATE == ConnectionSettingPermissionsState)
			{
				if (_flags.permissions) {
					[_forwarder connection:self didSetPermissionsForFile:[_filePermissions objectAtIndex:0]];
				}
				[self dequeuePermissionChange];
			} 
			[self setState:ConnectionIdleState];
			break;
		}
		case 202: //command not implemented
		{
			//Just skip over and hopefully the next command will be ok.
			[self setState:ConnectionIdleState];
			break;
		}
		case 211:
		{
			if (_state == ConnectionSentFeatureRequestState)
			{
				//parse features
				if ([buffer rangeOfString:@"SIZE"].location != NSNotFound)
					_serverSupport.hasSize = YES;
				else
					_serverSupport.hasSize = NO;
				if ([buffer rangeOfString:@"ADAT"].location != NSNotFound)
					_serverSupport.hasADAT = YES;
				else
					_serverSupport.hasADAT = NO;
				if ([buffer rangeOfString:@"AUTH"].location != NSNotFound)
					_serverSupport.hasAUTH = YES;
				else
					_serverSupport.hasAUTH = NO;
				if ([buffer rangeOfString:@"CCC"].location != NSNotFound)
					_serverSupport.hasCCC = YES;
				else
					_serverSupport.hasCCC = NO;
				if ([buffer rangeOfString:@"CONF"].location != NSNotFound)
					_serverSupport.hasCONF = YES;
				else
					_serverSupport.hasCONF = NO;
				if ([buffer rangeOfString:@"ENC"].location != NSNotFound)
					_serverSupport.hasENC = YES;
				else
					_serverSupport.hasENC = NO;
				if ([buffer rangeOfString:@"MIC"].location != NSNotFound)
					_serverSupport.hasMIC = YES;
				else
					_serverSupport.hasMIC = NO;
				if ([buffer rangeOfString:@"PBSZ"].location != NSNotFound)
					_serverSupport.hasPBSZ = YES;
				else
					_serverSupport.hasPBSZ = NO;
				if ([buffer rangeOfString:@"PROT"].location != NSNotFound)
					_serverSupport.hasPROT = YES;
				else
					_serverSupport.hasPROT = NO;
				if ([buffer rangeOfString:@"MDTM"].location != NSNotFound)
					_serverSupport.hasMDTM = YES;
				else
					_serverSupport.hasMDTM = NO;
				if ([buffer rangeOfString:@"SITE"].location != NSNotFound)
					_serverSupport.hasSITE = YES;
				else
					_serverSupport.hasSITE = NO;
				if (_serverSupport.loggedIn == NO) {
					[self sendCommand:[NSString stringWithFormat:@"USER %@", _username]];
					[self setState:ConnectionSentUsernameState];
				} else {
					[self setState:ConnectionIdleState];
				}
			}
			break;
		}
		case 213:
		{
			if (GET_STATE == ConnectionSentSizeState)
			{
				[scanner scanLongLong:&_transferSize];
				_transferSent = 0;
				[self setState:ConnectionIdleState];
			}
			break;
		}
		case 215:
		{
			if (GET_STATE == FTPAwaitingRemoteSystemTypeState)
			{
				if ([[command lowercaseString] rangeOfString:@"windows"].location != NSNotFound)
				{
					_serverSupport.isMicrosoft = YES;
					[self setState:FTPChangeDirectoryListingStyle];
					[self sendCommand:@"SITE DIRSTYLE"];
					break;
				}
				else
				{
					_serverSupport.isMicrosoft = NO;
				}
			}
			[self setState:ConnectionIdleState];
			break;
		}
		case 220:
		{
			if (GET_STATE == ConnectionNotConnectedState && _serverSupport.loggedIn == NO)
			{				
				if ([command rangeOfString:@"Microsoft FTP Service"].location != NSNotFound ||
					[buffer rangeOfString:@"Microsoft FTP Service"].location != NSNotFound)
				{
					_serverSupport.isMicrosoft = YES;
				}
				else
				{
					_serverSupport.isMicrosoft = NO;
				}
				[self sendCommand:@"FEAT"];
				[self setState:ConnectionSentFeatureRequestState];
			}
			break;
		}
		case 221:
		{
			if (GET_STATE == ConnectionSentQuitState || GET_STATE == ConnectionSentDisconnectState)
			{
				[self closeStreams];
				
				[self setState:ConnectionNotConnectedState];
				_flags.isConnected = NO;
				if (_flags.didDisconnect) {
					[_forwarder connection:self didDisconnectFromHost:_connectionHost];
				}	
			}
			break;
		}
		//skip 225 (no transfer to ABOR)
		case 226:
		{
			_received226 = YES;
			if (_serverSupport.isActiveDataConn == YES) {
				[self closeDataConnection];
			}
			if (_dataSendStream == nil || _dataReceiveStream == nil)
			{
				[self setState:ConnectionIdleState];
			}
			break;
		}
		case 227:
		{
			if (GET_STATE == FTPSettingPassiveState)//parse the ip and port.
			{
				int i[6];
				int j;
				unsigned char n[6];
				char *buf = (char *)[command UTF8String];
				char *start = strchr(buf,'(');
				if ( !start )
					start = strchr(buf,'=');
				if ( !start ||
					 ( sscanf(start, "(%d,%d,%d,%d,%d,%d)",&i[0], &i[1], &i[2], &i[3], &i[4], &i[5]) != 6 &&
					   sscanf(start, "=%d,%d,%d,%d,%d,%d", &i[0], &i[1], &i[2], &i[3], &i[4], &i[5]) != 6 ) )
				{
					_serverSupport.canUsePASV = NO;
					if (_flags.error)
					{
						NSError *err = [NSError errorWithDomain:FTPErrorDomain 
														   code:FTPErrorNoDataModes 
													   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"All data connection modes have been exhausted. Check with the server administrator.", @"FTP no data stream types available"), 
														   NSLocalizedDescriptionKey, 
														   command, NSLocalizedFailureReasonErrorKey,
														   nil]];
						[_forwarder connection:self didReceiveError:err];
					}
					_state = ConnectionSentQuitState;
					[self sendCommand:@"QUIT"];
				}
				for (j=0; j<6; j++)
				{
					n[j] = (unsigned char) (i[j] & 0xff);
				}
				int port = i[4] << 8 | i[5];
				//port = ntohs(i[5] << 8 | i[4]);
				NSString *hostString = [NSString stringWithFormat:@"%d.%d.%d.%d", i[0], i[1], i[2], i[3]];
				NSHost *host = [NSHost hostWithAddress:hostString];
				[host setValue:[NSArray arrayWithObject:_connectionHost] forKey:@"names"]; // KVC hack
				
				[self closeDataStreams];
				[self setState:FTPAwaitingDataConnectionToOpen];
				[self openDataStreamsToHost:host port:port];
			}
			break;
		}
		case 229:
		{
			if (GET_STATE == FTPSettingEPSVState)
			{
				//get the port number
				int port = 0;
				char *cmd = (char *)[command UTF8String];
				char *start = strchr(cmd,'|');
				if ( !start || sscanf(start, "|||%d|", &port) != 1)
				{
					_serverSupport.canUseEPSV = NO;
					[self pushCommandOnHistoryQueue:[ConnectionCommand command:@"EPRT"
																	awaitState:ConnectionIdleState
																	 sentState:FTPSettingEPRTState
																	 dependant:nil
																	  userInfo:nil]];
					_state = FTPSettingEPRTState;
					[self sendCommand:@"EPRT"];
				}
				NSHost *host = [NSHost hostWithName:_connectionHost];
				[host setValue:[NSArray arrayWithObject:_connectionHost] forKey:@"names"]; // KVC hack
					
				[self closeDataStreams];
				[self setState:FTPAwaitingDataConnectionToOpen];
				[self openDataStreamsToHost:host port:port];
			}
			break;
		}
		case 230:
		{
			if (GET_STATE == ConnectionSentPasswordState) //Login successful set up session
			{	
				// Queue up the commands we want to insert in the queue before notifying client we're connected
				[_commandQueue insertObject:[ConnectionCommand command:@"SYST"
															awaitState:ConnectionIdleState
															 sentState:FTPAwaitingRemoteSystemTypeState
															 dependant:nil
															  userInfo:nil]
									atIndex:0];
				[_commandQueue insertObject:[ConnectionCommand command:@"PWD"
															awaitState:ConnectionIdleState
															 sentState:ConnectionAwaitingCurrentDirectoryState
															 dependant:nil
															  userInfo:nil]
									atIndex:0];
				// We get the current directory -- and we're notified of a change directory ... so we'll know what directory
				// we are starting in.

				[self setState:ConnectionIdleState];
			}
			if (GET_STATE == ConnectionSentAccountState)
			{
				[self sendCommand:[NSString stringWithFormat:@"PASS %@", _password]];
				[self setState:ConnectionSentPasswordState];
			}
			break;
		}
		case 250:
		{
			if (GET_STATE == ConnectionDeleteFileState)
			{
				if (_flags.deleteFile) {
					[_forwarder connection:self didDeleteFile:[_fileDeletes objectAtIndex:0]];
				}
				[_fileDeletes removeObjectAtIndex:0];
			}
			else if (GET_STATE == ConnectionDeleteDirectoryState)
			{
				// Uses same _fileDeletes queue, hope that's safe to do.  (Any chance one could get ahead of another?)
				if (_flags.deleteDirectory) {
					[_forwarder connection:self didDeleteDirectory:[_fileDeletes objectAtIndex:0]];
				}
				[_fileDeletes removeObjectAtIndex:0];
			}
			else if (GET_STATE == ConnectionAwaitingRenameState)
			{
				if (_flags.rename) {
					[_forwarder connection:self didRename:[_fileRenames objectAtIndex:0] to:[_fileRenames objectAtIndex:1]];
				}
				[_fileRenames removeObjectAtIndex:0];
				[_fileRenames removeObjectAtIndex:0];
			}
			[self setState:ConnectionIdleState];
			break;
		}
		case 253:
		{		
			if (GET_STATE == ConnectionSettingPermissionsState)
			{
				[self setState:ConnectionIdleState];
				break;
			}
		}
		case 257:
		{
			if (GET_STATE == ConnectionAwaitingCurrentDirectoryState) //scan for the directory
			{
				NSString *path = [self scanBetweenQuotes:command];
				if (!path || [path length] == 0)
				{
					path = [[[[self lastCommand] command] substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
				}
				[self setCurrentPath:path];
				
				if (_rootPath == nil) 
					_rootPath = [[NSString stringWithString:path] retain];
				
				if (!_flags.isConnected)
				{
					if (_flags.didConnect) {
						[_forwarder connection:self didConnectToHost:_connectionHost];
					}
					
					_flags.isConnected = YES;
					[self setState:ConnectionIdleState];
					break;
				}
				
				if (_flags.changeDirectory) {
					[_forwarder connection:self didChangeToDirectory:_currentPath];
				}
				[self setState:ConnectionIdleState];
			}
			else if (GET_STATE == ConnectionCreateDirectoryState)
			{
				if (_flags.createDirectory)
				{
					NSString *path = [self scanBetweenQuotes:command];
					if (!path || [path length] == 0)
					{
						path = [[[[self lastCommand] command] substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
					}
					[_forwarder connection:self didCreateDirectory:path];
				}
				[self setState:ConnectionIdleState];
			}
			break;
		}
#pragma mark 300 series codes
		case 331: //need password
		{
			if (GET_STATE == ConnectionSentUsernameState)
			{
				[self sendCommand:[NSString stringWithFormat:@"PASS %@", _password]];
				[self setState:ConnectionSentPasswordState];
			}
			break;
		}
		case 332: //need account
		{
			if (_flags.needsAccount)
			{
				NSString *account;
				account = [_forwarder connection:self needsAccountForUsername:_username];
				if (account)
				{
					[self sendCommand:[NSString stringWithFormat:@"ACCT %@", account]];
					[self setState:ConnectionSentAccountState];
				}
			}
		}
		case 350:
		{
			if (GET_STATE == ConnectionRenameFromState)
			{
				[self setState:ConnectionRenameToState];
			}
			else if (GET_STATE == ConnectionSentOffsetState)
			{
				[self setState:ConnectionIdleState];
			}
			break;
		}
#pragma mark 400 series codes
		case 421: //service timed out.
		{
			[self closeDataStreams];
			_flags.isConnected = NO;
			
			if (_flags.didDisconnect) {
				[_forwarder connection:self didDisconnectFromHost:[self host]];
			}
			[self setState:ConnectionNotConnectedState]; 
			break;
		}
		case 425:
		{
			// 425 can't open data connection
			if (GET_STATE == ConnectionAwaitingDirectoryContentsState ||
				GET_STATE == ConnectionUploadingFileState ||
				GET_STATE == ConnectionDownloadingFileState)
			{
				ConnectionCommand *last = [self lastCommand];
				ConnectionState lastState = [[[self commandHistory] objectAtIndex:1] sentState];
				
				if (lastState == FTPSettingEPSVState)
				{
					_serverSupport.canUseEPSV = NO;
					[self closeDataStreams];
					[self sendCommand:@"DATA_CON"];
					[self pushCommandOnCommandQueue:last];
				}
				else if (lastState == FTPSettingEPRTState)
				{
					_serverSupport.canUseEPRT = NO;
					[self closeDataStreams];
					[self sendCommand:@"DATA_CON"];
					[self pushCommandOnCommandQueue:last];
				}
				else if (lastState == FTPSettingActiveState)
				{
					_serverSupport.canUseActive = NO;
					[self closeDataStreams];
					[self sendCommand:@"DATA_CON"];
					[self pushCommandOnCommandQueue:last];
				}
				else if (lastState == FTPSettingPassiveState)
				{
					_serverSupport.canUsePASV = NO;
					[self closeDataStreams];
					[self sendCommand:@"DATA_CON"];
					[self pushCommandOnCommandQueue:last];
				}
			}
			else
			{
				//technically we should never get here unless the ftp server doesn't support pasv or epsv
				KTLog(ProtocolDomain, KTLogError, @"FTP Internal Error: %@", command);
				[self setState:ConnectionIdleState];
			}
			break;
		}
		case 426: //con closed
		{
			//We don handle this here because we handle the data port connection closure in the 
			// NSStream event management.
			// However, send our abort callback.
			if (_flags.cancel) {
				[_forwarder connectionDidCancelTransfer:self];
			}
				
			break;
		}
		case 450: //file in use
		{
			if (_flags.error) {
				NSError *error = [NSError errorWithDomain:FTPErrorDomain
													 code:code
												 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"File in Use", @"FTP file in use"),
													 NSLocalizedDescriptionKey,
													 command, NSLocalizedFailureReasonErrorKey, nil]];
				[_forwarder connection:self didReceiveError:error];
			}
			[self setState:ConnectionIdleState];
		}
		case 451: //local error caused abortion
		{
			//don't know why so will pass it to the delegate
			if (_flags.error) {
				NSError *error = [NSError errorWithDomain:FTPErrorDomain
													 code:code
												 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"Action Aborted. Local Error", @"FTP Abort"),
													 NSLocalizedDescriptionKey,
													 command, NSLocalizedFailureReasonErrorKey]];
				[_forwarder connection:self didReceiveError:error];
			}
				
			[self setState:ConnectionIdleState];
			break;
		}
		case 452: //no storage space
		{
			if (GET_STATE == ConnectionUploadingFileState)
			{
				if (_flags.error) {
					NSError *error = [NSError errorWithDomain:FTPErrorDomain
														 code:code
													 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"No Storage Space Available", @"FTP Error"),
														 NSLocalizedDescriptionKey,
														 command, NSLocalizedFailureReasonErrorKey,
														 nil]];
					[_forwarder connection:self didReceiveError:error];
				}
				[self sendCommand:@"ABOR"];
			}
			break;
		}
#pragma mark 500 series codes 
		case 500: //Syntax Error
		case 501: //Syntax Error in arguments
		case 502: //Command not implemented
		{
			if (GET_STATE == FTPSettingEPSVState)
			{
				_serverSupport.canUseEPSV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingEPRTState)
			{
				_serverSupport.canUseEPRT = NO;
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingActiveState)
			{
				_serverSupport.canUseActive = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingPassiveState)
			{
				_serverSupport.canUsePASV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == ConnectionSentFeatureRequestState)
			{
				[self setState:ConnectionSentUsernameState];
				[self sendCommand:[NSString stringWithFormat:@"USER %@", [self username]]];
				break;
			}
			if (GET_STATE == ConnectionSettingPermissionsState)
			{
				[self setState:ConnectionIdleState];
				break;
			}
			if (GET_STATE == FTPAwaitingRemoteSystemTypeState)
			{
				[self setState:ConnectionIdleState];
				break;
			}
			if (GET_STATE == FTPChangeDirectoryListingStyle)
			{
				[self setState:ConnectionIdleState];
				break;
			}
			if (GET_STATE == ConnectionChangingDirectoryState)
			{
				if (_flags.error)
				{
					NSError *err = [NSError errorWithDomain:FTPErrorDomain
													   code:ConnectionErrorChangingDirectory
												   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"Failed to change to directory", @"Bad ftp command"),
													   NSLocalizedDescriptionKey,
													   command, NSLocalizedFailureReasonErrorKey, nil]];
					[_forwarder connection:self didReceiveError:err];
				}
				
				[self setState:ConnectionIdleState];
				break;
			}
			break;
		}
		case 503: //Bad sequence of commands
		{
			//This is an internal error in the syntax of the commands and arguments sent.
			//We should never get to this state as we should construct commands correctly.
			if (GET_STATE != ConnectionSentFeatureRequestState)
			{
				KTLog(ProtocolDomain, KTLogError, @"FTP Internal Error: %@", command);
				// We should just see if we can process the next command
				[self setState:ConnectionIdleState];
				break;
			}
			else
			{
				[self setState:ConnectionSentUsernameState];
				[self sendCommand:[NSString stringWithFormat:@"USER %@", [self username]]];
				break;
			}
		}
		case 521:
		{
			if (GET_STATE == ConnectionCreateDirectoryState)
			{
				if (_flags.error && !_flags.isRecursiveUploading)
				{
					NSString *error = LocalizedStringInThisBundle(@"Create directory operation failed", @"FTP Create directory error");
					NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
					if ([command rangeOfString:@"exists"].location != NSNotFound) 
					{
						[userInfo setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
						if ([command rangeOfString:@":"].location != NSNotFound)
						{
							[userInfo setObject:[command substringWithRange:NSMakeRange(4, [command rangeOfString:@":"].location - 4)] forKey:ConnectionDirectoryExistsFilenameKey];
						}
					}
					[userInfo setObject:error forKey:NSLocalizedDescriptionKey];
					[userInfo setObject:command forKey:NSLocalizedFailureReasonErrorKey];
					NSError *err = [NSError errorWithDomain:FTPErrorDomain
													   code:code
												   userInfo:userInfo];
					[_forwarder connection:self didReceiveError:err];
				}
				[self setState:ConnectionIdleState];
			}
			break;	
		}
		case 522:
		{
			_serverSupport.canUseEPRT = NO;
			[self sendCommand:@"DATA_CON"];
			break;
		}
		case 530:
		{
			if (GET_STATE == ConnectionSentPasswordState)//bad password
			{
				if (_flags.badPassword) {
					[_forwarder connectionDidSendBadPassword:self];
				}
					
			}
			else if (GET_STATE == ConnectionSentAccountState) //bad account
			{
				if (_flags.error) {
					NSError *error = [NSError errorWithDomain:FTPErrorDomain
														 code:code
													 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"Invalid Account name", @"FTP Error"),
														 NSLocalizedDescriptionKey,
														 command, NSLocalizedFailureReasonErrorKey,
														 nil]];
					[_forwarder connection:self didReceiveError:error];
				}
			}
			else if (GET_STATE == ConnectionSentFeatureRequestState)
			{
				// the server doesn't support FEAT before login
				[self sendCommand:[NSString stringWithFormat:@"USER %@", [self username]]];
				[self setState:ConnectionSentUsernameState];
				return;
			}
			else //any other error here is that we are not logged in
			{
				if (_flags.error) {
					NSError *error = [NSError errorWithDomain:FTPErrorDomain
														 code:code
													 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"Not Logged In", @"FTP Error"),
														 NSLocalizedDescriptionKey,
														 command, NSLocalizedFailureReasonErrorKey,
														 nil]];
					[_forwarder connection:self didReceiveError:error];
				}
			}
			[self sendCommand:@"QUIT"];
			[self setState:ConnectionSentQuitState];
			break;
		}
		case 532:
		{
			if (GET_STATE == ConnectionUploadingFileState)
			{
				if (_flags.error) {
					NSError *error = [NSError errorWithDomain:FTPErrorDomain
														 code:code
													 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"You need an Account to Upload Files", @"FTP Error"),
														 NSLocalizedDescriptionKey,
														 command, NSLocalizedFailureReasonErrorKey,
														 nil]];
					[_forwarder connection:self didReceiveError:error];
				}
				[self setState:ConnectionIdleState];
			}
		}
		case 550: //directory or file does not exist
		{
			NSString *error = nil;
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			
			if (GET_STATE == ConnectionUploadingFileState)
			{
				error = [NSString stringWithFormat:LocalizedStringInThisBundle(@"You do not have access to write file %@", @"FTP file upload error"), [[_uploadQueue objectAtIndex:0] objectForKey:QueueUploadRemoteFileKey]];
			}
			else if (GET_STATE == ConnectionDownloadingFileState)
			{
				error = [NSString stringWithFormat:LocalizedStringInThisBundle(@"File %@ does not exist on server", @"FTP file download error"), [[_downloadQueue objectAtIndex:0] objectForKey:QueueDownloadRemoteFileKey]];
			}
			else if (GET_STATE == ConnectionCreateDirectoryState)
			{
				error = LocalizedStringInThisBundle(@"Create directory operation failed", @"FTP Create directory error");
				//Some servers won't say that the directory exists. Once I get peer connections going, I will be able to ask the
				//peer if the dir exists for confirmation until then we will make the assumption that it exists.
				//if ([command rangeOfString:@"exists"].location != NSNotFound) {
					[userInfo setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
					[userInfo setObject:[[[[self lastCommand] command] substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
								 forKey:ConnectionDirectoryExistsFilenameKey];
					//[userInfo setObject:[command substringWithRange:NSMakeRange(4, [command rangeOfString:@":"].location - 4)] forKey:ConnectionDirectoryExistsFilenameKey];
				//}
			}
			else if (GET_STATE == ConnectionDeleteFileState)
			{
				error = [NSString stringWithFormat:@"%@: %@", LocalizedStringInThisBundle(@"Failed to delete file", @"couldn't delete the file"), [[self currentDirectory] stringByAppendingPathComponent:[self currentDeletion]]];
				[self dequeueDeletion];
			}
			else if (GET_STATE == ConnectionDeleteDirectoryState)
			{
				error = [NSString stringWithFormat:@"%@: %@", LocalizedStringInThisBundle(@"Failed to delete directory", @"couldn't delete the file"), [[self currentDirectory] stringByAppendingPathComponent:[self currentDeletion]]];
				[self dequeueDeletion];
			}
			else if (GET_STATE == FTPChangeDirectoryListingStyle || ConnectionSettingPermissionsState)
			{
				[self setState:ConnectionIdleState];
				break;
			}
			else
			{
				error = LocalizedStringInThisBundle(@"File / Directory does not exist", @"FTP error");
			}
			
			[userInfo setObject:error forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:command forKey:NSLocalizedFailureReasonErrorKey];
			if (_flags.error) {
				NSError *err = [NSError errorWithDomain:FTPErrorDomain
												   code:code
											   userInfo:userInfo];
				[_forwarder connection:self didReceiveError:err];
			}

			[self setState:ConnectionIdleState];
			break;
		}
		case 551: //request aborted. page type unknown
		{
			if (_flags.error) {
				NSError *error = [NSError errorWithDomain:FTPErrorDomain
													 code:code
												 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"Request Aborted. Page Type Unknown", @"FTP Error"), 
													 NSLocalizedDescriptionKey,
													 command, NSLocalizedFailureReasonErrorKey,
													 nil]];
				[_forwarder connection:self didReceiveError:error];
			}		
			[self setState:ConnectionIdleState];
			break;
		}
		case 552: //request aborted quota exceeded
		{
			if (_flags.error) {
				NSError *error = [NSError errorWithDomain:FTPErrorDomain
													 code:code
												 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"Cannot Upload File. Storage quota on server exceeded", @"FTP upload error"), 
													 NSLocalizedDescriptionKey,
													 command, NSLocalizedFailureReasonErrorKey,
													 nil]];
				[_forwarder connection:self didReceiveError:error];
			}
			[self setState:ConnectionIdleState];
			break;
		}
		case 553:
		{
			if (_flags.error) {
				NSError *error = [NSError errorWithDomain:FTPErrorDomain
													 code:code
												 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"Filename not Allowed", @"FTP Upload error"),
																					  NSLocalizedDescriptionKey,
													 command, NSLocalizedFailureReasonErrorKey,
													 nil]];
				[_forwarder connection:self didReceiveError:error];
			}
			break;
		}
	}
	
}

#pragma mark -
#pragma mark Stream Handling

- (void)threadedDisconnect
{
	_state = ConnectionSentDisconnectState;
	[self sendCommand:@"QUIT"];
}

- (void)threadedAbort
{
	[self sendCommand:@"ABOR"];
	_isForceDisconnecting = YES;
	[self closeDataConnection];
}

/*!	Stream delegate method.  "The delegate receives this message only if the stream object is scheduled on a runloop. The message is sent on the stream object‚Äôs thread."
*/
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{	
	if (aStream == _dataReceiveStream)
	{
		[self handleDataReceivedEvent:eventCode];
	}
	else if (aStream == _dataSendStream)
	{
		[self handleDataSendStreamEvent:eventCode];
	}
	else
	{
		[super stream:aStream handleEvent:eventCode];
	}
}


/*!	Stream delegate support method.  
*/
- (void)processReceivedData:(NSData *)data
{
	NSRange newLinePosition;

	NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	[_commandBuffer appendString:str];
	[str release];
				
	while ((newLinePosition=[_commandBuffer rangeOfString:@"\r\n"]).location != NSNotFound ||
		   (newLinePosition=[_commandBuffer rangeOfString:@"\n"]).location != NSNotFound)
	{
		NSString *cmd = [_commandBuffer substringToIndex:newLinePosition.location];
		[_commandBuffer deleteCharactersInRange:NSMakeRange(0,newLinePosition.location+newLinePosition.length)]; // delete the parsed part
		[self parseCommand:cmd]; // parse first line of the buffer
	}
}

- (void)handleDataReceivedEvent:(NSStreamEvent)eventCode
{
	switch (eventCode)
	{
		case NSStreamEventHasBytesAvailable:
		{
			uint8_t *buf = (uint8_t *)malloc(sizeof (uint8_t) * kStreamChunkSize);
			int len = [_dataReceiveStream read:buf maxLength:kStreamChunkSize];
			
			if (len >= 0)
			{			
				KTLog(StreamDomain, KTLogDebug, @"FTPD << %d bytes", len);

				if (GET_STATE == ConnectionDownloadingFileState)
				{
					CKInternalTransferRecord *download = [self currentDownload];
					NSString *file = [download remotePath];
					[_writeHandle writeData:[NSData dataWithBytesNoCopy:buf length:len freeWhenDone:NO]];
					_transferSent += len;
					
					//if ([self isAboveNotificationTimeThreshold:[NSDate date]]) 
					{
						if (_transferSize > 0)
						{
							int percent = 100.0 * (float)_transferSent / ((float)_transferSize * 1.0);
							if (percent > [[[download delegate] objectForKey:QueueDownloadTransferPercentReceived] intValue])
							{
								if ([download delegateRespondsToTransferProgressedTo])
								{
									[[download delegate] transfer:[download userInfo] progressedTo:[NSNumber numberWithInt:percent]];
								}
								if (_flags.downloadPercent)
								{
									[_forwarder connection:self download:file progressedTo:[NSNumber numberWithInt:percent]];	// send message if we have increased %
								}
								[[download delegate] setObject:[NSNumber numberWithInt:percent] forKey:QueueDownloadTransferPercentReceived];
							}
						}
						
						if (_flags.downloadProgressed) {
							[_forwarder connection:self download:file receivedDataOfLength:len];
						}
						
						if ([download delegateRespondsToTransferTransferredData])
						{
							[[download delegate] transfer:[download userInfo] transferredDataOfLength:len];
						}
					}
				}
				else {
					[_dataBuffer appendBytes:buf length:len];
				}
			}
			free(buf);
			break;
		}
		case NSStreamEventOpenCompleted:
		{
			KTLog(StreamDomain, KTLogDebug, @"FTP Data receive stream opened");
			[_openStreamsTimeout invalidate];
			[_openStreamsTimeout release];
			_openStreamsTimeout = nil;
			break;
		}
		case NSStreamEventErrorOccurred:
		{
			if ([self transcript])
			{
				[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"Receive Stream Error: %@\n", [_receiveStream streamError]] 
																		  attributes:[AbstractConnection sentAttributes]] autorelease]];
			}
			

			KTLog(StreamDomain, KTLogError, @"receive error %@", [_receiveStream streamError]);
			KTLog(ProtocolDomain, KTLogDebug, @"error state received = %@", [self stateName:GET_STATE]);
			// we don't want the error to go to the delegate unless we fail on setting the active con
			/* Some servers when trying to test PASV can crap out and throw an error */
			if (GET_STATE == FTPSettingEPSVState) 
			{
				_serverSupport.canUseEPSV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingEPRTState) 
			{
				_serverSupport.canUseEPRT = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingActiveState) 
			{
				_serverSupport.canUseActive = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingPassiveState) 
			{
				_serverSupport.canUsePASV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			
			// if uploading, skip the transfer
			if (GET_STATE == ConnectionUploadingFileState || 
				GET_STATE == ConnectionDownloadingFileState ||
				GET_STATE == FTPAwaitingDataConnectionToOpen ||
				GET_STATE == ConnectionAwaitingDirectoryContentsState) 
			{
				if (GET_STATE == ConnectionUploadingFileState)
				{
					CKInternalTransferRecord *rec = [self currentUpload];
					if ([rec delegateRespondsToError])
					{
						[[rec delegate] transfer:[rec userInfo] receivedError:[_receiveStream streamError]];
					}
				}
				if (GET_STATE == ConnectionDownloadingFileState)
				{
					CKInternalTransferRecord *rec = [self currentDownload];
					if ([rec delegateRespondsToError])
					{
						[[rec delegate] transfer:[rec userInfo] receivedError:[_receiveStream streamError]];
					}
				}
				//This will most likely occur when there is a misconfig of the server and we cannot open a data connection so we have unroll the command stack
				[self closeDataStreams];
				NSArray *history = [self commandHistory];
				//NSDictionary *conCommand = [history objectAtIndex:1];
			//	NSLog(@"command history:\n%@", [[self commandHistory] description]);
				ConnectionCommand *lastCommand = [history objectAtIndex:0];
				ConnectionState lastState = [lastCommand sentState];
				
				if (lastState == FTPSettingEPSVState) 
				{
					_serverSupport.canUseEPSV = NO;
					[self sendCommand:@"DATA_CON"];
					break;
				} 
				else if (lastState == FTPSettingEPRTState) 
				{
					_serverSupport.canUseEPRT = NO;
					[self sendCommand:@"DATA_CON"];
					break;
				} 
				else if (lastState == FTPSettingActiveState)
				{
					_serverSupport.canUseActive = NO;
					[self sendCommand:@"DATA_CON"];
					break;
				}
				else if (lastState == FTPSettingPassiveState) 
				{
					_serverSupport.canUseActive = NO;
					[self sendCommand:@"DATA_CON"];
				}
			}
			else 
			{
				KTLog(StreamDomain, KTLogDebug, @"NSStreamEventErrorOccurred: %@", [_dataReceiveStream streamError]);
			}
			
			break;
		}
		case NSStreamEventEndEncountered:
		{
			KTLog(StreamDomain, KTLogDebug, @"FTP Data receive stream ended");
			[self closeDataConnection];
			break;
		}
		case NSStreamEventNone:
		{
			break;
		}
		case NSStreamEventHasSpaceAvailable:
		{
			break;
		}
	}
}

- (void)handleDataSendStreamEvent:(NSStreamEvent)eventCode
{
	switch (eventCode)
	{
		case NSStreamEventHasBytesAvailable: //should never be called
		{
			break;
		}
		case NSStreamEventOpenCompleted:
		{
			[_openStreamsTimeout invalidate];
			[_openStreamsTimeout release];
			_openStreamsTimeout = nil;
			
			KTLog(StreamDomain, KTLogDebug, @"FTP Data send stream opened");
			
			if (!_serverSupport.isActiveDataConn)
				[self setState:ConnectionIdleState];
			break;
		}
		case NSStreamEventErrorOccurred:
		{
			if ([self transcript])
			{
				[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"Send Stream Error: %@\n", [_receiveStream streamError]] 
																		  attributes:[AbstractConnection sentAttributes]] autorelease]];
			}
			KTLog(StreamDomain, KTLogDebug, @"send error %@", [_sendStream streamError]);
			// we don't want the error to go to the delegate unless we fail on setting the active con
			/* Some servers when trying to test PASV can crap out and throw an error */
			if (GET_STATE == FTPSettingEPSVState) 
			{
				_serverSupport.canUseEPSV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingEPRTState) 
			{
				_serverSupport.canUseEPRT = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingActiveState) 
			{
				_serverSupport.canUseActive = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingPassiveState) 
			{
				_serverSupport.canUsePASV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}			
			// if uploading, skip the transfer
			if (GET_STATE == ConnectionUploadingFileState || 
				GET_STATE == ConnectionDownloadingFileState ||
				GET_STATE == FTPAwaitingDataConnectionToOpen ||
				GET_STATE == ConnectionAwaitingDirectoryContentsState) {
				if (GET_STATE == ConnectionUploadingFileState)
				{
					CKInternalTransferRecord *rec = [self currentUpload];
					if ([rec delegateRespondsToError])
					{
						[[rec delegate] transfer:[rec userInfo] receivedError:[_sendStream streamError]];
					}
				}
				if (GET_STATE == ConnectionDownloadingFileState)
				{
					CKInternalTransferRecord *rec = [self currentDownload];
					if ([rec delegateRespondsToError])
					{
						[[rec delegate] transfer:[rec userInfo] receivedError:[_sendStream streamError]];
					}
				}
				//This will most likely occur when there is a misconfig of the server and we cannot open a data connection so we have unroll the command stack
				[self closeDataStreams];
				NSArray *history = [self commandHistory];
				//NSDictionary *conCommand = [history objectAtIndex:1];
				//	NSLog(@"command history:\n%@", [[self commandHistory] description]);
				ConnectionCommand *lastCommand = [history objectAtIndex:0];
				ConnectionState lastState = [lastCommand sentState];
				
				if (lastState == FTPSettingEPSVState) 
				{
					_serverSupport.canUseEPSV = NO;
					[self sendCommand:@"DATA_CON"];
					break;
				} 
				else if (lastState == FTPSettingEPRTState) 
				{
					_serverSupport.canUseEPRT = NO;
					[self sendCommand:@"DATA_CON"];
					break;
				} 
				else if (lastState == FTPSettingActiveState)
				{
					_serverSupport.canUseActive = NO;
					[self sendCommand:@"DATA_CON"];
					break;
				}
				else if (lastState == FTPSettingPassiveState) 
				{
					_serverSupport.canUseActive = NO;
					[self sendCommand:@"DATA_CON"];
				}
			}
			else {
				KTLog(StreamDomain, KTLogDebug, @"NSStreamEventErrorOccurred: %@", [_dataReceiveStream streamError]);
				if (_flags.error) {
					[_forwarder connection:self didReceiveError:[_dataReceiveStream streamError]];	
				}
			}
			
			break;
		}
		case NSStreamEventEndEncountered:
		{
			KTLog(StreamDomain, KTLogDebug, @"FTP Data send stream ended");
			[self closeDataConnection];
			break;
		}
		case NSStreamEventNone:
		{
			break;
		}
		case NSStreamEventHasSpaceAvailable:
		{
			if (GET_STATE == ConnectionUploadingFileState)
			{
				unsigned chunkLength = 0;
				const uint8_t *bytes = NULL;
				CKInternalTransferRecord *upload = [self currentUpload];
				NSString *remoteFile = [upload remotePath];
				
				if (nil != _readHandle)		// reading from file handle
				{
					NSData *chunk = [_readHandle readDataOfLength:kStreamChunkSize];
					bytes = (uint8_t *)[chunk bytes];
					chunkLength = [chunk length];
				}
				else if (nil != _readData)
				{
					chunkLength = MIN([_readData length] - _transferCursor, kStreamChunkSize);	
					bytes = (uint8_t *)[[_readData subdataWithRange:NSMakeRange(_transferCursor, chunkLength)] bytes];
				}

				if (0 != _transferSize && (chunkLength > 0 || _transferSent == _transferSize)) //should only send 0 bytes to initiate a connection shutdown.  Do nothing if nothing to transfer yet.
				{
					[_dataSendStream write:bytes maxLength:chunkLength];
					_transferSent += chunkLength;
					_delegateSizeBuffer += chunkLength;
					_transferCursor += chunkLength;
					
					//if ([self isAboveNotificationTimeThreshold:[NSDate date]]) {
					if ([upload delegateRespondsToTransferTransferredData])
					{
						[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:_delegateSizeBuffer];
					}
						if (_flags.uploadProgressed)
						{
							[_forwarder connection:self upload:remoteFile sentDataOfLength:_delegateSizeBuffer];
							_delegateSizeBuffer = 0;
						}
					//}
					int percent = 100.0 * (float)_transferSent / ((float)_transferSize * 1.0);
					if (percent > _transferLastPercent)
					{
						if (_flags.uploadPercent)
						{
							[_forwarder connection:self upload:remoteFile progressedTo:[NSNumber numberWithInt:percent]];	// send message if we have increased %
						}
						if ([upload delegateRespondsToTransferProgressedTo])
						{
							[[upload delegate] transfer:[upload userInfo] progressedTo:[NSNumber numberWithInt:percent]];
						}
					}
					_transferLastPercent = percent;
				}				
			}
			break;
		}
		default:
		{
			KTLog(StreamDomain, KTLogDebug, @"Composite Event Code!  Need to deal with this!");
			break;
		}
	}
}

- (void)closeDataConnection
{
	KTLog(StreamDomain, KTLogDebug, @"closeDataConnection");
	[self closeDataStreams];
	
	// no delegate notifications if we force disconnected the connection
	if (_isForceDisconnecting)
	{
		_isForceDisconnecting = NO;
		return;
	}
	
	if (GET_STATE == ConnectionDownloadingFileState)
	{
		CKInternalTransferRecord *download = [[self currentDownload] retain];
		[self dequeueDownload];
		
		if (_flags.downloadFinished)
		{
			[_forwarder connection:self downloadDidFinish:[download remotePath]];
		}
		if ([download delegateRespondsToTransferDidFinish])
		{
			[[download delegate] transferDidFinish:[download userInfo]];
		}
		[_writeHandle closeFile];
		[self setWriteHandle:nil];
		
		if (_received226)
		{
			[self setState:ConnectionIdleState];
		}
		[download release];
	}
	else if (GET_STATE == ConnectionUploadingFileState)
	{
		CKInternalTransferRecord *upload = [[self currentUpload] retain];
		[self dequeueUpload];
		
		if (_flags.uploadFinished) 
		{
			[_forwarder connection:self uploadDidFinish:[upload remotePath]];
		}
		if ([upload delegateRespondsToTransferDidFinish])
		{
			[[upload delegate] transferDidFinish:[upload userInfo]];
		}
		[self setReadData:nil];
		[self setReadHandle:nil];
		_transferSize = 0;
		
		if (_received226)
		{
			[self setState:ConnectionIdleState];
		}
		[upload release];
	}
	else if (GET_STATE == ConnectionAwaitingDirectoryContentsState)
	{
		NSString *results = [[NSString alloc] initWithData:_dataBuffer encoding:NSUTF8StringEncoding];
		
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:results 
																  attributes:[AbstractConnection dataAttributes]] autorelease]];

		NSArray *contents = [self parseLines:results];
		
		KTLog(ParsingDomain, KTLogDebug, @"Contents of Directory %@:\n%@", _currentPath, [contents shortDescription]);
		
		[self cacheDirectory:_currentPath withContents:contents];
		
		if (_flags.directoryContents)
		{
			[_forwarder connection:self didReceiveContents:contents ofDirectory:_currentPath];
		}
		[results release];
		[_dataBuffer setLength:0];
		if (_received226)
		{
			[self setState:ConnectionIdleState];
		}
	}
}

- (void)closeDataStreams
{
	[_dataReceiveStream setDelegate:nil];
	[_dataSendStream setDelegate:nil];
	[_dataReceiveStream close];
	[_dataSendStream close];
	[_dataReceiveStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_dataSendStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_dataReceiveStream release];
	[_dataSendStream release];
	_dataReceiveStream = nil;
	_dataSendStream = nil;
	if (_connectedActive > 0) {
		close(_connectedActive);
		_connectedActive = -1;
	}
	//_serverSupport.isActiveDataConn = NO;
}

- (void)openDataStreamsToHost:(NSHost *)aHost port:(int)aPort 
{	
	[NSStream getStreamsToHost:aHost
						  port:aPort
				   inputStream:&_dataReceiveStream
				  outputStream:&_dataSendStream];
	
	[self prepareAndOpenDataStreams];
}

- (void)prepareAndOpenDataStreams
{
	[_dataReceiveStream retain];
	[_dataSendStream retain];
	
	[_dataReceiveStream setDelegate:self];
	[_dataSendStream setDelegate:self];
	
	[_dataReceiveStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_dataSendStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	
	[_dataReceiveStream open];
	[_dataSendStream open];
	
	KTLog(TransportDomain, KTLogDebug, @"Setting data connection timeout to 10 seconds");
	[_openStreamsTimeout invalidate];
	_openStreamsTimeout = [[NSTimer scheduledTimerWithTimeInterval:10
															target:self
														  selector:@selector(dataConnectionOpenTimedOut:) 
														  userInfo:nil
														   repeats:NO] retain];
}

- (void)dataConnectionOpenTimedOut:(NSTimer *)timer
{
	//do something
	KTLog(ProtocolDomain, KTLogError, @"Timed out opening data connection");

	if ([self transcript])
	{
		NSString *timeout = [NSString stringWithString:LocalizedStringInThisBundle(@"Data Stream Timed Out", @"Failed to open a data stream connection")];
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", timeout] attributes:[AbstractConnection dataAttributes]] autorelease]];
	}
	
	[timer invalidate];
	[_openStreamsTimeout release];
	_openStreamsTimeout = nil;
	[self closeDataStreams];
	
	ConnectionCommand *last = [self lastCommand];
	ConnectionState lastState = [last sentState];
	
	if (lastState == FTPSettingEPSVState) 
	{
		_serverSupport.canUseEPSV = NO;
		[self closeDataStreams];
		[self sendCommand:@"DATA_CON"];
	}
	else if (lastState == FTPSettingEPRTState) 
	{
		_serverSupport.canUseEPRT = NO;
		[self closeDataStreams];
		[self sendCommand:@"DATA_CON"];
	}
	else if (lastState == FTPSettingActiveState) 
	{
		_serverSupport.canUseActive = NO;
		[self closeDataStreams];
		[self sendCommand:@"DATA_CON"];
	}
	else if (lastState == FTPSettingPassiveState) 
	{
		_serverSupport.canUsePASV = NO;
		[self closeDataStreams];
		[self sendCommand:@"DATA_CON"];
	}			
}

#pragma mark -
#pragma mark Operations

- (void)changeToDirectory:(NSString *)dirPath
{
	NSAssert((nil != dirPath), @"dirPath is nil!");
	ConnectionCommand *pwd = [ConnectionCommand command:@"PWD"
											 awaitState:ConnectionIdleState 
											  sentState:ConnectionAwaitingCurrentDirectoryState
											  dependant:nil
											   userInfo:nil];
	ConnectionCommand *cwd = [ConnectionCommand command:[NSString stringWithFormat:@"CWD %@", dirPath]
											 awaitState:ConnectionIdleState 
											  sentState:ConnectionChangingDirectoryState
											  dependant:pwd
											   userInfo:nil];
	[self queueCommand:cwd];
	[self queueCommand:pwd];
}

- (NSString *)currentDirectory
{
	return _currentPath;
}

- (NSString *)rootDirectory
{
	return _rootPath;
}

- (void)createDirectory:(NSString *)dirPath
{
	ConnectionCommand *cmd = [ConnectionCommand command:[NSString stringWithFormat:@"MKD %@", dirPath]
											 awaitState:ConnectionIdleState 
											  sentState:ConnectionCreateDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)threadedSetPermissions:(NSNumber *)perms forFile:(NSString *)path
{
	unsigned long permissions = [perms unsignedLongValue];
	NSString *cmd = [NSString stringWithFormat:@"SITE CHMOD %lo %@", permissions, path];
	ConnectionCommand *com = [ConnectionCommand command:cmd
											 awaitState:ConnectionIdleState
											  sentState:ConnectionSettingPermissionsState
											  dependant:nil
											   userInfo:nil];
	[self pushCommandOnHistoryQueue:com];
	[self sendCommand:cmd];
	// Not all servers return SITE in the FEAT request.
	/*if (_serverSupport.hasSITE)
	{
		unsigned long permissions = [perms unsignedLongValue];
		NSString *cmd = [NSString stringWithFormat:@"SITE CHMOD %lo %@", permissions, path];
		ConnectionCommand *com = [ConnectionCommand command:cmd
												 awaitState:ConnectionIdleState
												  sentState:ConnectionSettingPermissionsState
												  dependant:nil
												   userInfo:nil];
		[self pushCommandOnHistoryQueue:com];
		[self sendCommand:cmd];
	}
	else
	{
		// do we send an error or silenty fail????
		[self dequeuePermissionChange];
		[self setState:ConnectionIdleState];
	}*/
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(threadedSetPermissions:forFile:)
													  target:self
												   arguments:[NSArray arrayWithObjects: [NSNumber numberWithUnsignedLong:permissions], dirPath, nil]];
	ConnectionCommand *chmod = [ConnectionCommand command:inv
											   awaitState:ConnectionIdleState 
												sentState:ConnectionSettingPermissionsState
												dependant:nil
												 userInfo:nil];
	ConnectionCommand *mkdir = [ConnectionCommand command:[NSString stringWithFormat:@"MKD %@", dirPath]
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
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(threadedSetPermissions:forFile:)
													  target:self
												   arguments:[NSArray arrayWithObjects: [NSNumber numberWithUnsignedLong:permissions], path, nil]];
	[self queuePermissionChange:path];
	ConnectionCommand *chmod = [ConnectionCommand command:inv
											   awaitState:ConnectionIdleState 
												sentState:ConnectionSettingPermissionsState
												dependant:nil
												 userInfo:path];
	[self queueCommand:chmod];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	[self queueDeletion:dirPath];
	ConnectionCommand *rm = [ConnectionCommand command:[NSString stringWithFormat:@"RMD %@", dirPath]
											awaitState:ConnectionIdleState 
											 sentState:ConnectionDeleteDirectoryState
											 dependant:nil
											  userInfo:dirPath];
	[self queueCommand:rm];
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	[self queueRename:fromPath];
	[self queueRename:toPath];

	ConnectionCommand *to = [ConnectionCommand command:[NSString stringWithFormat:@"RNTO %@", toPath]
											awaitState:ConnectionRenameToState 
											 sentState:ConnectionAwaitingRenameState
											 dependant:nil
											  userInfo:toPath];
	ConnectionCommand *from = [ConnectionCommand command:[NSString stringWithFormat:@"RNFR %@", fromPath]
											  awaitState:ConnectionIdleState 
											   sentState:ConnectionRenameFromState
											   dependant:to
												userInfo:fromPath];
	[self queueCommand:from];
	[self queueCommand:to];
}

- (void)deleteFile:(NSString *)path
{
	[self queueDeletion:path];
	ConnectionCommand *del = [ConnectionCommand command:[NSString stringWithFormat:@"DELE %@", path]
											 awaitState:ConnectionIdleState 
											  sentState:ConnectionDeleteFileState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:del];
}

/*!	Upload file to the current directory
*/
- (void)uploadFile:(NSString *)localPath
{
	[self uploadFile:localPath orData:nil offset:0 remotePath:nil checkRemoteExistence:NO delegate:nil];
}

/*!	Upload file to the given directory
*/
- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	[self uploadFile:localPath orData:nil offset:0 remotePath:remotePath checkRemoteExistence:NO delegate:nil];
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
	return [self uploadFile:localPath
					 orData:nil
					 offset:0
				 remotePath:remotePath
	   checkRemoteExistence:flag
				   delegate:delegate];
}

/*!	Upload file to the current directory
*/
- (void)resumeUploadFile:(NSString *)localPath fileOffset:(unsigned long long)offset;
{
	[self uploadFile:localPath orData:nil offset:offset remotePath:nil checkRemoteExistence:NO delegate:nil];
}

/*!	Upload file to the given directory
*/
- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset;
{
	[self uploadFile:localPath orData:nil offset:offset remotePath:remotePath checkRemoteExistence:NO delegate:nil];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	[self uploadFile:nil orData:data offset:0 remotePath:remotePath checkRemoteExistence:NO delegate:nil];
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	[self uploadFile:nil orData:data offset:offset remotePath:remotePath checkRemoteExistence:NO delegate:nil];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	[self downloadFile:remotePath
		   toDirectory:dirPath
			 overwrite:flag
			  delegate:nil];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(unsigned long long)offset
{
	[self resumeDownloadFile:remotePath
				 toDirectory:dirPath
				  fileOffset:offset
					delegate:nil];
}

- (CKTransferRecord *)downloadFile:(NSString *)remotePath 
					   toDirectory:(NSString *)dirPath 
						 overwrite:(BOOL)flag
						  delegate:(id)delegate
{
	NSString *remoteFileName = [remotePath lastPathComponent];
	NSString *localPath = [dirPath stringByAppendingPathComponent:remoteFileName];
	
	if (!flag)
	{
		if ([[NSFileManager defaultManager] fileExistsAtPath:localPath])
		{
			if (_flags.error) {
				NSError *error = [NSError errorWithDomain:FTPErrorDomain
													 code:FTPDownloadFileExists
												 userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInThisBundle(@"Local File already exists", @"FTP download error")
																					  forKey:NSLocalizedDescriptionKey]];
				[_forwarder connection:self didReceiveError:error];
			}
			return nil;
		}
	}
	
	/*
	 TYPE I
	 SIZE file
	 PASV/EPSV/ERPT/PORT
	 RETR file
	 TYPE A
	 */
	
	[self startBulkCommands];
	ConnectionCommand *ascii = [ConnectionCommand command:@"TYPE A"
											   awaitState:ConnectionIdleState
												sentState:FTPModeChangeState
												dependant:nil
												 userInfo:nil];
	CKTransferRecord *record = [CKTransferRecord recordWithName:remotePath size:0];
	CKInternalTransferRecord *download = [CKInternalTransferRecord recordWithLocal:localPath
																			  data:nil
																			offset:0
																			remote:remotePath
																		  delegate:delegate ? delegate : record
																		  userInfo:record];
	[record setProperty:remotePath forKey:QueueDownloadRemoteFileKey];
	[record setProperty:localPath forKey:QueueDownloadDestinationFileKey];
	[record setProperty:[NSNumber numberWithInt:0] forKey:QueueDownloadTransferPercentReceived];

	[self queueDownload:download];
	
	ConnectionCommand *retr = [ConnectionCommand command:[NSString stringWithFormat:@"RETR %@", remotePath]
											  awaitState:ConnectionIdleState 
											   sentState:ConnectionDownloadingFileState
											   dependant:ascii
												userInfo:download];
	ConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	[dataCmd addDependantCommand: retr];
	
	ConnectionCommand *size = [ConnectionCommand command:[NSString stringWithFormat:@"SIZE %@", remotePath]
											  awaitState:ConnectionIdleState 
											   sentState:ConnectionSentSizeState
											   dependant:dataCmd
												userInfo:nil];
	
	ConnectionCommand *bin = [ConnectionCommand command:@"TYPE I"
											 awaitState:ConnectionIdleState 
											  sentState:FTPModeChangeState
											  dependant:_serverSupport.hasSize ? size : nil
											   userInfo:nil];
	[self queueCommand:bin];
	if (_serverSupport.hasSize)
		[self queueCommand:size];
	[self queueCommand:dataCmd];
	[self queueCommand:retr];
	[self queueCommand:ascii];
	[self endBulkCommands];
	
	return record;
}

- (CKTransferRecord *)resumeDownloadFile:(NSString *)remotePath
							 toDirectory:(NSString *)dirPath
							  fileOffset:(unsigned long long)offset
								delegate:(id)delegate
{
	NSNumber *off = [NSNumber numberWithLongLong:offset];
	NSString *remoteFileName = [remotePath lastPathComponent];
	NSString *localPath = [dirPath stringByAppendingPathComponent:remoteFileName];
	
	ConnectionCommand *ascii = [ConnectionCommand command:@"TYPE A" 
											   awaitState:ConnectionIdleState 
												sentState:ConnectionIdleState
												dependant:nil 
												 userInfo:nil];

	CKTransferRecord *record = [CKTransferRecord recordWithName:remotePath
														   size:0];
	[record setProperty:remotePath forKey:QueueDownloadRemoteFileKey];
	[record setProperty:localPath forKey:QueueDownloadDestinationFileKey];
	CKInternalTransferRecord *download = [CKInternalTransferRecord recordWithLocal:localPath
																			  data:nil
																			offset:offset
																			remote:remotePath
																		  delegate:delegate ? delegate : record
																		  userInfo:record];
	[_downloadQueue addObject:download];
	ConnectionCommand *retr = [ConnectionCommand command:[NSString stringWithFormat:@"RETR %@", remotePath]
											  awaitState:ConnectionIdleState 
											   sentState:ConnectionDownloadingFileState
											   dependant:ascii
												userInfo:download];
	ConnectionCommand *rest = [ConnectionCommand command:[NSString stringWithFormat:@"REST %@", off]
											  awaitState:ConnectionIdleState 
											   sentState:ConnectionSentOffsetState
											   dependant:retr
												userInfo:nil];
	ConnectionCommand *size = nil;
	if (_serverSupport.hasSize) {
		size = [ConnectionCommand command:[NSString stringWithFormat:@"SIZE %@", remotePath]
							   awaitState:ConnectionIdleState 
								sentState:ConnectionSentSizeState
								dependant:rest
								 userInfo:nil];
	}
	ConnectionCommand *bin = [ConnectionCommand command:@"TYPE I"
											 awaitState:ConnectionIdleState 
											  sentState:ConnectionIdleState
											  dependant:_serverSupport.hasSize ? size : rest
											   userInfo:nil];
	ConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	[dataCmd addDependantCommand:bin];
	
	[self startBulkCommands];
	[self queueCommand:dataCmd];
	
	[self queueCommand:bin];
	if (_serverSupport.hasSize)
		[self queueCommand:size];
	[self queueCommand:rest];
	[self queueCommand:retr];
	[self queueCommand:ascii];	
	[self endBulkCommands];
	
	return record;
}

/*!	Send the abort message immediately
*/
- (void)cancelTransfer
{
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedAbort];
}

- (void)cancelAll
{
	[self cancelTransfer];
	[_queueLock lock];
	[_commandQueue removeAllObjects];
	[_queueLock unlock];
}

- (void)directoryContents
{
	ConnectionCommand *ls = [ConnectionCommand command:@"LIST -FA" 
											awaitState:ConnectionIdleState 
											 sentState:ConnectionAwaitingDirectoryContentsState 
											 dependant:nil 
											  userInfo:nil];
	ConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	[dataCmd addDependantCommand:ls];
	
	[self queueCommand:dataCmd];
	[self queueCommand:ls];
}

- (void)threadedContentsOfDirectory:(NSString *)dirPath
{
	NSString *currentDir = [[[self currentDirectory] copy] autorelease];
	
	ConnectionCommand *pwd2 = [ConnectionCommand command:@"PWD"
											  awaitState:ConnectionIdleState 
											   sentState:ConnectionAwaitingCurrentDirectoryState
											   dependant:nil
												userInfo:nil];
	ConnectionCommand *cwd2 = [ConnectionCommand command:[NSString stringWithFormat:@"CWD %@", currentDir]
											  awaitState:ConnectionIdleState 
											   sentState:ConnectionChangingDirectoryState
											   dependant:pwd2
												userInfo:nil];
	
	ConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	ConnectionCommand *ls = [ConnectionCommand command:@"LIST -FA" 
											awaitState:ConnectionIdleState 
											 sentState:ConnectionAwaitingDirectoryContentsState 
											 dependant:dataCmd 
											  userInfo:nil];
	
	ConnectionCommand *pwd = [ConnectionCommand command:@"PWD"
											 awaitState:ConnectionIdleState 
											  sentState:ConnectionAwaitingCurrentDirectoryState
											  dependant:nil
											   userInfo:nil];
	ConnectionCommand *cwd = [ConnectionCommand command:[NSString stringWithFormat:@"CWD %@", dirPath]
											 awaitState:ConnectionIdleState 
											  sentState:ConnectionChangingDirectoryState
											  dependant:pwd
											   userInfo:nil];
	[_commandQueue insertObject:pwd2 atIndex:0];
	[_commandQueue insertObject:cwd2 atIndex:0];
	[_commandQueue insertObject:ls atIndex:0];
	[_commandQueue insertObject:dataCmd atIndex:0];
	[_commandQueue insertObject:pwd atIndex:0];
	[_commandQueue insertObject:cwd atIndex:0];
	[self setState:ConnectionIdleState];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(threadedContentsOfDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObject:dirPath]];
	ConnectionCommand *ls = [ConnectionCommand command:inv
											awaitState:ConnectionIdleState 
											 sentState:ConnectionAwaitingDirectoryContentsState 
											 dependant:nil 
											  userInfo:nil];
	[self queueCommand:ls];
	NSArray *cachedContents = [self cachedContentsWithDirectory:dirPath];
	if (cachedContents)
	{
		[_forwarder connection:self didReceiveContents:cachedContents ofDirectory:dirPath];
	}
}

#pragma mark -
#pragma mark Queue Support

- (NSString *)stateName:(int)state
{
	switch (state) {
		case FTPSettingActiveState: return @"FTPSettingActiveState";
		case FTPSettingPassiveState: return @"FTPSettingPassiveState";
		case FTPSettingEPSVState: return @"FTPSettingEPSVState";
		case FTPModeChangeState: return @"FTPModeChangeState";
		case FTPSettingEPRTState: return @"FTPSettingEPRTState";
		case FTPAwaitingDataConnectionToOpen: return @"FTPAwaitingDataConnectionToOpen";
		case FTPAwaitingRemoteSystemTypeState: return @"FTPAwaitingRemoteSystemTypeState";
		case FTPChangeDirectoryListingStyle: return @"FTPChangeDirectoryListingStyle";
		default: return [super stateName:state];
	}
}

- (ConnectionCommand *)nextAvailableDataConnectionType
{
	ConnectionCommand *cmd = nil;
	if (_serverSupport.canUsePASV) {
		cmd = [ConnectionCommand command:@"PASV" 
							  awaitState:ConnectionIdleState
							   sentState:FTPSettingPassiveState
							   dependant:nil 
								userInfo:nil];
	}
	else if (_serverSupport.canUseEPSV) {
		cmd = [ConnectionCommand command:@"EPSV" 
							  awaitState:ConnectionIdleState
							   sentState:FTPSettingEPSVState
							   dependant:nil 
								userInfo:nil];
	}
	else if (_serverSupport.canUseEPRT) {
		//we scan for this in the send command to setup the connection
		cmd = [ConnectionCommand command:@"EPRT" 
							  awaitState:ConnectionIdleState
							   sentState:FTPSettingEPRTState
							   dependant:nil 
								userInfo:nil];
	}
	else if (_serverSupport.canUseActive) {
		//we scan for this in the send command to setup the connection
		cmd = [ConnectionCommand command:@"PORT" 
							  awaitState:ConnectionIdleState
							   sentState:FTPSettingActiveState
							   dependant:nil 
								userInfo:nil];
	}
	else
	{
		if (_flags.error) {
			NSError *err = [NSError errorWithDomain:FTPErrorDomain
											   code:FTPErrorNoDataModes
										   userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInThisBundle(@"Exhausted all connection types to server. Please contact server administrator", @"FTP no data streams available")
																				forKey:NSLocalizedDescriptionKey]];
			[_forwarder connection:self didReceiveError:err];
		}
		cmd = [ConnectionCommand command:@"QUIT"
							  awaitState:ConnectionIdleState	
							   sentState:ConnectionSentQuitState
							   dependant:nil
								userInfo:nil];
	}
	_received226 = NO;
	return cmd;
}

- (ConnectionCommand *)pushDataConnectionOnCommandQueue
{
	ConnectionCommand *cmd = nil;
	cmd = [ConnectionCommand command:@"DATA_CON"
						  awaitState:ConnectionIdleState
						   sentState:FTPDeterminingDataConnectionType
						   dependant:nil
							userInfo:nil];
	return cmd;
}


#pragma mark -
#pragma mark General Support

- (void)setDataInputStreamAndOpen:(NSInputStream *)iStream outputStream:(NSOutputStream *)oStream socket:(CFSocketNativeHandle)sock
{
	_connectedActive = sock;
	_dataSendStream = oStream;
	_dataReceiveStream = iStream;
	[self prepareAndOpenDataStreams];
}

void dealWithConnectionSocket(CFSocketRef s, CFSocketCallBackType type, 
							  CFDataRef address, const void *data, void *info)
{
	FTPConnection *con = (FTPConnection *)info;
	CFSocketNativeHandle connectedFrom = *(CFSocketNativeHandle *)data;
	CFReadStreamRef read;
	CFWriteStreamRef write;
		
	CFStreamCreatePairWithSocket(kCFAllocatorDefault,connectedFrom,&read,&write);
	//cast as NSStreams
	NSInputStream *iStream = (NSInputStream *)read;
	NSOutputStream *oStream = (NSOutputStream *)write;
	
	//send the data streams to the ftp connection object
	[con setDataInputStreamAndOpen:iStream outputStream:oStream socket:connectedFrom];
	
	//close down the original listening socket
	CFSocketInvalidate(s);
	CFRelease(s);
}

- (BOOL)setupActiveConnectionWithPort:(unsigned)port
{
	CFOptionFlags cbTypes = kCFSocketAcceptCallBack; //once accepted we will tear down the _activeSocket
	CFSocketContext ctx = {0, self, NULL, NULL, NULL};
	
	_activeSocket = CFSocketCreate(kCFAllocatorDefault,
								   PF_INET,
								   SOCK_STREAM,
								   IPPROTO_TCP,
								   cbTypes,
								   (CFSocketCallBack)&dealWithConnectionSocket,
								   &ctx);
	CFSocketSetSocketFlags(_activeSocket,kCFSocketCloseOnInvalidate);
	int on = 1;
	setsockopt(CFSocketGetNative(_activeSocket), SOL_SOCKET, SO_REUSEPORT, &on, sizeof(on));
	setsockopt(CFSocketGetNative(_activeSocket), SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
	
	//add to the runloop
	CFRunLoopSourceRef src = CFSocketCreateRunLoopSource(kCFAllocatorDefault,_activeSocket,0);
	CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
	CFRelease(src);
	
	CFSocketError err;
	struct sockaddr_in my_addr;
	
	memset(&my_addr, 0, sizeof(my_addr));
	my_addr.sin_family = PF_INET;    
	my_addr.sin_port = htons(port); 
	my_addr.sin_addr.s_addr = inet_addr([[[NSHost currentHost] ipv4Address] UTF8String]);
	bzero(&(my_addr.sin_zero), 8);
	
	CFDataRef addrData = CFDataCreate(kCFAllocatorDefault,(const UInt8 *)&my_addr,sizeof(my_addr));
	err = CFSocketSetAddress(_activeSocket,addrData);
	CFRelease(addrData);
	
	if (err != kCFSocketSuccess) {
		KTLog(TransportDomain, KTLogError, @"Failed CFSocketSetAddress() to %@:%u", [[NSHost currentHost] ipv4Address], port);
		CFSocketInvalidate(_activeSocket);
		CFRelease(_activeSocket);
		_activeSocket = nil;
		
		if (_flags.error) {
			
			/*NSError *err = [NSError errorWithDomain:FTPErrorDomain
											   code:FTPErrorNoDataModes
										   userInfo:[NSDictionary dictionaryWithObject:@"Failed to create active connection to server" forKey:NSLocalizedDescriptionKey]];
			[_forwarder connection:self didReceiveError:err];*/
		}
		return NO;
	}
	return YES;
}

- (NSString *)setupEPRTConnection
{
	if (![self setupActiveConnectionWithPort:0])
	{
		KTLog(TransportDomain, KTLogError, @"Failed to setup EPRT socket, trying PORT");
		//try doing a port command
		_serverSupport.canUseEPRT = NO;
		_state = FTPSettingActiveState;
		return [self setupActiveConnection];
	}
	
	CFDataRef addrData = CFSocketCopyAddress(_activeSocket);
	struct sockaddr_in active_addr;
	CFDataGetBytes(addrData,CFRangeMake(0,CFDataGetLength(addrData)),(UInt8 *)&active_addr);
	CFRelease(addrData);
	
	unsigned port = ntohs(active_addr.sin_port); //Do I need to convert from network byte order? YES
	return [NSString stringWithFormat:@"EPRT |1|%@|%u|", [[NSHost currentHost] ipv4Address], port];
}

- (NSString *)setupActiveConnection
{
	if (_lastActivePort == 0)
	{
		_lastActivePort = [self localPort] + 1;
	}
	else
	{
		_lastActivePort += 1;
	}
	if (![self setupActiveConnectionWithPort:_lastActivePort])
	{
		KTLog(TransportDomain, KTLogError, @"Failed to setup PORT socket, trying PASV");
		_state = FTPSettingPassiveState;
		return @"PASV";
	}
	div_t portDiv = div(_lastActivePort, 256);
	NSString *ip = [[[[NSHost currentHost] ipv4Address] componentsSeparatedByString:@"."] componentsJoinedByString:@","];
	return [NSString stringWithFormat:@"PORT %@,%d,%d", ip, portDiv.quot, portDiv.rem];
}

- (NSArray *)parseLines:(NSString *)line
{
	return [NSFileManager attributedFilesFromListing:line];
}
 
/*!	Deal with quoted string. Quotes are doubled.... 257 "/he said ""yo"" to me" created
*/
- (NSString *)scanBetweenQuotes:(NSString *)aString
{
	NSRange r1 = [aString rangeOfString:@"\""];
	NSRange r2 = [aString rangeOfString:@"\"" options:NSBackwardsSearch];
	
	if (NSNotFound == r1.location || NSNotFound == r2.location || r1.location == r2.location)
	{
		return nil;		// can't find quotes
	}
	NSString *betweenQuotes = [aString substringWithRange:NSMakeRange(r1.location + 1, r2.location - (r1.location +1))];
	NSMutableString *result = [NSMutableString stringWithString:betweenQuotes];
	[result replaceOccurrencesOfString:@"\"\"" withString:@"\"" options:nil range:NSMakeRange(0, [result length])];
	return result;
}

/*!	Support upload method, handles all the gory details
*/

- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  orData:(NSData *)data 
						  offset:(unsigned long long)offset 
					  remotePath:(NSString *)remotePath
			checkRemoteExistence:(BOOL)flag
						delegate:(id)delegate
{
	if (nil == localPath)
	{
		localPath = [remotePath lastPathComponent];
	}
	if (nil == remotePath)
	{
		remotePath = [[self currentDirectory] stringByAppendingPathComponent:[localPath lastPathComponent]];
	}
	
	KTLog(QueueDomain, KTLogDebug, @"Queueing Upload: localPath = %@ data = %d bytes offset = %lld remotePath = %@", localPath, [data length], offset, remotePath);
	
	ConnectionCommand *ascii = [ConnectionCommand command:@"TYPE A"
											   awaitState:ConnectionIdleState
												sentState:FTPModeChangeState
												dependant:nil
												 userInfo:nil];
	ConnectionCommand *store = [ConnectionCommand command:[NSString stringWithFormat:@"STOR %@", remotePath]
											   awaitState:ConnectionIdleState
												sentState:ConnectionUploadingFileState
												dependant:ascii
												 userInfo:nil];
	ConnectionCommand *rest = nil;
	if (offset != 0) {
		rest = [ConnectionCommand command:[NSString stringWithFormat:@"REST %@", offset]
							   awaitState:ConnectionIdleState
								sentState:ConnectionSentOffsetState
								dependant:store
								 userInfo:nil];
	}
	unsigned long long uploadSize = 0;
	if (data)
	{
		uploadSize = [data length];
	}
	else
	{
		NSDictionary *attribs = [[NSFileManager defaultManager] fileAttributesAtPath:localPath traverseLink:YES];
		uploadSize = [[attribs objectForKey:NSFileSize] unsignedLongLongValue];
	}
	
	CKTransferRecord *record = [CKTransferRecord recordWithName:remotePath
														   size:uploadSize];
	[record setUpload:YES];
	[record setObject:localPath forKey:QueueUploadLocalFileKey];
	[record setObject:remotePath forKey:QueueUploadRemoteFileKey];
	
	CKInternalTransferRecord *dict = [CKInternalTransferRecord recordWithLocal:localPath
																		  data:data
																		offset:offset
																		remote:remotePath
																	  delegate:delegate ? delegate : record
																	  userInfo:record];
	[self queueUpload:dict];
	[store setUserInfo:dict];
	
	ConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	[dataCmd addDependantCommand:offset != 0 ? rest : store];
	[dataCmd setUserInfo:dict];
	
	ConnectionCommand *bin = [ConnectionCommand command:@"TYPE I"
											 awaitState:ConnectionIdleState
											  sentState:FTPModeChangeState
											  dependant:dataCmd
											   userInfo:nil];
	
	[self startBulkCommands];
	[self queueCommand:bin];
	[self queueCommand:dataCmd];
	
	if (0 != offset)
	{
		[self queueCommand:rest];
	}
	[self queueCommand:store];
	[self queueCommand:ascii];
	[self endBulkCommands];
	
	return record;
}

/*! when transferring large files over a fast connection, like the same machine, the delegate notification
* system slows the transfer down too much because the runloopforwarder has to pause the worker thread until
* the ui has updated. This method limits the amount of notifcations sent to the delegate
*/
- (BOOL)isAboveNotificationTimeThreshold:(NSDate *)date
{
	BOOL ret = YES;
	if (_lastNotified == nil) _lastNotified = [date copy];
	double diff = [date timeIntervalSinceReferenceDate] - [_lastNotified timeIntervalSinceReferenceDate];
	
	if (diff > kDelegateNotificationTheshold) {
		ret = YES;
		[_lastNotified autorelease];
		_lastNotified = [date retain];
	} else {
		ret = NO;
	}
	return ret;
}

#pragma mark -
#pragma mark Accessors

- (NSFileHandle *)writeHandle
{
    return _writeHandle; 
}

- (void)setWriteHandle:(NSFileHandle *)aWriteHandle
{
	[_writeHandle closeFile];
    [aWriteHandle retain];
    [_writeHandle release];
    _writeHandle = aWriteHandle;
}

- (NSFileHandle *)readHandle
{
    return _readHandle; 
}

- (void)setReadHandle:(NSFileHandle *)aReadHandle
{
	[_readHandle closeFile];
    [aReadHandle retain];
    [_readHandle release];
    _readHandle = aReadHandle;
}

- (NSData *)readData
{
    return _readData; 
}

- (void)setReadData:(NSData *)aReadData
{
    [aReadData retain];
    [_readData release];
    _readData = aReadData;
}

- (NSString *)currentPath	// same as external function currentDirectory
{
    return _currentPath; 
}

- (void)setCurrentPath:(NSString *)aCurrentPath
{
    if (_currentPath != aCurrentPath) {
        [_currentPath release];
        _currentPath = [aCurrentPath copy];
    }
}

@end





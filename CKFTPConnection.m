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
 
#import "CKFTPConnection.h"

#import "CKConnectionThreadManager.h"
#import "RunLoopForwarder.h"
#import "CKInternalTransferRecord.h"
#import "CKTransferRecord.h"
#import "NSObject+Connection.h"
#import "CKCacheableHost.h"
#import "CKConnectionProtocol.h"
#import "CKURLProtectionSpace.h"

#import <sys/types.h> 
#import <sys/socket.h> 
#import <netinet/in.h>

NSString *CKFTPErrorDomain = @"FTPErrorDomain";

// 500 ms.
const double kDelegateNotificationTheshold = 0.5;

@interface CKTransferRecord (Internal)
- (void)setSize:(unsigned long long)size;
@end

@interface CKFTPConnection (Private)

- (NSArray *)parseLines:(NSString *)line;
- (void)closeDataConnection;
- (void)handleDataReceivedEvent:(NSStreamEvent)eventCode;
- (void)handleDataSendStreamEvent:(NSStreamEvent)eventCode;
- (void)closeDataStreams;
- (void)openDataStreamsToHost:(NSHost *)aHost port:(int)aPort;
- (CKConnectionCommand *)pushDataConnectionOnCommandQueue;
- (CKConnectionCommand *)nextAvailableDataConnectionType;
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

//Command Handling
- (void)_receivedCodeInConnectionNotConnectedState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionSentUsernameState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionSentAccountState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionSentPasswordState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionAwaitingCurrentDirectoryState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionAwaitingDirectoryContentsState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionChangingDirectoryState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionCreateDirectoryState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionDeleteDirectoryState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionRenameFromState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionAwaitingRenameState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionDeleteFileState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionDownloadingFileState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionUploadingFileState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionSentOffsetState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionSentFeatureRequestState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionSentQuitState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionSettingPermissionsState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionSentSizeState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInConnectionSentDisconnectState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInFTPSettingPassiveState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInFTPSettingEPSVState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInFTPSettingActiveState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInFTPSettingEPRTState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInFTPAwaitingRemoteSystemTypeState:(int)code command:(NSString *)command buffer:(NSString *)buffer;
- (void)_receivedCodeInFTPChangeDirectoryListingStyleState:(int)code command:(NSString *)command buffer:(NSString *)buffer;

@end

@interface CKFTPConnection (Authentication) <NSURLAuthenticationChallengeSender>
- (void)authenticateConnection;
- (void)sendPassword;
@end


#pragma mark -


void dealWithConnectionSocket(CFSocketRef s, CFSocketCallBackType type, 
							  CFDataRef address, const void *data, void *info);


#pragma mark -


@implementation CKFTPConnection

+ (void)load	// registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forName:[self name] URLScheme:@"ftp"];
	[pool release];
}

+ (NSInteger)defaultPort { return 21; }

+ (NSString *)name
{
	return @"FTP";
}

+ (NSArray *)URLSchemes
{
	return [NSArray arrayWithObject:@"ftp"];
}

- (id)initWithURL:(NSURL *)URL
{
	if (self = [super initWithURL:URL])
	{
		[self setState:CKConnectionNotConnectedState];
		
		// These are never replaced during the lifetime of this object so we don't bother with accessor methods
		_dataBuffer = [[NSMutableData data] retain];
		_commandBuffer = [[NSMutableString alloc] initWithString:@""];
		
		_ftpFlags.canUseActive = YES;
		_ftpFlags.canUseEPRT = YES;
		_ftpFlags.canUsePASV = YES;
		_ftpFlags.canUseEPSV = YES;
		
		_ftpFlags.hasSize = YES;
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
	[_noopTimer invalidate];
	[_noopTimer release];
    
    [_lastAuthenticationChallenge release];
    [_currentAuthenticationCredential release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Commands

/*!	Called from the background thread.
*/
- (void)sendCommand:(id)command
{
	/* clang flagged these as not being used
	NSString *stringOnlyCommand = command;
	if ([command isKindOfClass:[NSInvocation class]])
	{
		stringOnlyCommand = NSStringFromSelector([command selector]);
	}
	*/ 
	
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	if ([command isKindOfClass:[NSInvocation class]])
	{
		[command invoke];
		return;
	}
	
	if ([command isEqualToString:@"DATA_CON"])
	{
		CKConnectionCommand *cmd = [self nextAvailableDataConnectionType];
		[self pushCommandOnHistoryQueue:cmd];
		command = [cmd command];
		_state = [cmd sentState];
		[self closeDataConnection];
	}
	
	if ([command isEqualToString:@"EPRT"]) 
	{
		_ftpFlags.isActiveDataConn = YES;
		command = [self setupEPRTConnection];
	} 
	else if ([command isEqualToString:@"PORT"]) 
	{
		_ftpFlags.isActiveDataConn = YES;
		command = [self setupActiveConnection];
	} 
	else if ([command isEqualToString:@"EPSV"])
	{
		_ftpFlags.isActiveDataConn = NO;
	}
	else if ([command isEqualToString:@"PASV"])
	{
		_ftpFlags.isActiveDataConn = NO;
	}
	else if ([command isEqualToString:@"LIST -a"] && _ftpFlags.isMicrosoft)
	{
		command = @"LIST";
	}

	NSString *formattedCommand = [NSString stringWithFormat:@"%@\r\n", command];

	NSString *commandToEcho = command;
	if ([command rangeOfString:@"PASS"].location != NSNotFound)
	{
		if (![defaults boolForKey:@"AllowPasswordToBeLogged"])
		{
			commandToEcho = @"PASS ####";
		}
	}
	if (_flags.transcript)
	{
		[self appendSentStringToTranscript:[NSString stringWithFormat:@"%@\n", commandToEcho]];
	}
		
	KTLog(CKProtocolDomain, KTLogDebug, @">> %@", commandToEcho);

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
		CKInternalTransferRecord *upload = [self currentUpload];
		if (_flags.didBeginUpload)
		{
			[_forwarder connection:self uploadDidBegin:[upload remotePath]];
		}
		if ([upload delegateRespondsToTransferDidBegin])
		{
			[[upload delegate] transferDidBegin:[upload userInfo]];
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
	
	if (_flags.transcript)
	{
		[self appendReceivedStringToTranscript:[NSString stringWithFormat:([buffer hasSuffix:@"\n"] ? @"%@" : @"%@\n"), buffer]];
	}
	
	KTLog(CKProtocolDomain, KTLogDebug, @"<<# %@", command);	/// use <<# to help find commands
	
	int stateToHandle = GET_STATE;
	//State independent handling	
	switch (code)
	{
		case 200: //Command okay
		case 202:
		case 215: //NAME system type
		case 250:
		case 257: //Path Created
		case 450: //Requested file action not taken. File unavailable.
		case 451: //Requested acion aborted, local error in processing
		case 504: //Command not implemented for that parameter (Karelia Case 28078, FileZilla servers do not allow CHMOD, returning 504)
		case 551:
		{
			[self setState:CKConnectionIdleState];
			break;
		}			
		case 150: //File status okay, about to open data connection.
		{
			if ([command rangeOfString:@"directory listing"].location != NSNotFound) //Sometimes we get "150 Here comes the directory listing"
			{
				//we'll clean the buffer
				[_buffer setLength:0];
			}
			break;
		}
		case 226:
		{
			_ftpFlags.received226 = YES;
			if ([command rangeOfString:@"abort" options:NSCaseInsensitiveSearch].location != NSNotFound)
			{
				NSString *remotePath = [NSString string];
				if ([self currentUpload] != nil)
				{
					remotePath = [NSString stringWithString:[[self currentUpload] remotePath]];
					//Dequeue and close any handles just as if we finished the upload
					[self dequeueUpload];
					[self setReadData:nil];
					[self setReadHandle:nil];
					_transferSize = 0;
				}
				else if ([self currentDownload] != nil)
				{
					remotePath = [NSString stringWithString:[[self currentDownload] remotePath]];
					//Dequeue and close any handles just as if we finished the download
					[self dequeueDownload];
					[_writeHandle closeFile];
					[self setWriteHandle:nil];
				}
				if (_flags.cancel)
				{
					[_forwarder connectionDidCancelTransfer:self];
				}
				if (_flags.didCancel)
				{
					[_forwarder connection:self didCancelTransfer:remotePath];
				}
			}
			if (_dataSendStream == nil || _dataReceiveStream == nil)
			{
				[self setState:CKConnectionIdleState];
			}			
			break;
		}
		case 332: //need account
		{
			if (_flags.needsAccount)
			{
				NSString *account;
				account = [_forwarder connection:self needsAccountForUsername:nil]; // TODO: Handle this more gracefully
				if (account)
				{
					[self sendCommand:[NSString stringWithFormat:@"ACCT %@", account]];
					[self setState:CKConnectionSentAccountState];
				}
			}
			break;
		}		
		case 421: //service timed out.
		{
			[self closeDataStreams];
			[super threadedDisconnect]; //This empties the queues, etc.
			_flags.isConnected = NO;
			if (_flags.didDisconnect) {
				[_forwarder connection:self didDisconnectFromHost:[[self URL] host]];
			}
			
			if (_flags.error)
			{
				NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
										  localizedDescription, NSLocalizedDescriptionKey,
										  command, NSLocalizedFailureReasonErrorKey,
										  [self URL], ConnectionHostKey, nil];
				NSError *error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
				[_forwarder connection:self didReceiveError:error];
			}
			[self setState:CKConnectionNotConnectedState]; 
			break;
		}	
		case 503: //Bad sequence of commands
		{
			//This is an internal error in the syntax of the commands and arguments sent.
			//We should never get to this state as we should construct commands correctly.
			if (GET_STATE != CKConnectionSentFeatureRequestState)
			{
				KTLog(CKProtocolDomain, KTLogError, @"FTP Internal Error: %@", command);
				// We should just see if we can process the next command
				[self setState:CKConnectionIdleState];
				break;
			}
			else
			{
				[self authenticateConnection];
				break;
			}
		}			
		case 522:
		{
			_ftpFlags.canUseEPRT = NO;
			[self sendCommand:@"DATA_CON"];
			break;
		}		
		case 530: //User not logged in
		{
			if (_flags.error)
			{
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
										  LocalizedStringInConnectionKitBundle(@"Not Logged In", @"FTP Error"), NSLocalizedDescriptionKey,
										  command, NSLocalizedFailureReasonErrorKey,
										  [[self URL] host], ConnectionHostKey, nil];
				NSError *error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
				[_forwarder connection:self didReceiveError:error];
			}
			if (GET_STATE != CKConnectionSentQuitState)
			{
				[self sendCommand:@"QUIT"];
				[self setState:CKConnectionSentQuitState];
			}
			break;
		}			
		default:
			break;
	}
	
	switch (stateToHandle)
	{
		case CKConnectionNotConnectedState:
			[self _receivedCodeInConnectionNotConnectedState:code command:command buffer:buffer];
			break;
		case CKConnectionSentUsernameState:
			[self _receivedCodeInConnectionSentUsernameState:code command:command buffer:buffer];
			break;
		case CKConnectionSentAccountState:
			[self _receivedCodeInConnectionSentAccountState:code command:command buffer:buffer];
			break;
		case CKConnectionSentPasswordState:
			[self _receivedCodeInConnectionSentPasswordState:code command:command buffer:buffer];
			break;
		case CKConnectionAwaitingCurrentDirectoryState:
			[self _receivedCodeInConnectionAwaitingCurrentDirectoryState:code command:command buffer:buffer];
			break;
		case CKConnectionAwaitingDirectoryContentsState:
			[self _receivedCodeInConnectionAwaitingDirectoryContentsState:code command:command buffer:buffer];
			break;
		case CKConnectionChangingDirectoryState:
			[self _receivedCodeInConnectionChangingDirectoryState:code command:command buffer:buffer];
			break;
		case CKConnectionCreateDirectoryState:
			[self _receivedCodeInConnectionCreateDirectoryState:code command:command buffer:buffer];
			break;
		case CKConnectionDeleteDirectoryState:
			[self _receivedCodeInConnectionDeleteDirectoryState:code command:command buffer:buffer];
			break;
		case CKConnectionRenameFromState:		
			[self _receivedCodeInConnectionRenameFromState:code command:command buffer:buffer];
			break;
		case CKConnectionAwaitingRenameState:  
			[self _receivedCodeInConnectionAwaitingRenameState:code command:command buffer:buffer];
			break;
		case CKConnectionDeleteFileState:
			[self _receivedCodeInConnectionDeleteFileState:code command:command buffer:buffer];
			break;
		case CKConnectionDownloadingFileState:
			[self _receivedCodeInConnectionDownloadingFileState:code command:command buffer:buffer];
			break;
		case CKConnectionUploadingFileState:
			[self _receivedCodeInConnectionUploadingFileState:code command:command buffer:buffer];
			break;
		case CKConnectionSentOffsetState:
			[self _receivedCodeInConnectionSentOffsetState:code command:command buffer:buffer];
			break;
		case CKConnectionSentFeatureRequestState:
			[self _receivedCodeInConnectionSentFeatureRequestState:code command:command buffer:buffer];
			break;
		case CKConnectionSentQuitState:		
			[self _receivedCodeInConnectionSentQuitState:code command:command buffer:buffer];
			break;
		case CKConnectionSettingPermissionsState:
			[self _receivedCodeInConnectionSettingPermissionsState:code command:command buffer:buffer];
			break;
		case CKConnectionSentSizeState:		
			[self _receivedCodeInConnectionSentSizeState:code command:command buffer:buffer];
			break;
		case CKConnectionSentDisconnectState: 
			[self _receivedCodeInConnectionSentDisconnectState:code command:command buffer:buffer];
			break;
		case FTPSettingPassiveState:
			[self _receivedCodeInFTPSettingPassiveState:code command:command buffer:buffer];
			break;
		case FTPSettingEPSVState:
			[self _receivedCodeInFTPSettingEPSVState:code command:command buffer:buffer];
			break;
		case FTPSettingActiveState:
			[self _receivedCodeInFTPSettingActiveState:code command:command buffer:buffer];
			break;
		case FTPSettingEPRTState:
			[self _receivedCodeInFTPSettingEPRTState:code command:command buffer:buffer];
			break;
		case FTPAwaitingRemoteSystemTypeState:
			[self _receivedCodeInFTPAwaitingRemoteSystemTypeState:code command:command buffer:buffer];
			break;
		case FTPChangeDirectoryListingStyle:
			[self _receivedCodeInFTPChangeDirectoryListingStyleState:code command:command buffer:buffer];
			break;
		default:
			break;		
	}
}
- (void)_receivedCodeInConnectionNotConnectedState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 120: //Service Ready
		{
			if (_flags.didConnect)
			{
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
										  LocalizedStringInConnectionKitBundle(@"FTP Service Unavailable", @"FTP no service"), NSLocalizedDescriptionKey,
										  command, NSLocalizedFailureReasonErrorKey,
										  [[self URL] host], ConnectionHostKey, nil];
				NSError *error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
				[_forwarder connection:self didConnectToHost:[[self URL] host] error:error];
			}
			[self setState:CKConnectionNotConnectedState]; //don't really need.
			break;
		}
		case 220: //Service Ready For New User
		{
			if (_ftpFlags.loggedIn != NO)
				break;
			if ([command rangeOfString:@"Microsoft FTP Service"].location != NSNotFound ||
				[buffer rangeOfString:@"Microsoft FTP Service"].location != NSNotFound)
			{
				_ftpFlags.isMicrosoft = YES;
			}
			else
			{
				_ftpFlags.isMicrosoft = NO;
			}
			
			// Some servers do not accept the FEAT command before logging in. They either ignore it or close the connection
			// after. The user default CKDisableFEATCommandBeforeFTPLogin enables applications to disable sending of the
			// command until after login.
			if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CKDisableFEATCommandBeforeFTPLogin"])
			{
				[self authenticateConnection];
			}
			else
			{
				[self sendCommand:@"FEAT"];
				[self setState:CKConnectionSentFeatureRequestState];
			}			
			break;
		}
		default:
			break;
	}
}

- (void)_receivedCodeInConnectionSentUsernameState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 230: //User logged in, proceed
		{
			if (![[_currentAuthenticationCredential user] isEqualToString:@"anonymous"])
            {
				break;
			}
            
			_ftpFlags.loggedIn = YES;

						
			// Queue up the commands we want to insert in the queue before notifying client we're connected
			
			// We get the current directory -- and we're notified of a change directory ... so we'll know what directory
			// we are starting in.
			CKConnectionCommand *getCurrentDirectoryCommand = [CKConnectionCommand command:@"PWD"
																				awaitState:CKConnectionIdleState
																				 sentState:CKConnectionAwaitingCurrentDirectoryState
																				 dependant:nil
																				  userInfo:nil];
			[self pushCommandOnCommandQueue:getCurrentDirectoryCommand];
			CKConnectionCommand *getRemoteSystemTypeCommand = [CKConnectionCommand command:@"SYST"
																				awaitState:CKConnectionIdleState
																				 sentState:FTPAwaitingRemoteSystemTypeState
																				 dependant:nil
																				  userInfo:nil];
			[self pushCommandOnCommandQueue:getRemoteSystemTypeCommand];
			
			//If we're supposed to log in before sending FEAT, since we're now logged in, send it!
			if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CKDisableFEATCommandBeforeFTPLogin"])
			{
				CKConnectionCommand *featuresCommand = [CKConnectionCommand command:@"FEAT"
																		 awaitState:CKConnectionIdleState
																		  sentState:CKConnectionSentFeatureRequestState
																		  dependant:nil
																		   userInfo:nil];
				[self pushCommandOnCommandQueue:featuresCommand];
			}			
			
			[self setState:CKConnectionIdleState];			
			break;
		}
		case 331: //User name okay, need password.
		{
			[self sendPassword];
			break;
		}
		default:
			break;
	}
}

- (void)_receivedCodeInConnectionSentAccountState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 230: //User logged in, proceed
		{
			[self sendPassword];
			break;
		}
		case 530: //User not logged in
		{
			// TODO: Attempt authentication again
            /*NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
										  LocalizedStringInConnectionKitBundle(@"Invalid Account name", @"FTP Error"), NSLocalizedDescriptionKey,
										  command, NSLocalizedFailureReasonErrorKey,
										  [self host], ConnectionHostKey, nil];
			*/			
			break;
		}
		default:
			break;
	}
}

- (void)_receivedCodeInConnectionSentPasswordState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch(code)
	{
		case 230: //User logged in, proceed
		{
			_ftpFlags.loggedIn = YES;
			
			// We get the current directory -- and we're notified of a change directory ... so we'll know what directory
			// we are starting in.
			CKConnectionCommand *getCurrentDirectoryCommand = [CKConnectionCommand command:@"PWD"
																				awaitState:CKConnectionIdleState
																				 sentState:CKConnectionAwaitingCurrentDirectoryState
																				 dependant:nil
																				  userInfo:nil];
			[self pushCommandOnCommandQueue:getCurrentDirectoryCommand];
			CKConnectionCommand *getRemoteSystemTypeCommand = [CKConnectionCommand command:@"SYST"
																				awaitState:CKConnectionIdleState
																				 sentState:FTPAwaitingRemoteSystemTypeState
																				 dependant:nil
																				  userInfo:nil];
			[self pushCommandOnCommandQueue:getRemoteSystemTypeCommand];
			
			//If we're supposed to log in before sending FEAT, since we're now logged in, send it!
			if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CKDisableFEATCommandBeforeFTPLogin"])
			{
				CKConnectionCommand *featuresCommand = [CKConnectionCommand command:@"FEAT"
																		 awaitState:CKConnectionIdleState
																		  sentState:CKConnectionSentFeatureRequestState
																		  dependant:nil
																		   userInfo:nil];
				[self pushCommandOnCommandQueue:featuresCommand];
			}			
			
			[self setState:CKConnectionIdleState];			
			break;
		}
		case 530: // Authentication failed. We shall request fresh authentication
		{
			[self authenticateConnection];
			break;
		}
		default:
			break;
	}
}

- (void)_receivedCodeInConnectionAwaitingCurrentDirectoryState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	NSError *error = nil;
	NSString *path = [self scanBetweenQuotes:command];
	if (!path || [path length] == 0)
		path = [[[[self lastCommand] command] substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];	
	switch (code)
	{
		case 257: //Path Created
		{
			[self setCurrentPath:path];			
			if (_rootPath == nil) 
				_rootPath = [path copy];
			
			break;
		}
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];			
			break;
		}
		case 550: //Requested action not taken, file not found. //Permission Denied
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied"), NSLocalizedDescriptionKey, path, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
		}
		default:
			break;
	}
	if (_flags.changeDirectory)
		[_forwarder connection:self didChangeToDirectory:path error:error];
}

- (void)_receivedCodeInConnectionAwaitingDirectoryContentsState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 425: //Couldn't open data connection
		{
			CKConnectionCommand *last = [self lastCommand];
			CKConnectionState lastState = [[[self commandHistory] objectAtIndex:1] sentState];
			
			if (lastState == FTPSettingEPSVState)
			{
				_ftpFlags.canUseEPSV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				[self pushCommandOnCommandQueue:last];
			}
			else if (lastState == FTPSettingEPRTState)
			{
				_ftpFlags.canUseEPRT = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				[self pushCommandOnCommandQueue:last];
			}
			else if (lastState == FTPSettingActiveState)
			{
				_ftpFlags.canUseActive = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				[self pushCommandOnCommandQueue:last];
			}
			else if (lastState == FTPSettingPassiveState)
			{
				_ftpFlags.canUsePASV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				[self pushCommandOnCommandQueue:last];
			}			
			break;
		}
		default:
			break;
	}
}

- (void)_receivedCodeInConnectionChangingDirectoryState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	NSError *error = nil;
	NSString *path = [self scanBetweenQuotes:command];
	if (!path || [path length] == 0)
		path = [[[[self lastCommand] command] substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];		
	switch (code)
	{
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];			
			break;
		}			
		case 500: //Syntax error, command unrecognized.
		case 501: //Syntax error in parameters or arguments.
		case 502: //Command not implemented
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"Failed to change to directory", @"Bad ftp command"), NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey, path, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:ConnectionErrorChangingDirectory userInfo:userInfo];
			break;			
		}		
		case 550: //Requested action not taken, file not found. //Permission Denied
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied"), NSLocalizedDescriptionKey, path, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;
		}
		default:
			break;
	}
	
	if (_flags.changeDirectory)
		[_forwarder connection:self didChangeToDirectory:path error:error];
	[self setState:CKConnectionIdleState];
}

- (void)_receivedCodeInConnectionCreateDirectoryState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	NSError *error = nil;
	switch (code)
	{
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];			
			break;
		}			
		case 521: //Supported Address Families
		{
			if (!_flags.isRecursiveUploading)
			{
				NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Create directory operation failed", @"FTP Create directory error");
				NSString *path = nil;
				NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
				if ([command rangeOfString:@"exists"].location != NSNotFound) 
				{
					[userInfo setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
					if ([command rangeOfString:@":"].location != NSNotFound)
					{
						path = [command substringWithRange:NSMakeRange(4, [command rangeOfString:@":"].location - 4)];
						[userInfo setObject:path forKey:ConnectionDirectoryExistsFilenameKey];
						[userInfo setObject:path forKey:NSFilePathErrorKey];
					}
				}
				[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
				[userInfo setObject:command forKey:NSLocalizedFailureReasonErrorKey];
				error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			}
			break;
		}
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Create directory operation failed", @"FTP Create directory error");
			//Some servers won't say that the directory exists. Once I get peer connections going, I will be able to ask the
			//peer if the dir exists for confirmation until then we will make the assumption that it exists.
			//if ([command rangeOfString:@"exists"].location != NSNotFound) {
			[userInfo setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
			NSString *path = [[[[self lastCommand] command] substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			[userInfo setObject:path forKey:ConnectionDirectoryExistsFilenameKey];
			[userInfo setObject:path forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:command forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;			
		}			
		default:
			break;
	}
	
	if (_flags.createDirectory)
	{
		NSString *path = [self scanBetweenQuotes:command];
		if (!path || [path length] == 0)
		{
			path = [[[[self lastCommand] command] substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		}
		[_forwarder connection:self didCreateDirectory:path error:error];
	}
	[self setState:CKConnectionIdleState];
}

- (void)_receivedCodeInConnectionDeleteDirectoryState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	NSError *error = nil;
	switch (code)
	{
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];			
			break;
		}			
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			NSString *localizedDescription = [NSString stringWithFormat:@"%@: %@", LocalizedStringInConnectionKitBundle(@"Failed to delete directory", @"couldn't delete the file"), [[self currentDirectory] stringByAppendingPathComponent:[self currentDeletion]]];
			[userInfo setObject:[self currentDeletion] forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:command forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;			
		}									
		default:
			break;
	}
	
	// Uses same _fileDeletes queue, hope that's safe to do.  (Any chance one could get ahead of another?)
	if (_flags.deleteDirectory)
		[_forwarder connection:self didDeleteDirectory:[_fileDeletes objectAtIndex:0] error:error];
	[self dequeueDeletion];
	[self setState:CKConnectionIdleState];
}

- (void)_receivedCodeInConnectionRenameFromState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	NSError *error = nil;
	switch (code)
	{
		case 350: //Requested action pending further information
		{
			[self setState:CKConnectionRenameToState];
			break;
		}
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];			
			break;
		}			
		default:
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(@"No such file", @"No such file"), NSLocalizedDescriptionKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;
		}
	}
	
	//Unlike other methods, we check that error isn't nil here, because we're sending the finished delegate message on error, whereas the "successful" codes send downloadProgressed messages.
	if (error)
	{
		if (_flags.rename)
			[_forwarder connection:self didRename:[_fileRenames objectAtIndex:0] to:[_fileRenames objectAtIndex:1] error:error];
		[_fileRenames removeObjectAtIndex:0];
		[_fileRenames removeObjectAtIndex:0];							 
		[self setState:CKConnectionIdleState];				
	}
}

- (void)_receivedCodeInConnectionAwaitingRenameState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	NSString *fromPath = [_fileRenames objectAtIndex:0];
	NSString *toPath = [_fileRenames objectAtIndex:1];
	
	NSError *error = nil;
	switch (code)
	{
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];			
			break;
		}			
		case 450: //Requested file action not taken. File unavailable. //File in Use
		{
			NSString *remotePath = [[self currentUpload] remotePath];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File in Use", @"FTP file in use"), NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  remotePath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;
		}			
		case 550: //Requested action not taken, file not found. //Permission Denied
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied"), NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  fromPath, @"fromPath", 
									  toPath, @"toPath", nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;			
		}
		default:
			break;
	}
	
	if (_flags.rename)
		[_forwarder connection:self didRename:fromPath to:toPath error:error];
	[_fileRenames removeObjectAtIndex:0];
	[_fileRenames removeObjectAtIndex:0];							 
	[self setState:CKConnectionIdleState];	
}

- (void)_receivedCodeInConnectionDeleteFileState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	NSError *error = nil;
	switch (code)
	{
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];			
			break;
		}			
		case 450: //Requested file action not taken. File unavailable.
		{
			NSString *remotePath = [[self currentUpload] remotePath];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File in Use", @"FTP file in use"), NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  remotePath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;
		}			
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			NSString *localizedDescription = [NSString stringWithFormat:@"%@: %@", LocalizedStringInConnectionKitBundle(@"Failed to delete file", @"couldn't delete the file"), [[self currentDirectory] stringByAppendingPathComponent:[self currentDeletion]]];
			[userInfo setObject:[self currentDeletion] forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:command forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;			
		}						
		default:
			break;
	}
	
	if (_flags.deleteFile) 
		[_forwarder connection:self didDeleteFile:[self currentDeletion] error:error];
	[self dequeueDeletion];	
	[self setState:CKConnectionIdleState];
}

- (void)_receivedCodeInConnectionDownloadingFileState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	NSError *error = nil;
	switch (code)
	{
		case 150: //File status okay, about to open data connection.
		{
			CKInternalTransferRecord *download = [self currentDownload];
			if (_writeHandle == nil) // we can get setup in the handleDataReceievedEvent: method
			{
				NSFileManager *fm = [NSFileManager defaultManager];
				
				// check the file offset of the current download to see if we resume the transfer
				unsigned long long fileOffset = [download offset];
				bool isResume = ( fileOffset > 0 && [fm fileExistsAtPath:[download localPath]] );
				
				if ( !isResume ) {
					[fm removeFileAtPath:[download localPath] handler:nil];
					[fm createFileAtPath:[download localPath]
								contents:nil
							  attributes:nil];
					_transferSent = 0;
				}
				
				[self setWriteHandle:[NSFileHandle fileHandleForWritingAtPath:[download localPath]]];
				if ( isResume ) {
					[_writeHandle seekToEndOfFile];
					_transferSent = fileOffset;
				}
			}
			//start to read in the data to kick start it
			uint8_t *buf = (uint8_t *)malloc(sizeof(uint8_t) * kStreamChunkSize);
			int len = [_dataReceiveStream read:buf maxLength:kStreamChunkSize];
			if (len >= 0) {
				[_writeHandle writeData:[NSData dataWithBytesNoCopy:buf length:len freeWhenDone:NO]];
				_transferSent += len;
				
				if (_flags.downloadProgressed)
				{
					[_forwarder connection:self download:[download remotePath] receivedDataOfLength:len];
				}
				if ([download delegateRespondsToTransferTransferredData])
				{
					[[download delegate] transfer:[download userInfo] transferredDataOfLength:len];
				}
				int percent = 100.0 * (float)_transferSent / ((float)_transferSize * 1.0);
				if (_flags.downloadPercent)
				{
					[_forwarder connection:self download:[download remotePath] progressedTo:[NSNumber numberWithInt:percent]];
				}
				if ([download delegateRespondsToTransferProgressedTo])
				{
					[[download delegate] transfer:[download userInfo] progressedTo:[NSNumber numberWithInt:percent]];
				}
				_transferLastPercent = percent;
			}
			
			free(buf);			
			break;
		}
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];			
			break;
		}			
		case 425: //Couldn't open data connection
		{
			CKConnectionCommand *last = [self lastCommand];
			CKConnectionState lastState = [[[self commandHistory] objectAtIndex:1] sentState];
			
			if (lastState == FTPSettingEPSVState)
			{
				_ftpFlags.canUseEPSV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				[self pushCommandOnCommandQueue:last];
			}
			else if (lastState == FTPSettingEPRTState)
			{
				_ftpFlags.canUseEPRT = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				[self pushCommandOnCommandQueue:last];
			}
			else if (lastState == FTPSettingActiveState)
			{
				_ftpFlags.canUseActive = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				[self pushCommandOnCommandQueue:last];
			}
			else if (lastState == FTPSettingPassiveState)
			{
				_ftpFlags.canUsePASV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				[self pushCommandOnCommandQueue:last];
			}			
			break;
		}		
		case 450: //Requested file action not taken. File unavailable.
		{
			NSString *remotePath = [[self currentUpload] remotePath];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File in Use", @"FTP file in use"), NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  remotePath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;
		}	
		case 451: //Requested acion aborted, local error in processing
		{
			NSString *remotePath = [[self currentDownload] remotePath];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"Action Aborted. Local Error", @"FTP Abort"), NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  remotePath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;
		}
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			CKInternalTransferRecord *download = [self currentDownload];
			NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"File %@ does not exist on server", @"FTP file download error"), [download remotePath]];
			[userInfo setObject:[download remotePath] forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:command forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;			
		}			
		default:
			break;
	}
	if (error)
	{	
		//Unlike other methods, we check that error isn't nil here, because we're sending the finished delegate message on error, whereas the "successful" codes send downloadProgressed messages.
		CKInternalTransferRecord *download = [[self currentDownload] retain];
		[self dequeueDownload];
		
		if (_flags.downloadFinished)
			[_forwarder connection:self downloadDidFinish:[download remotePath] error:error];
		if ([download delegateRespondsToTransferDidFinish])
			[[download delegate] transferDidFinish:[download userInfo] error:error];
		
		[download release];
		
		//At this point the top of the command queue is something associated with this download. Remove it and all of its dependents.
		[_queueLock lock];
		CKConnectionCommand *nextCommand = ([_commandQueue count] > 0) ? [_commandQueue objectAtIndex:0] : nil;
		if (nextCommand)
		{
			NSEnumerator *enumerator = [[nextCommand dependantCommands] objectEnumerator];
			CKConnectionCommand *dependent;
			while (dependent = [enumerator nextObject])
			{
				[_commandQueue removeObject:dependent];
			}
			
			[_commandQueue removeObject:nextCommand];
		}
		[_queueLock unlock];
		[self setState:CKConnectionIdleState];
	}
}

- (void)_receivedCodeInConnectionUploadingFileState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	NSError *error = nil;
	switch (code)
	{
		case 110: //Restart marker reply
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
			break;
		}
		case 150: //File status okay, about to open data connection.
		{
			CKInternalTransferRecord *d = [self currentUpload];
			NSString *file = [d localPath];	// actual path to file, or destination name if from data
			NSString *remoteFile = [d remotePath];
			NSData *data = [d data];
			
			if (nil == file && nil == data)
			{
				NSString *str = [NSString stringWithFormat:@"FTPConnection parseCommand: no file or data.  currrentUpload = %p remotePath = %@",
								 d, remoteFile ];
				NSLog(@"%@", str);
				//NSAssert(NO, str);		// hacky way to throw an exception.
			}
			else
			{
				
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
					
                    // The file handle will be nil if the file doesn't exist. Cancel the transfer and report the error
                    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:file];
					if (fileHandle)
                    {
                        [self setReadHandle:fileHandle];
                        
                        NSData *chunk = [fileHandle readDataOfLength:kStreamChunkSize];
                        bytes = (uint8_t *)[chunk bytes];
                        chunkLength = [chunk length];		// actual length of bytes read
                        
                        NSNumber *size = [[[NSFileManager defaultManager] fileAttributesAtPath:file traverseLink:YES] objectForKey:NSFileSize];
                        _transferSize = [size unsignedLongLongValue];
                    }
                    else
                    {
                        NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Local file %@ doesn't exist", @"File doesn't exist"), [file lastPathComponent]];
                        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                                  localizedDescription, NSLocalizedDescriptionKey,
                                                  file, NSFilePathErrorKey,
                                                  [[self URL] host], ConnectionHostKey, nil];
                        error = [NSError errorWithDomain:CKConnectionErrorDomain code:ConnectionErrorUploading userInfo:userInfo];			
                        [self threadedCancelTransfer];			
                        break;
                    }
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
			break;
		}
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];			
			break;
		}			
		case 425: //Couldn't open data connection
		{
			CKConnectionCommand *last = [self lastCommand];
			CKConnectionState lastState = [[[self commandHistory] objectAtIndex:1] sentState];
			
			if (lastState == FTPSettingEPSVState)
			{
				_ftpFlags.canUseEPSV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				[self pushCommandOnCommandQueue:last];
			}
			else if (lastState == FTPSettingEPRTState)
			{
				_ftpFlags.canUseEPRT = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				[self pushCommandOnCommandQueue:last];
			}
			else if (lastState == FTPSettingActiveState)
			{
				_ftpFlags.canUseActive = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				[self pushCommandOnCommandQueue:last];
			}
			else if (lastState == FTPSettingPassiveState)
			{
				_ftpFlags.canUsePASV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				[self pushCommandOnCommandQueue:last];
			}			
			break;
		}
		case 450: //Requested file action not taken. File unavailable.
		{
			NSString *remotePath = [[self currentUpload] remotePath];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File in Use", @"FTP file in use"), NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  remotePath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;
		}
		case 452: //Requested action not taken. Insufficient storage space in system.
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"No Storage Space Available", @"FTP Error"), NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self currentUpload] remotePath], NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			[self sendCommand:@"ABOR"];			
			break;
		}
		case 532: //Need account for storing files.
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"You need an Account to Upload Files", @"FTP Error"), NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self URL] host], ConnectionHostKey,
									  [[self currentUpload] remotePath], NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;
		}
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			CKInternalTransferRecord *upload = [self currentUpload];
			NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"You do not have access to write file %@", @"FTP file upload error"), [upload remotePath]];
			[userInfo setObject:[upload remotePath] forKey:NSFilePathErrorKey];
			[self dequeueUpload];			
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:command forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;			
		}
		case 552: //Requested file action aborted, storage allocation exceeded.
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"Cannot Upload File. Storage quota on server exceeded", @"FTP upload error"), NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self currentUpload] remotePath], NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;
		}
		default:
			break;
	}
    
    
    // If there was an error, report it to the delegate
	if (error)
	{
		CKInternalTransferRecord *upload = [[self currentUpload] retain];
		[self dequeueUpload];
		
		if (_flags.uploadFinished)
			[_forwarder connection:self uploadDidFinish:[upload remotePath] error:error];
		if ([upload delegateRespondsToTransferDidFinish])
			[[upload delegate] transferDidFinish:[upload userInfo] error:error];
		
		[upload release];
		
		//At this point the top of the command queue is something associated with this upload. Remove it and all of its dependents.
		[_queueLock lock];
		CKConnectionCommand *nextCommand = ([_commandQueue count] > 0) ? [_commandQueue objectAtIndex:0] : nil;
		if (nextCommand)
		{
			NSEnumerator *e = [[nextCommand dependantCommands] objectEnumerator];
			CKConnectionCommand *dependent;
			while (dependent = [e nextObject])
			{
				[_commandQueue removeObject:dependent];
			}
			
			[_commandQueue removeObject:nextCommand];
		}
		[_queueLock unlock];		
		[self setState:CKConnectionIdleState];
	}
}

- (void)_receivedCodeInConnectionSentOffsetState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 350: //Requested action pending further information
		{
			[self setState:CKConnectionIdleState];
			break;
		}
		default:
			break;
	}
}

- (void)_receivedCodeInConnectionSentFeatureRequestState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 211: //System status, or system help ready
		{
			//parse features
			if ([buffer rangeOfString:@"SIZE"].location != NSNotFound)
				_ftpFlags.hasSize = YES;
			else
				_ftpFlags.hasSize = NO;
			
            if ([buffer rangeOfString:@"ADAT"].location != NSNotFound)
				_ftpFlags.hasADAT = YES;
			else
				_ftpFlags.hasADAT = NO;
			
            if ([buffer rangeOfString:@"AUTH"].location != NSNotFound)
				_ftpFlags.hasAUTH = YES;
			else
				_ftpFlags.hasAUTH = NO;
			
            if ([buffer rangeOfString:@"CCC"].location != NSNotFound)
				_ftpFlags.hasCCC = YES;
			else
				_ftpFlags.hasCCC = NO;
			
            if ([buffer rangeOfString:@"CONF"].location != NSNotFound)
				_ftpFlags.hasCONF = YES;
			else
				_ftpFlags.hasCONF = NO;
			
            if ([buffer rangeOfString:@"ENC"].location != NSNotFound)
				_ftpFlags.hasENC = YES;
			else
				_ftpFlags.hasENC = NO;
			
            if ([buffer rangeOfString:@"MIC"].location != NSNotFound)
				_ftpFlags.hasMIC = YES;
			else
				_ftpFlags.hasMIC = NO;
			
            if ([buffer rangeOfString:@"PBSZ"].location != NSNotFound)
				_ftpFlags.hasPBSZ = YES;
			else
				_ftpFlags.hasPBSZ = NO;
			
            if ([buffer rangeOfString:@"PROT"].location != NSNotFound)
				_ftpFlags.hasPROT = YES;
			else
				_ftpFlags.hasPROT = NO;
			
            if ([buffer rangeOfString:@"MDTM"].location != NSNotFound)
				_ftpFlags.hasMDTM = YES;
			else
				_ftpFlags.hasMDTM = NO;
			
            if ([buffer rangeOfString:@"SITE"].location != NSNotFound)
				_ftpFlags.hasSITE = YES;
			else
				_ftpFlags.hasSITE = NO;
			
            if (_ftpFlags.loggedIn == NO) {
				[self authenticateConnection];
			} else {
				[self setState:CKConnectionIdleState];
			}			
			break;
		}
		case 500: //Syntax error, command unrecognized.
		case 501: //Syntax error in parameters or arguments.
		case 502: //Command not implemented
		{
			if (!_ftpFlags.loggedIn)
			{
				[self authenticateConnection];
			}
			else
			{
				[self setState:CKConnectionIdleState];
			}
			break;
		}
		case 530: //User not logged in
		{
			// the server doesn't support FEAT before login
            [self authenticateConnection];
			break;
		}
		default:
			break;
	}
}

- (void)_receivedCodeInConnectionSentQuitState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 221: //Service closing control connection.
		{
			[super threadedDisconnect];
			break;
		}
		default:
			break;
	}
}

- (void)_receivedCodeInConnectionSettingPermissionsState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	NSError *error = nil;
	switch (code)
	{
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];			
			break;
		}			
		case 450: //Requested file action not taken. File unavailable.
		{
			NSString *remotePath = [[self currentUpload] remotePath];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File in Use", @"FTP file in use"), NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  remotePath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;
		}		
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Failed to set permissions for path %@", @"FTP Upload error"), [self currentPermissionChange]];
			[userInfo setObject:[self currentPermissionChange] forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:command forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;			
		}				
		case 553: //Requested action not taken. Illegal file name.
		{
			NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Failed to set permissions for path %@", @"FTP Upload error"), [self currentPermissionChange]];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [self currentPermissionChange], NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;
		}
		default:
			break;
	}
	if (_flags.permissions)
		[_forwarder connection:self didSetPermissionsForFile:[_filePermissions objectAtIndex:0] error:error];
	[self dequeuePermissionChange];
	[self setState:CKConnectionIdleState];
}

- (void)_receivedCodeInConnectionSentSizeState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	NSError *error = nil;
	switch (code)
	{
		case 213: //File status
		{
			CKInternalTransferRecord *download = [self currentDownload];
			if ([command rangeOfString:@"("].location != NSNotFound)
			{
				NSScanner *sizeScanner = [NSScanner scannerWithString:command];
				NSCharacterSet *bracketSet = [NSCharacterSet characterSetWithCharactersInString:@"()"];
				[sizeScanner scanUpToCharactersFromSet:bracketSet intoString:nil];
				if ( [sizeScanner scanLocation] < [command length] )
				{
					[sizeScanner setScanLocation:[sizeScanner scanLocation] + 1];
					sscanf([[command substringFromIndex:[sizeScanner scanLocation]] cStringUsingEncoding:NSUTF8StringEncoding],
						   "%llu", &_transferSize);
				}
			}
			else
			{
				// some servers return 213 4937728
				NSScanner *sizeScanner = [NSScanner scannerWithString:command];
				NSCharacterSet *sp = [NSCharacterSet whitespaceCharacterSet];
				[sizeScanner scanUpToCharactersFromSet:sp intoString:nil];
				if ( [sizeScanner scanLocation] < [command length] )
				{
					[sizeScanner setScanLocation:[sizeScanner scanLocation] + 1];
					sscanf([[command substringFromIndex:[sizeScanner scanLocation]] cStringUsingEncoding:NSUTF8StringEncoding],
						   "%llu", &_transferSize);
				}
				else
				{
					_transferSize = LONG_MAX;
				}
			}
			if ([[download delegate] isKindOfClass:[CKTransferRecord class]])
			{
				[(CKTransferRecord *)[download delegate] setSize:_transferSize];
			}
			
			_transferSent = 0;
			[self setState:CKConnectionIdleState];			
			break;
		}
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  command, NSLocalizedFailureReasonErrorKey,
									  [[self URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];			
			break;
		}			
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			CKInternalTransferRecord *download = [self currentDownload];
			NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"File %@ does not exist on server", @"FTP file download error"), [download remotePath]];
			[userInfo setObject:[download remotePath] forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:command forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:code userInfo:userInfo];
			break;			
		}			
		default:
			break;
	}
	if (error)
	{	
		//Unlike other methods, we check that error isn't nil here, because we're sending the finished delegate message on error, whereas the "successful" codes send downloadProgressed messages.
		CKInternalTransferRecord *download = [[self currentDownload] retain];
		[self dequeueDownload];
		
		if (_flags.downloadFinished)
			[_forwarder connection:self downloadDidFinish:[download remotePath] error:error];
		if ([download delegateRespondsToTransferDidFinish])
			[[download delegate] transferDidFinish:[download userInfo] error:error];
		
		[download release];
		
		//At this point the top of the command queue is something associated with this download. Remove it and all of its dependents.
		[_queueLock lock];
		CKConnectionCommand *nextCommand = ([_commandQueue count] > 0) ? [_commandQueue objectAtIndex:0] : nil;
		if (nextCommand)
		{
			NSEnumerator *e = [[nextCommand dependantCommands] objectEnumerator];
			CKConnectionCommand *dependent;
			while (dependent = [e nextObject])
			{
				[_commandQueue removeObject:dependent];
			}
			[_commandQueue removeObject:nextCommand];
		}
		[_queueLock unlock];
		[self setState:CKConnectionIdleState];
	}
}

- (void)_receivedCodeInConnectionSentDisconnectState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 221: //Service closing control connection.
		{
			[super threadedDisconnect];
			break;
		}
		default:
			break;
	}
}

- (void)_receivedCodeInFTPSettingPassiveState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 227: //Entering Passive Mode
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
				_ftpFlags.canUsePASV = NO;
				if (_flags.error)
				{
					NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"All data connection modes have been exhausted. Check with the server administrator.", @"FTP no data stream types available");
					NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
											  localizedDescription, NSLocalizedDescriptionKey,
											  command, NSLocalizedFailureReasonErrorKey,
											  [[self URL] host], ConnectionHostKey, nil];
					NSError *err = [NSError errorWithDomain:CKFTPErrorDomain code:FTPErrorNoDataModes userInfo:userInfo];
					[_forwarder connection:self didReceiveError:err];
				}
				_state = CKConnectionSentQuitState;
				[self sendCommand:@"QUIT"];
			}
			for (j=0; j<6; j++)
			{
				n[j] = (unsigned char) (i[j] & 0xff);
			}
			int port = i[4] << 8 | i[5];
			//port = ntohs(i[5] << 8 | i[4]);
			NSString *hostString = [NSString stringWithFormat:@"%d.%d.%d.%d", i[0], i[1], i[2], i[3]];
						
			NSHost *host = [CKCacheableHost hostWithAddress:hostString];
			[host setValue:[NSArray arrayWithObject:[[self URL] host]] forKey:@"names"]; // KVC hack
			
			[self closeDataStreams];
			[self setState:FTPAwaitingDataConnectionToOpen];
			[self openDataStreamsToHost:host port:port];			
			break;
		}
		case 500: //Syntax error, command unrecognized.
		case 501: //Syntax error in parameters or arguments.
		case 502: //Command not implemented
		{
			_ftpFlags.canUsePASV = NO;
			[self closeDataStreams];
			[self sendCommand:@"DATA_CON"];
			break;			
		}
		default:
			break;
	}
}

- (void)_receivedCodeInFTPSettingEPSVState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 229: //Extended Passive Mode Entered
		{
			//get the port number
			int port = 0;
			char *cmd = (char *)[command UTF8String];
			char *start = strchr(cmd,'|');
			if ( !start || sscanf(start, "|||%d|", &port) != 1)
			{
				_ftpFlags.canUseEPSV = NO;
				CKConnectionCommand *cmd = [self nextAvailableDataConnectionType];
				_state = [cmd sentState];
				[self sendCommand:[cmd command]];
			}
			NSHost *host = [CKCacheableHost hostWithName:[[self URL] host]];
			[host setValue:[NSArray arrayWithObject:[[self URL] host]] forKey:@"names"]; // KVC hack
			
			[self closeDataStreams];
			[self setState:FTPAwaitingDataConnectionToOpen];
			[self openDataStreamsToHost:host port:port];			
			break;
		}
		case 500: //Syntax error, command unrecognized.
		case 501: //Syntax error in parameters or arguments.
		case 502: //Command not implemented
		{
			_ftpFlags.canUseEPSV = NO;
			[self closeDataStreams];
			[self sendCommand:@"DATA_CON"];
			break;			
		}
		default:
			break;
	}
}

- (void)_receivedCodeInFTPSettingActiveState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 500: //Syntax error, command unrecognized.
		case 501: //Syntax error in parameters or arguments.
		case 502: //Command not implemented
		{
			_ftpFlags.canUseActive = NO;
			[self closeDataStreams];
			[self sendCommand:@"DATA_CON"];			
			break;
		}
		default:
			break;
	}
}

- (void)_receivedCodeInFTPSettingEPRTState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 500: //Syntax error, command unrecognized.
		case 501: //Syntax error in parameters or arguments.
		case 502: //Command not implemented
		{
			_ftpFlags.canUseEPRT = NO;
			[self sendCommand:@"DATA_CON"];
			break;
		}
		default:
			break;
	}
}

- (void)_receivedCodeInFTPAwaitingRemoteSystemTypeState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 215: //NAME system type
		{
			if ([[command lowercaseString] rangeOfString:@"windows"].location != NSNotFound)
			{
				_ftpFlags.isMicrosoft = YES;
				[self setState:FTPChangeDirectoryListingStyle];
				[self sendCommand:@"SITE DIRSTYLE"];
				break;
			}
			else
			{
				_ftpFlags.isMicrosoft = NO;
			}			
			break;
		}
		case 500: //Syntax error, command unrecognized.
		case 501: //Syntax error in parameters or arguments.
		case 502: //Command not implemented
		{
			[self setState:CKConnectionIdleState];
			break;
		}			
		default:
			break;
	}
}

- (void)_receivedCodeInFTPChangeDirectoryListingStyleState:(int)code command:(NSString *)command buffer:(NSString *)buffer
{
	switch (code)
	{
		case 500: //Syntax error, command unrecognized.
		case 501: //Syntax error in parameters or arguments.
		case 502: //Command not implemented
		{
			[self setState:CKConnectionIdleState];
			break;
		}
		case 550: //Requested action not taken, file not found.
		{
			[self setState:CKConnectionIdleState];
			break;
		}
		default:
			break;
	}
}

#pragma mark -
#pragma mark Stream Handling

- (void)threadedDisconnect
{
	_state = CKConnectionSentDisconnectState;
	[self sendCommand:@"QUIT"];
}

- (void)threadedCancelTransfer
{
	[self sendCommand:@"ABOR"];
	_isForceDisconnecting = YES;
	[self closeDataConnection];
	[super threadedCancelTransfer];
}

/*!	Stream delegate method.  "The delegate receives this message only if the stream object is scheduled on a runloop. The message is sent on the stream object’s thread."
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

	
	NSString *str = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
	if (str)
	{
		[_commandBuffer appendString:str];
	}
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
				NSData *data = [NSData dataWithBytesNoCopy:buf length:len freeWhenDone:NO];
				/*
				 If this is uncommented, it'll cause massive CPU load when we're doing downloads.
				 From Greg: "if you enable this, you computer will heat your house this winter"
				 KTLog(CKStreamDomain, KTLogDebug, @"FTPD << %@", [data shortDescription]);
				 */
				
				if (GET_STATE == CKConnectionDownloadingFileState)
				{
					CKInternalTransferRecord *download = [self currentDownload];
					NSString *file = [download remotePath];
					if (_writeHandle == nil) // data receieved before receiving a 150
					{
						NSFileManager *fm = [NSFileManager defaultManager];
						
						// check the file offset of the current download to see if we resume the transfer
						unsigned long long fileOffset = [download offset];
						bool isResume = ( fileOffset > 0 && [fm fileExistsAtPath:[download localPath]] );
						
						if ( !isResume ) {
							[fm removeFileAtPath:[download localPath] handler:nil];
							[fm createFileAtPath:[download localPath]
										contents:nil
									  attributes:nil];
							_transferSent = 0;
						}
						
						[self setWriteHandle:[NSFileHandle fileHandleForWritingAtPath:[download localPath]]];
						if ( isResume ) {
							[_writeHandle seekToEndOfFile];
							_transferSent = fileOffset;
						}
					}
					[_writeHandle writeData:data];
					_transferSent += len;
					
					//if ([self isAboveNotificationTimeThreshold:[NSDate date]]) 
					{
						if (_transferSize > 0)
						{
							int percent = 100.0 * (float)_transferSent / ((float)_transferSize * 1.0);
							if (percent > _transferLastPercent)
							{
								if ([download delegateRespondsToTransferProgressedTo])
								{
									[[download delegate] transfer:[download userInfo] progressedTo:[NSNumber numberWithInt:percent]];
								}
								if (_flags.downloadPercent)
								{
									[_forwarder connection:self download:file progressedTo:[NSNumber numberWithInt:percent]];	// send message if we have increased %
								}
								_transferLastPercent = percent;
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
			KTLog(CKTransportDomain, KTLogDebug, @"FTP Data receive stream opened");
			[_openStreamsTimeout invalidate];
			[_openStreamsTimeout release];
			_openStreamsTimeout = nil;
			break;
		}
		case NSStreamEventErrorOccurred:
		{
			if (_flags.transcript)
			{
				[self appendSentStringToTranscript:[NSString stringWithFormat:@"Receive Stream Error: %@\n", [_receiveStream streamError]]];
			}
			

			KTLog(CKStreamDomain, KTLogError, @"receive error %@", [_receiveStream streamError]);
			KTLog(CKProtocolDomain, KTLogDebug, @"error state received = %@", [self stateName:GET_STATE]);
			// we don't want the error to go to the delegate unless we fail on setting the active con
			/* Some servers when trying to test PASV can crap out and throw an error */
			if (GET_STATE == FTPAwaitingDataConnectionToOpen)
			{
				CKConnectionCommand *lastCommand = [[self commandHistory] objectAtIndex:0];
				CKConnectionState lastState = [lastCommand sentState];
				switch (lastState)
				{
					case FTPSettingEPSVState:
						_ftpFlags.canUseEPSV = NO;
						break;
					case FTPSettingEPRTState:
						_ftpFlags.canUseEPRT = NO;
						break;
					case FTPSettingActiveState:
						_ftpFlags.canUseActive = NO;
						break;
					case FTPSettingPassiveState:
						_ftpFlags.canUsePASV = NO;
						break;
				}
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingEPSVState) 
			{
				_ftpFlags.canUseEPSV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingEPRTState) 
			{
				_ftpFlags.canUseEPRT = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingActiveState) 
			{
				_ftpFlags.canUseActive = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingPassiveState) 
			{
				_ftpFlags.canUsePASV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			
			// if uploading, skip the transfer
			if (GET_STATE == CKConnectionUploadingFileState || 
				GET_STATE == CKConnectionDownloadingFileState ||
				GET_STATE == FTPAwaitingDataConnectionToOpen ||
				GET_STATE == CKConnectionAwaitingDirectoryContentsState) 
			{
				if (GET_STATE == CKConnectionUploadingFileState)
				{
					CKInternalTransferRecord *upload = [[self currentUpload] retain];
					[self dequeueUpload];
					
					if (_flags.uploadFinished)
						[_forwarder connection:self uploadDidFinish:[upload remotePath] error:[_receiveStream streamError]];
					if ([upload delegateRespondsToTransferDidFinish])
						[[upload delegate] transferDidFinish:[upload userInfo] error:[_receiveStream streamError]];
					
					[upload release];

					//At this point the top of the command queue is something associated with this upload. Remove it and all of its dependents.
					[_queueLock lock];
					CKConnectionCommand *nextCommand = ([_commandQueue count] > 0) ? [_commandQueue objectAtIndex:0] : nil;
					if (nextCommand)
					{
						NSEnumerator *e = [[nextCommand dependantCommands] objectEnumerator];
						CKConnectionCommand *dependent;
						while (dependent = [e nextObject])
						{
							[_commandQueue removeObject:dependent];
						}
						
						[_commandQueue removeObject:nextCommand];
					}
					[_queueLock unlock];		
					[self setState:CKConnectionIdleState];
				}
				if (GET_STATE == CKConnectionDownloadingFileState)
				{
					CKInternalTransferRecord *download = [[self currentDownload] retain];
					[self dequeueDownload];
					
					if (_flags.downloadFinished)
						[_forwarder connection:self downloadDidFinish:[download remotePath] error:[_receiveStream streamError]];
					if ([download delegateRespondsToTransferDidFinish])
						[[download delegate] transferDidFinish:[download userInfo] error:[_receiveStream streamError]];
					
					[download release];
					
					//At this point the top of the command queue is something associated with this download. Remove it and all of its dependents.
					[_queueLock lock];
					CKConnectionCommand *nextCommand = ([_commandQueue count] > 0) ? [_commandQueue objectAtIndex:0] : nil;
					if (nextCommand)
					{
						NSEnumerator *e = [[nextCommand dependantCommands] objectEnumerator];
						CKConnectionCommand *dependent;
						while (dependent = [e nextObject])
						{
							[_commandQueue removeObject:dependent];
						}
						
						[_commandQueue removeObject:nextCommand];
					}
					[_queueLock unlock];
					[self setState:CKConnectionIdleState];
				}
				//This will most likely occur when there is a misconfig of the server and we cannot open a data connection so we have unroll the command stack
				[self closeDataStreams];
				NSArray *history = [self commandHistory];
				//NSDictionary *conCommand = [history objectAtIndex:1];
			//	NSLog(@"command history:\n%@", [[self commandHistory] description]);
				CKConnectionCommand *lastCommand = [history objectAtIndex:0];
				CKConnectionState lastState = [lastCommand sentState];
				
				if (lastState == FTPSettingEPSVState) 
				{
					_ftpFlags.canUseEPSV = NO;
					[self sendCommand:@"DATA_CON"];
					break;
				} 
				else if (lastState == FTPSettingEPRTState) 
				{
					_ftpFlags.canUseEPRT = NO;
					[self sendCommand:@"DATA_CON"];
					break;
				} 
				else if (lastState == FTPSettingActiveState)
				{
					_ftpFlags.canUseActive = NO;
					[self sendCommand:@"DATA_CON"];
					break;
				}
				else if (lastState == FTPSettingPassiveState) 
				{
					_ftpFlags.canUseActive = NO;
					[self sendCommand:@"DATA_CON"];
				}
			}
			else 
			{
				KTLog(CKStreamDomain, KTLogDebug, @"NSStreamEventErrorOccurred: %@", [_dataReceiveStream streamError]);
			}
			
			break;
		}
		case NSStreamEventEndEncountered:
		{
			KTLog(CKStreamDomain, KTLogDebug, @"FTP Data receive stream ended");
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
			
			KTLog(CKTransportDomain, KTLogDebug, @"FTP Data send stream opened");
			
			if (!_ftpFlags.isActiveDataConn)
				[self setState:CKConnectionIdleState];
			break;
		}
		case NSStreamEventErrorOccurred:
		{
			if (_flags.transcript)
			{
				[self appendSentStringToTranscript:[NSString stringWithFormat:@"Send Stream Error: %@\n", [_receiveStream streamError]]];
			}
			KTLog(CKStreamDomain, KTLogDebug, @"send error %@", [_sendStream streamError]);
			// we don't want the error to go to the delegate unless we fail on setting the active con
			/* Some servers when trying to test PASV can crap out and throw an error */
			if (GET_STATE == FTPSettingEPSVState) 
			{
				_ftpFlags.canUseEPSV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingEPRTState) 
			{
				_ftpFlags.canUseEPRT = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingActiveState) 
			{
				_ftpFlags.canUseActive = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}
			if (GET_STATE == FTPSettingPassiveState) 
			{
				_ftpFlags.canUsePASV = NO;
				[self closeDataStreams];
				[self sendCommand:@"DATA_CON"];
				break;
			}			
			// if uploading, skip the transfer
			if (GET_STATE == CKConnectionUploadingFileState || 
				GET_STATE == CKConnectionDownloadingFileState ||
				GET_STATE == FTPAwaitingDataConnectionToOpen ||
				GET_STATE == CKConnectionAwaitingDirectoryContentsState) {
				if (GET_STATE == CKConnectionUploadingFileState)
				{
					CKInternalTransferRecord *rec = [self currentUpload];
					if ([rec delegateRespondsToError])
					{
						[[rec delegate] transfer:[rec userInfo] receivedError:[_sendStream streamError]];
					}
				}
				if (GET_STATE == CKConnectionDownloadingFileState)
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
				CKConnectionCommand *lastCommand = [history objectAtIndex:0];
				CKConnectionState lastState = [lastCommand sentState];
				
				if (lastState == FTPSettingEPSVState) 
				{
					_ftpFlags.canUseEPSV = NO;
					[self sendCommand:@"DATA_CON"];
					break;
				} 
				else if (lastState == FTPSettingEPRTState) 
				{
					_ftpFlags.canUseEPRT = NO;
					[self sendCommand:@"DATA_CON"];
					break;
				} 
				else if (lastState == FTPSettingActiveState)
				{
					_ftpFlags.canUseActive = NO;
					[self sendCommand:@"DATA_CON"];
					break;
				}
				else if (lastState == FTPSettingPassiveState) 
				{
					_ftpFlags.canUseActive = NO;
					[self sendCommand:@"DATA_CON"];
				}
			}
			else {
				KTLog(CKStreamDomain, KTLogDebug, @"NSStreamEventErrorOccurred: %@", [_dataReceiveStream streamError]);
				if (_flags.error) {
					[_forwarder connection:self didReceiveError:[_dataReceiveStream streamError]];	
				}
			}
			
			break;
		}
		case NSStreamEventEndEncountered:
		{
			KTLog(CKStreamDomain, KTLogDebug, @"FTP Data send stream ended");
			[self closeDataConnection];
			break;
		}
		case NSStreamEventNone:
		{
			break;
		}
		case NSStreamEventHasSpaceAvailable:
		{
			if (GET_STATE == CKConnectionUploadingFileState)
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
					_transferCursor += chunkLength;
					
					//if ([self isAboveNotificationTimeThreshold:[NSDate date]]) {
					if ([upload delegateRespondsToTransferTransferredData])
					{
						[[upload delegate] transfer:[upload userInfo] transferredDataOfLength:chunkLength];
					}
						if (_flags.uploadProgressed)
						{
							[_forwarder connection:self upload:remoteFile sentDataOfLength:chunkLength];
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
			KTLog(CKStreamDomain, KTLogDebug, @"Composite Event Code!  Need to deal with this!");
			break;
		}
	}
}

- (void)closeDataConnection
{
	KTLog(CKStreamDomain, KTLogDebug, @"closeDataConnection");
	[self closeDataStreams];
	
	// no delegate notifications if we force disconnected the connection
	if (_isForceDisconnecting)
	{
		_isForceDisconnecting = NO;
		return;
	}
	
	if (GET_STATE == CKConnectionDownloadingFileState)
	{
		CKInternalTransferRecord *download = [[self currentDownload] retain];
		[self dequeueDownload];
		
		if (_flags.downloadFinished)
		{
			[_forwarder connection:self downloadDidFinish:[download remotePath] error:nil];
		}
		if ([download delegateRespondsToTransferDidFinish])
		{
			[[download delegate] transferDidFinish:[download userInfo] error:nil];
		}
		[_writeHandle closeFile];
		[self setWriteHandle:nil];
		
		if (_ftpFlags.received226)
		{
			[self setState:CKConnectionIdleState];
		}
		[download release];
	}
	else if (GET_STATE == CKConnectionUploadingFileState)
	{
		CKInternalTransferRecord *upload = [[self currentUpload] retain];
		[self dequeueUpload];
		
		if (_flags.uploadFinished) 
		{
			[_forwarder connection:self uploadDidFinish:[upload remotePath] error:nil];
		}
		if ([upload delegateRespondsToTransferDidFinish])
		{
			[[upload delegate] transferDidFinish:[upload userInfo] error:nil];
		}
		[self setReadData:nil];
		[self setReadHandle:nil];
		_transferSize = 0;
		
		if (_ftpFlags.received226)
		{
			[self setState:CKConnectionIdleState];
		}
		[upload release];
	}
	else if (GET_STATE == CKConnectionAwaitingDirectoryContentsState)
	{
		NSString *results = [[NSString alloc] initWithData:_dataBuffer encoding:NSUTF8StringEncoding];
		if (!results)
		{
			//Try ASCII
			results = [[NSString alloc] initWithData:_dataBuffer encoding:NSASCIIStringEncoding];
			if (!results)
			{
				//We failed!
				return;
			}
		}
		[self appendDataStringToTranscript:results];

		NSArray *contents = [self parseLines:results];
		
		KTLog(CKParsingDomain, KTLogDebug, @"Contents of Directory %@:\n%@", _currentPath, [contents shortDescription]);
		
		[self cacheDirectory:_currentPath withContents:contents];
		
		if (_flags.directoryContents)
		{
			[_forwarder connection:self didReceiveContents:contents ofDirectory:_currentPath error:nil];
		}
		[results release];
		[_dataBuffer setLength:0];

		if (_ftpFlags.received226)
		{
			[self setState:CKConnectionIdleState];
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
	//cancel the noop timer
	[_noopTimer invalidate];
	[_noopTimer release]; _noopTimer = nil;
	
	//_ftpFlags.isActiveDataConn = NO;
}

- (void)openDataStreamsToHost:(NSHost *)aHost port:(int)aPort 
{	
	[NSStream getStreamsToHost:aHost
						  port:aPort
				   inputStream:&_dataReceiveStream
				  outputStream:&_dataSendStream];
	
	[self prepareAndOpenDataStreams];
	
	// send no op commands
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	if ([ud objectForKey:@"FTPSendsNoOps"] && [[ud objectForKey:@"FTPSendsNoOps"] boolValue])
	{
		_noopTimer = [[NSTimer scheduledTimerWithTimeInterval:60
													   target:self
													 selector:@selector(sendNoOp:)
													 userInfo:nil
													  repeats:YES] retain];
	}
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
	
	unsigned dataConnectionTimeout = 10;
	NSNumber *defaultsValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"CKFTPDataConnectionTimeoutValue"];
	if (defaultsValue) {
		dataConnectionTimeout = [defaultsValue unsignedIntValue];
	}
	
	KTLog(CKTransportDomain, KTLogDebug, @"Setting data connection timeout to %u seconds", dataConnectionTimeout);
	[_openStreamsTimeout invalidate];
	_openStreamsTimeout = [[NSTimer scheduledTimerWithTimeInterval:dataConnectionTimeout
															target:self
														  selector:@selector(dataConnectionOpenTimedOut:) 
														  userInfo:nil
														   repeats:NO] retain];
}

- (void)dataConnectionOpenTimedOut:(NSTimer *)timer
{
	//do something
	KTLog(CKTransportDomain, KTLogError, @"Timed out opening data connection");

	if (_flags.transcript)
	{
		NSString *timeout = [NSString stringWithString:LocalizedStringInConnectionKitBundle(@"Data Stream Timed Out", @"Failed to open a data stream connection")];
		[self appendDataStringToTranscript:[NSString stringWithFormat:@"%@\n", timeout]];
	}
	
	[timer invalidate];
	[_openStreamsTimeout release];
	_openStreamsTimeout = nil;
	[self closeDataStreams];
	
	CKConnectionCommand *last = [self lastCommand];
	CKConnectionState lastState = [last sentState];
	
	if (lastState == FTPSettingEPSVState) 
	{
		_ftpFlags.canUseEPSV = NO;
		[self closeDataStreams];
		[self sendCommand:@"DATA_CON"];
	}
	else if (lastState == FTPSettingEPRTState) 
	{
		_ftpFlags.canUseEPRT = NO;
		[self closeDataStreams];
		[self sendCommand:@"DATA_CON"];
	}
	else if (lastState == FTPSettingActiveState) 
	{
		_ftpFlags.canUseActive = NO;
		[self closeDataStreams];
		[self sendCommand:@"DATA_CON"];
	}
	else if (lastState == FTPSettingPassiveState) 
	{
		_ftpFlags.canUsePASV = NO;
		[self closeDataStreams];
		[self sendCommand:@"DATA_CON"];
	}			
}

- (void)closeStreams
{
	_ftpFlags.setBinaryTransferMode = NO;
	[super closeStreams];
}

#pragma mark -
#pragma mark Operations

- (void)changeToDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"dirPath is nil!");
	
	CKConnectionCommand *pwd = [CKConnectionCommand command:@"PWD"
											 awaitState:CKConnectionIdleState 
											  sentState:CKConnectionAwaitingCurrentDirectoryState
											  dependant:nil
											   userInfo:nil];
	CKConnectionCommand *cwd = [CKConnectionCommand command:[NSString stringWithFormat:@"CWD %@", dirPath]
											 awaitState:CKConnectionIdleState 
											  sentState:CKConnectionChangingDirectoryState
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
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no directory specified");
	
	CKConnectionCommand *cmd = [CKConnectionCommand command:[NSString stringWithFormat:@"MKD %@", dirPath]
											 awaitState:CKConnectionIdleState 
											  sentState:CKConnectionCreateDirectoryState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

- (void)threadedSetPermissions:(NSNumber *)perms forFile:(NSString *)path
{
	unsigned long permissions = [perms unsignedLongValue];
	NSString *cmd = [NSString stringWithFormat:@"SITE CHMOD %lo %@", permissions, path];
	CKConnectionCommand *com = [CKConnectionCommand command:cmd
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionSettingPermissionsState
											  dependant:nil
											   userInfo:nil];
	[self pushCommandOnHistoryQueue:com];
	[self sendCommand:cmd];
	// Not all servers return SITE in the FEAT request.
	/*if (_ftpFlags.hasSITE)
	{
		unsigned long permissions = [perms unsignedLongValue];
		NSString *cmd = [NSString stringWithFormat:@"SITE CHMOD %lo %@", permissions, path];
		ConnectionCommand *com = [ConnectionCommand command:cmd
												 awaitState:CKConnectionIdleState
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
		[self setState:CKConnectionIdleState];
	}*/
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no directory specified");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(threadedSetPermissions:forFile:)
													  target:self
												   arguments:[NSArray arrayWithObjects: [NSNumber numberWithUnsignedLong:permissions], dirPath, nil]];
	CKConnectionCommand *chmod = [CKConnectionCommand command:inv
											   awaitState:CKConnectionIdleState 
												sentState:CKConnectionSettingPermissionsState
												dependant:nil
												 userInfo:nil];
	CKConnectionCommand *mkdir = [CKConnectionCommand command:[NSString stringWithFormat:@"MKD %@", dirPath]
											   awaitState:CKConnectionIdleState 
												sentState:CKConnectionCreateDirectoryState
												dependant:chmod
												 userInfo:nil];
	[self queuePermissionChange:dirPath];
	[self queueCommand:mkdir];
	[self queueCommand:chmod];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"no file/path specified");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(threadedSetPermissions:forFile:)
													  target:self
												   arguments:[NSArray arrayWithObjects: [NSNumber numberWithUnsignedLong:permissions], path, nil]];
	[self queuePermissionChange:path];
	CKConnectionCommand *chmod = [CKConnectionCommand command:inv
											   awaitState:CKConnectionIdleState 
												sentState:CKConnectionSettingPermissionsState
												dependant:nil
												 userInfo:path];
	[self queueCommand:chmod];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"dirPath is nil!");
	
	[self queueDeletion:dirPath];
	CKConnectionCommand *rm = [CKConnectionCommand command:[NSString stringWithFormat:@"RMD %@", dirPath]
											awaitState:CKConnectionIdleState 
											 sentState:CKConnectionDeleteDirectoryState
											 dependant:nil
											  userInfo:dirPath];
	[self queueCommand:rm];
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSAssert(fromPath && ![fromPath isEqualToString:@""], @"fromPath is nil!");
    NSAssert(toPath && ![toPath isEqualToString:@""], @"toPath is nil!");
			
	[self queueRename:fromPath];
	[self queueRename:toPath];

	CKConnectionCommand *to = [CKConnectionCommand command:[NSString stringWithFormat:@"RNTO %@", toPath]
											awaitState:CKConnectionRenameToState 
											 sentState:CKConnectionAwaitingRenameState
											 dependant:nil
											  userInfo:toPath];
	CKConnectionCommand *from = [CKConnectionCommand command:[NSString stringWithFormat:@"RNFR %@", fromPath]
											  awaitState:CKConnectionIdleState 
											   sentState:CKConnectionRenameFromState
											   dependant:to
												userInfo:fromPath];
	[self queueCommand:from];
	[self queueCommand:to];
}

- (void)deleteFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"path is nil!");
	
	[self queueDeletion:path];
	CKConnectionCommand *del = [CKConnectionCommand command:[NSString stringWithFormat:@"DELE %@", path]
											 awaitState:CKConnectionIdleState 
											  sentState:CKConnectionDeleteFileState
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
	NSAssert(localPath && ![localPath isEqualToString:@""], @"localPath is nil!");
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
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

- (CKTransferRecord *)uploadFromData:(NSData *)data
							  toFile:(NSString *)remotePath 
				checkRemoteExistence:(BOOL)flag
							delegate:(id)delegate
{
	NSAssert(data, @"no data");	// data should not be nil, but it shoud be OK to have zero length!
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"remotePath is nil!");
	
	return [self uploadFile:nil
					 orData:data
					 offset:0
				 remotePath:remotePath
	   checkRemoteExistence:flag
				   delegate:delegate];
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
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"no remotePath");
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
	NSString *remoteFileName = [remotePath lastPathComponent];
	NSString *localPath = [dirPath stringByAppendingPathComponent:remoteFileName];
	
	if (!flag)
	{
		if ([[NSFileManager defaultManager] fileExistsAtPath:localPath])
		{
			if (_flags.error)
			{
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
										  LocalizedStringInConnectionKitBundle(@"Local File already exists", @"FTP download error"), NSLocalizedDescriptionKey,
										  remotePath, NSFilePathErrorKey, nil];
				NSError *error = [NSError errorWithDomain:CKFTPErrorDomain code:FTPDownloadFileExists userInfo:userInfo];
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
	CKTransferRecord *record = [CKTransferRecord recordWithName:remotePath size:0];
	CKInternalTransferRecord *download = [CKInternalTransferRecord recordWithLocal:localPath
																			  data:nil
																			offset:0
																			remote:remotePath
																		  delegate:delegate ? delegate : record
																		  userInfo:record];
	[record setProperty:remotePath forKey:CKQueueDownloadRemoteFileKey];
	[record setProperty:localPath forKey:CKQueueDownloadDestinationFileKey];
	[record setProperty:[NSNumber numberWithInt:0] forKey:CKQueueDownloadTransferPercentReceived];

	[self queueDownload:download];
	
	CKConnectionCommand *retr = [CKConnectionCommand command:[NSString stringWithFormat:@"RETR %@", remotePath]
											  awaitState:CKConnectionIdleState 
											   sentState:CKConnectionDownloadingFileState
											   dependant:nil
												userInfo:download];
	CKConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	[dataCmd addDependantCommand: retr];
	
	CKConnectionCommand *size = [CKConnectionCommand command:[NSString stringWithFormat:@"SIZE %@", remotePath]
											  awaitState:CKConnectionIdleState 
											   sentState:CKConnectionSentSizeState
											   dependant:dataCmd
												userInfo:nil];
	
	if (!_ftpFlags.setBinaryTransferMode) {
		CKConnectionCommand *bin = [CKConnectionCommand command:@"TYPE I"
											 awaitState:CKConnectionIdleState
											  sentState:FTPModeChangeState
											  dependant:nil
											   userInfo:nil];
		[self queueCommand:bin];
		_ftpFlags.setBinaryTransferMode = YES;
	}
	
	
	if (_ftpFlags.hasSize)
		[self queueCommand:size];
	[self queueCommand:dataCmd];
	[self queueCommand:retr];
	[self endBulkCommands];
	
	return record;
}

- (CKTransferRecord *)resumeDownloadFile:(NSString *)remotePath
							 toDirectory:(NSString *)dirPath
							  fileOffset:(unsigned long long)offset
								delegate:(id)delegate
{
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"no remotePath");
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
	NSNumber *off = [NSNumber numberWithLongLong:offset];
	NSString *remoteFileName = [remotePath lastPathComponent];
	NSString *localPath = [dirPath stringByAppendingPathComponent:remoteFileName];
	
	/*
	 TYPE I
	 SIZE file
	 PASV/EPSV/ERPT/PORT
	 RETR file
	 TYPE A
	 */

	[self startBulkCommands];
	CKTransferRecord *record = [CKTransferRecord recordWithName:remotePath size:0];
	CKInternalTransferRecord *download = [CKInternalTransferRecord recordWithLocal:localPath
																			  data:nil
																			offset:offset
																			remote:remotePath
																		  delegate:delegate ? delegate : record
																		  userInfo:record];
	[record setProperty:remotePath forKey:CKQueueDownloadRemoteFileKey];
	[record setProperty:localPath forKey:CKQueueDownloadDestinationFileKey];
	[record setProperty:[NSNumber numberWithInt:0] forKey:CKQueueDownloadTransferPercentReceived];

	[self queueDownload:download];
	
	CKConnectionCommand *retr = [CKConnectionCommand command:[NSString stringWithFormat:@"RETR %@", remotePath]
											  awaitState:CKConnectionIdleState 
											   sentState:CKConnectionDownloadingFileState
											   dependant:nil
												userInfo:download];
	
	CKConnectionCommand *rest = [CKConnectionCommand command:[NSString stringWithFormat:@"REST %@", off]
											  awaitState:CKConnectionIdleState 
											   sentState:CKConnectionSentOffsetState
											   dependant:retr
												userInfo:nil];
	
	CKConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	[dataCmd addDependantCommand:rest];
	
	CKConnectionCommand *size = [CKConnectionCommand command:[NSString stringWithFormat:@"SIZE %@", remotePath]
											  awaitState:CKConnectionIdleState 
											   sentState:CKConnectionSentSizeState
											   dependant:dataCmd
												userInfo:nil];
	
	if (!_ftpFlags.setBinaryTransferMode) {
		CKConnectionCommand *bin = [CKConnectionCommand command:@"TYPE I"
												 awaitState:CKConnectionIdleState
												  sentState:FTPModeChangeState
												  dependant:nil
												   userInfo:nil];
		[self queueCommand:bin];
		_ftpFlags.setBinaryTransferMode = YES;
	}
	
	if (_ftpFlags.hasSize)
		[self queueCommand:size];
	[self queueCommand:dataCmd];
	[self queueCommand:rest];
	[self queueCommand:retr];
	[self endBulkCommands];
	
	return record;
}

- (void)directoryContents
{
	CKConnectionCommand *ls = [CKConnectionCommand command:@"LIST -a" 
											awaitState:CKConnectionIdleState 
											 sentState:CKConnectionAwaitingDirectoryContentsState 
											 dependant:nil 
											  userInfo:nil];
	CKConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	[dataCmd addDependantCommand:ls];
	
	[self queueCommand:dataCmd];
	[self queueCommand:ls];
}

- (void)threadedContentsOfDirectory:(NSString *)dirPath
{
	NSString *currentDir = [[[self currentDirectory] copy] autorelease];
	
	CKConnectionCommand *pwd2 = [CKConnectionCommand command:@"PWD"
											  awaitState:CKConnectionIdleState 
											   sentState:CKConnectionAwaitingCurrentDirectoryState
											   dependant:nil
												userInfo:nil];
	CKConnectionCommand *cwd2 = [CKConnectionCommand command:[NSString stringWithFormat:@"CWD %@", currentDir]
											  awaitState:CKConnectionIdleState 
											   sentState:CKConnectionChangingDirectoryState
											   dependant:pwd2
												userInfo:nil];
	
	CKConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	CKConnectionCommand *ls = [CKConnectionCommand command:@"LIST -a" 
											awaitState:CKConnectionIdleState 
											 sentState:CKConnectionAwaitingDirectoryContentsState 
											 dependant:dataCmd 
											  userInfo:nil];
	
	CKConnectionCommand *pwd = [CKConnectionCommand command:@"PWD"
											 awaitState:CKConnectionIdleState 
											  sentState:CKConnectionAwaitingCurrentDirectoryState
											  dependant:nil
											   userInfo:nil];
	CKConnectionCommand *cwd = [CKConnectionCommand command:[NSString stringWithFormat:@"CWD %@", dirPath]
											 awaitState:CKConnectionIdleState 
											  sentState:CKConnectionChangingDirectoryState
											  dependant:pwd
											   userInfo:nil];
	[self startBulkCommands];
	[_commandQueue insertObject:pwd2 atIndex:0];
	[_commandQueue insertObject:cwd2 atIndex:0];
	[_commandQueue insertObject:ls atIndex:0];
	[_commandQueue insertObject:dataCmd atIndex:0];
	[_commandQueue insertObject:pwd atIndex:0];
	[_commandQueue insertObject:cwd atIndex:0];
	[self endBulkCommands];
	[self setState:CKConnectionIdleState];
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
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(threadedContentsOfDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObject:dirPath]];
	CKConnectionCommand *ls = [CKConnectionCommand command:inv
											awaitState:CKConnectionIdleState 
											 sentState:CKConnectionAwaitingDirectoryContentsState 
											 dependant:nil 
											  userInfo:nil];
	[self queueCommand:ls];
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
		case FTPNoOpState: return @"FTPNoOpState";
		default: return [super stateName:state];
	}
}

- (CKConnectionCommand *)nextAvailableDataConnectionType
{
	/*
	 This property is a string specifying the preferred data connection type. If it's specified, we will keep trying with *that* connection type. This is desired behavior because as is often the case, the second or third (or 10th, if we experience a connection drop) try at setting a given data type will work –– whereas falling back to other (typically unsupported) types will not. Thus, by setting this property, you are *explicitly* asking this connection to connect *only* with that connection type.
	 
	 If it's not specified, we'll continually fall back to different connection types until we find that works (or fail.)
	 
	 Supported Types (as strings) are:
	 (1) "Passive"
	 (2) "Extended Passive"
	 (3) "Extended Active"
	 (4) "Active"
	 */
	NSString *preferredDataConnectionType = [self propertyForKey:@"CKFTPDataConnectionType"];
	
	NSString *connectionTypeString = nil;
	CKConnectionState sendState;
	
	BOOL explicitlySetConnectionType = (preferredDataConnectionType && [preferredDataConnectionType length] > 0);
	BOOL prefersPASV = (explicitlySetConnectionType && [preferredDataConnectionType isEqualToString:@"Passive"]);
	BOOL prefersEPSV = (explicitlySetConnectionType && [preferredDataConnectionType isEqualToString:@"Extended Passive"]);
	BOOL prefersEPRT = (explicitlySetConnectionType && [preferredDataConnectionType isEqualToString:@"Extended Active"]);
	BOOL prefersPORT = (explicitlySetConnectionType && [preferredDataConnectionType isEqualToString:@"Active"]);
	
	if (prefersPASV || (!explicitlySetConnectionType && _ftpFlags.canUsePASV))
	{
		connectionTypeString = @"PASV";
		sendState = FTPSettingPassiveState;
	}
	else if (prefersEPSV || (!explicitlySetConnectionType && _ftpFlags.canUseEPSV))
	{
		connectionTypeString = @"EPSV";
		sendState = FTPSettingEPSVState;
	}
	else if (prefersEPRT || (!explicitlySetConnectionType && _ftpFlags.canUseEPRT))
	{
		connectionTypeString = @"EPRT";
		sendState = FTPSettingEPRTState;
	}
	else if (prefersPORT || (!explicitlySetConnectionType && _ftpFlags.canUseActive))
	{
		connectionTypeString = @"PORT";
		sendState = FTPSettingActiveState;
	}
	else
	{
		if (_flags.error)
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Exhausted all connection types to server. Please contact server administrator", @"FTP no data streams available");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  [[self URL] host], ConnectionHostKey, nil];
			NSError *err = [NSError errorWithDomain:CKFTPErrorDomain code:FTPErrorNoDataModes userInfo:userInfo];
			[_forwarder connection:self didReceiveError:err];
		}
	}
	
	CKConnectionCommand *command;
	if (connectionTypeString)
	{
		command = [CKConnectionCommand command:connectionTypeString
								  awaitState:CKConnectionIdleState
								   sentState:sendState
								   dependant:nil
									userInfo:nil];
	}
	else
	{
		command = [CKConnectionCommand command:@"QUIT"
								  awaitState:CKConnectionIdleState	
								   sentState:CKConnectionSentQuitState
								   dependant:nil
									userInfo:nil];		
	}
	_ftpFlags.received226 = NO;
	
	
	return command;
}

- (CKConnectionCommand *)pushDataConnectionOnCommandQueue
{
	return [CKConnectionCommand command:@"DATA_CON"
						   awaitState:CKConnectionIdleState
							sentState:FTPDeterminingDataConnectionType
							dependant:nil
							 userInfo:nil];
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
	CKFTPConnection *con = (CKFTPConnection *)info;
	CFSocketNativeHandle connectedFrom = *(CFSocketNativeHandle *)data;
	CFReadStreamRef read;
	CFWriteStreamRef write;
		
	CFStreamCreatePairWithSocket(kCFAllocatorDefault,connectedFrom,&read,&write);
	//cast as NSStreams
	NSInputStream *iStream = [(NSInputStream *)read autorelease];
	NSOutputStream *oStream = [(NSOutputStream *)write autorelease];
	
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
	if (src)
	{
		CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
		CFRelease(src);
	}
	
	CFSocketError err;
	struct sockaddr_in my_addr;
	
	memset(&my_addr, 0, sizeof(my_addr));
	my_addr.sin_family = PF_INET;    
	my_addr.sin_port = htons(port); 
	my_addr.sin_addr.s_addr = inet_addr([[[NSHost currentHost] ipv4Address] UTF8String]);
	bzero(&(my_addr.sin_zero), 8);
	
	CFDataRef addrData = CFDataCreate(kCFAllocatorDefault,(const UInt8 *)&my_addr,sizeof(my_addr));
	if (addrData)
	{
		err = CFSocketSetAddress(_activeSocket,addrData);
		CFRelease(addrData);
	}
	
	if (err != kCFSocketSuccess) {
		KTLog(CKTransportDomain, KTLogError, @"Failed CFSocketSetAddress() to %@:%u", [[NSHost currentHost] ipv4Address], port);
		if (_activeSocket)
		{
			CFSocketInvalidate(_activeSocket);
			CFRelease(_activeSocket);
			_activeSocket = nil;
		}
		
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
		KTLog(CKTransportDomain, KTLogError, @"Failed to setup EPRT socket, trying PORT");
		//try doing a port command
		_ftpFlags.canUseEPRT = NO;
		_state = FTPSettingActiveState;
		return [self setupActiveConnection];
	}
	
	CFDataRef addrData = CFSocketCopyAddress(_activeSocket);
	
	struct sockaddr_in active_addr;
	CFDataGetBytes(addrData,CFRangeMake(0,CFDataGetLength(addrData)),(UInt8 *)&active_addr);
	if (addrData) CFRelease(addrData);

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
		KTLog(CKTransportDomain, KTLogError, @"Failed to setup PORT socket, trying PASV");
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
	[result replaceOccurrencesOfString:@"\"\"" withString:@"\"" options:NSLiteralSearch range:NSMakeRange(0, [result length])];
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
	
	KTLog(CKQueueDomain, KTLogDebug, @"Queueing Upload: localPath = %@ data = %d bytes offset = %lld remotePath = %@", localPath, [data length], offset, remotePath);
	
	CKConnectionCommand *store = [CKConnectionCommand command:[NSString stringWithFormat:@"STOR %@", remotePath]
											   awaitState:CKConnectionIdleState
												sentState:CKConnectionUploadingFileState
												dependant:nil
												 userInfo:nil];
	CKConnectionCommand *rest = nil;
	if (offset != 0) {
		rest = [CKConnectionCommand command:[NSString stringWithFormat:@"REST %qu", offset]
							   awaitState:CKConnectionIdleState
								sentState:CKConnectionSentOffsetState
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
	[record setObject:localPath forKey:CKQueueUploadLocalFileKey];
	[record setObject:remotePath forKey:CKQueueUploadRemoteFileKey];
	
	CKInternalTransferRecord *dict = [CKInternalTransferRecord recordWithLocal:localPath
																		  data:data
																		offset:offset
																		remote:remotePath
																	  delegate:delegate ? delegate : record
																	  userInfo:record];
	[self queueUpload:dict];
	[store setUserInfo:dict];
	
	CKConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	[dataCmd addDependantCommand:offset != 0 ? rest : store];
	[dataCmd setUserInfo:dict];
	
	[self startBulkCommands];
	
	if (!_ftpFlags.setBinaryTransferMode) {
		CKConnectionCommand *bin = [CKConnectionCommand command:@"TYPE I"
											 awaitState:CKConnectionIdleState
											  sentState:FTPModeChangeState
											  dependant:nil
											   userInfo:nil];
		[self queueCommand:bin];
		_ftpFlags.setBinaryTransferMode = YES;
	}
	
	
	[self queueCommand:dataCmd];
	
	if (0 != offset)
	{
		[self queueCommand:rest];
	}
	[self queueCommand:store];
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

- (void)sendNoOp:(NSTimer *)timer
{
	[self sendCommand:@"NOOP"];
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


#pragma mark -


@implementation CKFTPConnection (Authentication)

- (NSURLCredential *)currentAuthenticationCredential { return _currentAuthenticationCredential; }

- (void)setCurrentAuthenticationCredential:(NSURLCredential *)credential
{
    credential = [credential copy];
    [_currentAuthenticationCredential release]; // Should generally be nil already
    _currentAuthenticationCredential = credential;
}

/*  Uses the delegate to authenticate the connection. If the delegate (heaven forbid) doesn't
 *  implement authentication, we will fall back to annonymous login if possible.
 */
- (void)authenticateConnection
{
    // Cancel old credentials
    [self setCurrentAuthenticationCredential:nil];
    
    
    // Create authentication challenge object and store it as the last authentication attempt
    NSInteger previousFailureCount = 0;
    if (_lastAuthenticationChallenge)
    {
        previousFailureCount = [_lastAuthenticationChallenge previousFailureCount] + 1;
    }
    
    
    [_lastAuthenticationChallenge release];
    
    NSURLProtectionSpace *protectionSpace = [[CKURLProtectionSpace alloc] initWithHost:[[self URL] host]
                                                                                  port:[self port]
                                                                              protocol:[[self URL] scheme]
                                                                                 realm:nil
                                                                  authenticationMethod:NSURLAuthenticationMethodDefault];
    
    _lastAuthenticationChallenge = [[NSURLAuthenticationChallenge alloc]
                                    initWithProtectionSpace:protectionSpace
                                    proposedCredential:[self proposedCredentialForProtectionSpace:protectionSpace]
                                    previousFailureCount:previousFailureCount
                                    failureResponse:nil
                                    error:nil
                                    sender:self];
    
    [protectionSpace release];
    
    // As the delegate to handle the challenge
    [self didReceiveAuthenticationChallenge:_lastAuthenticationChallenge];    
}

/*  FTP's horrible design requires us to send the username or account name and then wait for a response
 *  before sending the password. This method performs the second half of the operation and sends the
 *  password that our delegate previously supplied.
 */
- (void)sendPassword
{
    NSString *password = [[[self currentAuthenticationCredential] password] copy];
    
    // Dispose of the credentials once the password has been sent
    [self setCurrentAuthenticationCredential:nil];
       
    if (password)   // Should we do anything special if this fails?
    {
        [self sendCommand:[NSString stringWithFormat:@"PASS %@", password]];
        [self setState:CKConnectionSentPasswordState];
        [password release];
    }
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge == _lastAuthenticationChallenge)
    {
        [self disconnect];
    }
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    // TODO: Attempt to continue downloading, login anonymously, or disconnect with an error?
}

/*  Start login
 */
- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge == _lastAuthenticationChallenge)
    {
        // Store the credentials ready for the password request
        [self setCurrentAuthenticationCredential:credential];
        
        // Send the username
        [self setState:CKConnectionSentUsernameState];
        [self sendCommand:[NSString stringWithFormat:@"USER %@", [credential user]]];
    }
}

@end


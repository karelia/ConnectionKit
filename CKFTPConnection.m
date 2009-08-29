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

#import "NSFileManager+Connection.h"
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

@interface CKFTPConnection ()

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

- (void)_changeToDirectory:(NSString *)dirPath forDependentCommand:(CKConnectionCommand *)dependentCommand;


- (NSString *)currentPath;
- (void)setCurrentPath:(NSString *)aCurrentPath;
- (NSString *)topQueuedChangeDirectoryPath;
- (void)setTopQueuedChangeDirectoryPath:(NSString *)path;

- (BOOL)isAboveNotificationTimeThreshold:(NSDate *)date;

- (CKFTPCommand *)setupEPRTConnection; //returns the command after creating a socket
- (CKFTPCommand *)setupActiveConnection; //return the cmmand after creating a socket

- (void)setDataInputStreamAndOpen:(NSInputStream *)iStream outputStream:(NSOutputStream *)oStream socket:(CFSocketNativeHandle)socket;
- (void)prepareAndOpenDataStreams;

//Command Handling
- (void)_receivedReplyInConnectionNotConnectedState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionSentUsernameState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionSentAccountState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionSentPasswordState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionAwaitingCurrentDirectoryState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionAwaitingDirectoryContentsState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionChangingDirectoryState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionCreateDirectoryState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionDeleteDirectoryState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionRenameFromState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionAwaitingRenameState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionDeleteFileState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionDownloadingFileState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionUploadingFileState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionSentOffsetState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionSentFeatureRequestState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionSentQuitState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionSettingPermissionsState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionSentSizeState:(CKFTPReply *)reply;
- (void)_receivedReplyInConnectionSentDisconnectState:(CKFTPReply *)reply;
- (void)_receivedReplyInFTPSettingPassiveState:(CKFTPReply *)reply;
- (void)_receivedReplyInFTPSettingEPSVState:(CKFTPReply *)reply;
- (void)_receivedReplyInFTPSettingActiveState:(CKFTPReply *)reply;
- (void)_receivedReplyInFTPSettingEPRTState:(CKFTPReply *)reply;
- (void)_receivedReplyInFTPAwaitingRemoteSystemTypeState:(CKFTPReply *)reply;
- (void)_receivedReplyInFTPChangeDirectoryListingStyleState:(CKFTPReply *)reply;

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

	//Register all URL Schemes and the protocol.
	NSEnumerator *URLSchemeEnumerator = [[self URLSchemes] objectEnumerator];
	NSString *URLScheme;
	while ((URLScheme = [URLSchemeEnumerator nextObject]))
		[[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forProtocol:[self protocol] URLScheme:URLScheme];
	
	[pool release];
}

+ (NSInteger)defaultPort { return 21; }

+ (CKProtocol)protocol
{
	return CKFTPProtocol;
}

+ (NSArray *)URLSchemes
{
	return [NSArray arrayWithObject:@"ftp"];
}

- (id)initWithRequest:(CKConnectionRequest *)request
{
	if (self = [super initWithRequest:request])
	{
		[self setState:CKConnectionNotConnectedState];
		
		// These are never replaced during the lifetime of this object so we don't bother with accessor methods
		_dataBuffer = [[NSMutableData data] retain];
		
		_ftpFlags.canUseActive = YES;
		_ftpFlags.canUseEPRT = YES;
		_ftpFlags.canUsePASV = YES;
		_ftpFlags.canUseEPSV = YES;
		
		_ftpFlags.hasSize = YES;
		_isConnected = NO;
	}
	return self;
}

- (void)dealloc
{
	[self closeDataStreams];
	[_buffer release];
	[_currentReply release];
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
	
    // There's a possibility it's an invocation instead; so deal with that
	if ([command isKindOfClass:[NSInvocation class]])
	{
		[command invoke];
		return;
	}
	
    
    // Data connection is a bit special and added to the queue as a plain string
	if ([command isKindOfClass:[NSString class]] && [command isEqualToString:@"DATA_CON"])
	{
		CKConnectionCommand *cmd = [self nextAvailableDataConnectionType];
		[self pushCommandOnHistoryQueue:cmd];
		command = [cmd command];
		_state = [cmd sentState];
		[self closeDataConnection];
	}
	
    
    // Everything else
	if ([[command commandCode] isEqualToString:@"EPRT"]) 
	{
		_ftpFlags.isActiveDataConn = YES;
		command = [self setupEPRTConnection];
	} 
	else if ([[command commandCode] isEqualToString:@"PORT"]) 
	{
		_ftpFlags.isActiveDataConn = YES;
		command = [self setupActiveConnection];
	} 
	else if ([[command commandCode] isEqualToString:@"EPSV"])
	{
		_ftpFlags.isActiveDataConn = NO;
	}
	else if ([[command commandCode] isEqualToString:@"PASV"])
	{
		_ftpFlags.isActiveDataConn = NO;
	}
//	else if ([[command description] isEqualToString:@"LIST -a"] && _ftpFlags.isMicrosoft)
//	{
//		command = [CKFTPCommand commandWithCode:@"LIST"];
//	}

	NSString *commandToEcho = [command description];
	if ([[command commandCode] isEqualToString:@"PASS"])
	{
		if (![defaults boolForKey:@"AllowPasswordToBeLogged"])
		{
			commandToEcho = @"PASS ####";
		}
	}
	
    [[self client] appendLine:commandToEcho toTranscript:CKTranscriptSent];
		
	KTLog(CKProtocolDomain, KTLogDebug, @">> %@", commandToEcho);

	if ([[command commandCode] isEqualToString:@"RETR"])
	{
		CKInternalTransferRecord *download = [self currentDownload];
		
        [[self client] downloadDidBegin:[download remotePath]];
		
		if ([download delegateRespondsToTransferDidBegin])
		{
			[[download delegate] transferDidBegin:[download userInfo]];
		}
	}
	if ([[command commandCode] isEqualToString:@"STOR"])
	{
		CKInternalTransferRecord *upload = [self currentUpload];
		
        [[self client] uploadDidBegin:[upload remotePath]];
        
		if ([upload delegateRespondsToTransferDidBegin])
		{
			[[upload delegate] transferDidBegin:[upload userInfo]];
		}
	}
	
	[self sendData:[command serializedCommand]];
}

/*!	The main communication between the foreground thread and the background thread.  Called by EITHER thread.
*/

/*!	Parse the response received from the server.  Called from the background thread.
*/
- (void)parseCommand:(CKFTPReply *)reply
{
	[[self client] appendLine:[reply description] toTranscript:CKTranscriptReceived];
	
	KTLog(CKProtocolDomain, KTLogDebug, @"<<# %@", [reply description]);	/// use <<# to help find commands
	
	int stateToHandle = GET_STATE;
	//State independent handling	
	switch ([reply replyCode])
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
			if ([[[reply textLines] objectAtIndex:0] rangeOfString:@"directory listing"].location != NSNotFound) //Sometimes we get "150 Here comes the directory listing"
			{
				//we'll clean the buffer
				[_buffer setLength:0];
			}
			break;
		}
		case 226:
		{
			_ftpFlags.received226 = YES;
			if ([[[reply textLines] objectAtIndex:0] rangeOfString:@"abort" options:NSCaseInsensitiveSearch].location != NSNotFound)
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
				
                [[self client] connectionDidCancelTransfer:remotePath];
			}
			if (_dataSendStream == nil || _dataReceiveStream == nil)
			{
				[self setState:CKConnectionIdleState];
			}			
			break;
		}
		case 332: //need account
		{
			NSString *account = [[self client] accountForUsername:nil];
            if (account)
            {
                [self sendCommand:[CKFTPCommand commandWithCode:@"ACCT" argumentField:account]];
                [self setState:CKConnectionSentAccountState];
            }
			break;
		}		
		case 421: //service timed out.
		{
			[self closeDataStreams];
			[super threadedDisconnect]; //This empties the queues, etc.
			_isConnected = NO;
            
			[[self client] connectionDidDisconnectFromHost:[[[self request] URL] host]];
            
			
            NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                      localizedDescription, NSLocalizedDescriptionKey,
                                      [reply description], NSLocalizedFailureReasonErrorKey,
                                      [[self request] URL], ConnectionHostKey, nil];
            NSError *error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
            [[self client] connectionDidReceiveError:error];
			
			[self setState:CKConnectionNotConnectedState]; 
			break;
		}	
		case 503: //Bad sequence of commands
		{
			//This is an internal error in the syntax of the commands and arguments sent.
			//We should never get to this state as we should construct commands correctly.
			if (GET_STATE != CKConnectionSentFeatureRequestState)
			{
				KTLog(CKProtocolDomain, KTLogError, @"FTP Internal Error: %@", [reply description]);
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
		default:
			break;
	}
	
	switch (stateToHandle)
	{
		case CKConnectionNotConnectedState:
			[self _receivedReplyInConnectionNotConnectedState:reply];
			break;
		case CKConnectionSentUsernameState:
			[self _receivedReplyInConnectionSentUsernameState:reply];
			break;
		case CKConnectionSentAccountState:
			[self _receivedReplyInConnectionSentAccountState:reply];
			break;
		case CKConnectionSentPasswordState:
			[self _receivedReplyInConnectionSentPasswordState:reply];
			break;
		case CKConnectionAwaitingCurrentDirectoryState:
			[self _receivedReplyInConnectionAwaitingCurrentDirectoryState:reply];
			break;
		case CKConnectionAwaitingDirectoryContentsState:
			[self _receivedReplyInConnectionAwaitingDirectoryContentsState:reply];
			break;
		case CKConnectionChangingDirectoryState:
			[self _receivedReplyInConnectionChangingDirectoryState:reply];
			break;
		case CKConnectionCreateDirectoryState:
			[self _receivedReplyInConnectionCreateDirectoryState:reply];
			break;
		case CKConnectionDeleteDirectoryState:
			[self _receivedReplyInConnectionDeleteDirectoryState:reply];
			break;
		case CKConnectionRenameFromState:		
			[self _receivedReplyInConnectionRenameFromState:reply];
			break;
		case CKConnectionAwaitingRenameState:  
			[self _receivedReplyInConnectionAwaitingRenameState:reply];
			break;
		case CKConnectionDeleteFileState:
			[self _receivedReplyInConnectionDeleteFileState:reply];
			break;
		case CKConnectionDownloadingFileState:
			[self _receivedReplyInConnectionDownloadingFileState:reply];
			break;
		case CKConnectionUploadingFileState:
			[self _receivedReplyInConnectionUploadingFileState:reply];
			break;
		case CKConnectionSentOffsetState:
			[self _receivedReplyInConnectionSentOffsetState:reply];
			break;
		case CKConnectionSentFeatureRequestState:
			[self _receivedReplyInConnectionSentFeatureRequestState:reply];
			break;
		case CKConnectionSentQuitState:		
			[self _receivedReplyInConnectionSentQuitState:reply];
			break;
		case CKConnectionSettingPermissionsState:
			[self _receivedReplyInConnectionSettingPermissionsState:reply];
			break;
		case CKConnectionSentSizeState:		
			[self _receivedReplyInConnectionSentSizeState:reply];
			break;
		case CKConnectionSentDisconnectState: 
			[self _receivedReplyInConnectionSentDisconnectState:reply];
			break;
		case FTPSettingPassiveState:
			[self _receivedReplyInFTPSettingPassiveState:reply];
			break;
		case FTPSettingEPSVState:
			[self _receivedReplyInFTPSettingEPSVState:reply];
			break;
		case FTPSettingActiveState:
			[self _receivedReplyInFTPSettingActiveState:reply];
			break;
		case FTPSettingEPRTState:
			[self _receivedReplyInFTPSettingEPRTState:reply];
			break;
		case FTPAwaitingRemoteSystemTypeState:
			[self _receivedReplyInFTPAwaitingRemoteSystemTypeState:reply];
			break;
		case FTPChangeDirectoryListingStyle:
			[self _receivedReplyInFTPChangeDirectoryListingStyleState:reply];
			break;
		default:
			break;		
	}
}

- (void)_receivedReplyInConnectionNotConnectedState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
	{
		case 120: //Service Ready
		{
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                      LocalizedStringInConnectionKitBundle(@"FTP Service Unavailable", @"FTP no service"), NSLocalizedDescriptionKey,
                                      [reply description], NSLocalizedFailureReasonErrorKey,
                                      [[[self request] URL] host], ConnectionHostKey, nil];
            NSError *error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
            [[self client] connectionDidConnectToHost:[[[self request] URL] host] error:error];
			
			[self setState:CKConnectionNotConnectedState]; //don't really need.
			break;
		}
		case 220: //Service Ready For New User
		{
			if (_ftpFlags.loggedIn != NO)
				break;
			if ([[[reply textLines] objectAtIndex:0] rangeOfString:@"Microsoft FTP Service"].location != NSNotFound)
			{
				_ftpFlags.isMicrosoft = YES;
			}
			else
			{
				_ftpFlags.isMicrosoft = NO;
			}
			
			
            [self authenticateConnection];
			break;
		}
		default:
			break;
	}
}

- (void)_receivedReplyInConnectionSentUsernameState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
	{
		case 230: //User logged in, proceed
		{
			if (![[_currentAuthenticationCredential user] isEqualToString:@"anonymous"]) break;

            _ftpFlags.loggedIn = YES;
						
			// Queue up the commands we want to insert in the queue before notifying client we're connected
			
			// We get the current directory -- and we're notified of a change directory ... so we'll know what directory
			// we are starting in.
			CKConnectionCommand *getCurrentDirectoryCommand = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"PWD"]
																				awaitState:CKConnectionIdleState
																				 sentState:CKConnectionAwaitingCurrentDirectoryState
																				 dependant:nil
																				  userInfo:nil];
			[self pushCommandOnCommandQueue:getCurrentDirectoryCommand];
			CKConnectionCommand *getRemoteSystemTypeCommand = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"SYST"]
																				awaitState:CKConnectionIdleState
																				 sentState:FTPAwaitingRemoteSystemTypeState
																				 dependant:nil
																				  userInfo:nil];
			[self pushCommandOnCommandQueue:getRemoteSystemTypeCommand];
			
            // What features does the server support?
            CKConnectionCommand *featuresCommand = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"FEAT"]
                                                                     awaitState:CKConnectionIdleState
                                                                      sentState:CKConnectionSentFeatureRequestState
                                                                      dependant:nil
                                                                       userInfo:nil];
			[self pushCommandOnCommandQueue:featuresCommand];
						
			
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

- (void)_receivedReplyInConnectionSentAccountState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
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

- (void)_receivedReplyInConnectionSentPasswordState:(CKFTPReply *)reply
{
	switch([reply replyCode])
	{
		case 230: //User logged in, proceed
		{
			_ftpFlags.loggedIn = YES;
			
			// We get the current directory -- and we're notified of a change directory ... so we'll know what directory
			// we are starting in.
			CKConnectionCommand *getCurrentDirectoryCommand = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"PWD"]
																				awaitState:CKConnectionIdleState
																				 sentState:CKConnectionAwaitingCurrentDirectoryState
																				 dependant:nil
																				  userInfo:nil];
			[self pushCommandOnCommandQueue:getCurrentDirectoryCommand];
			CKConnectionCommand *getRemoteSystemTypeCommand = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"SYST"]
																				awaitState:CKConnectionIdleState
																				 sentState:FTPAwaitingRemoteSystemTypeState
																				 dependant:nil
																				  userInfo:nil];
			[self pushCommandOnCommandQueue:getRemoteSystemTypeCommand];
			
			// What features does the server support?
            CKConnectionCommand *featuresCommand = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"FEAT"]
                                                                     awaitState:CKConnectionIdleState
                                                                      sentState:CKConnectionSentFeatureRequestState
                                                                      dependant:nil
                                                                       userInfo:nil];
            [self pushCommandOnCommandQueue:featuresCommand];
						
			
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

- (void)_receivedReplyInConnectionAwaitingCurrentDirectoryState:(CKFTPReply *)reply
{
	NSError *error = nil;
	NSString *path = [reply quotedString];
	if (!path)
		path = (NSString *)[[self lastCommand] userInfo];
	
	BOOL connectionJustOpened = NO;
	switch ([reply replyCode])
	{
		case 257: //Path Created
		{
			[self setCurrentPath:path];			
			if (_rootPath == nil) 
			{
				connectionJustOpened = YES;
				_rootPath = [path copy];
			}
			break;
		}
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[[self request] URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];			
			break;
		}
		case 550: //Requested action not taken, file not found. //Permission Denied
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied"), NSLocalizedDescriptionKey, path, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
		}
		default:
			break;
	}
	
	if (connectionJustOpened)
		[[self client] connectionDidOpenAtPath:path error:error];
	else
		[[self client] connectionDidChangeToDirectory:path error:error];
}

- (void)_receivedReplyInConnectionAwaitingDirectoryContentsState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
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

- (void)_receivedReplyInConnectionChangingDirectoryState:(CKFTPReply *)reply
{
	NSError *error = nil;

	NSString *directoryPath = (NSString *)[[self lastCommand] userInfo];
	
	switch ([reply replyCode])
	{
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[[self request] URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];			
			break;
		}			
		case 500: //Syntax error, command unrecognized.
		case 501: //Syntax error in parameters or arguments.
		case 502: //Command not implemented
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"Failed to change to directory", @"Bad ftp command"), NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey, directoryPath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:ConnectionErrorChangingDirectory userInfo:userInfo];
			break;			
		}		
		case 550: //Requested action not taken, file not found. //Permission Denied
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied"), NSLocalizedDescriptionKey, directoryPath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;
		}
		default:
			break;
	}
	
	//If we couldn't change to the directory, unroll and dependant commands.
	if (error)
		[self dequeueDependentsOfCommand:[self lastCommand]];
	
    [[self client] connectionDidChangeToDirectory:directoryPath error:error];
	[self setState:CKConnectionIdleState];
}

- (void)_receivedReplyInConnectionCreateDirectoryState:(CKFTPReply *)reply
{
	NSError *error = nil;
	
	NSString *directoryPath = (NSString *)[[self lastCommand] userInfo];
	
	switch ([reply replyCode])
	{
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[[self request] URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];			
			break;
		}			
		case 521: //Supported Address Families
		{
			if (!_isRecursiveUploading)
			{
				NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Create directory operation failed", @"FTP Create directory error");
				NSString *path = nil;
				NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
				if ([[reply description] rangeOfString:@"exists"].location != NSNotFound) 
				{
					[userInfo setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
					if ([[reply description] rangeOfString:@":"].location != NSNotFound)
					{
						path = [[reply description] substringWithRange:NSMakeRange(4, [[reply description] rangeOfString:@":"].location - 4)];
						[userInfo setObject:path forKey:ConnectionDirectoryExistsFilenameKey];
						[userInfo setObject:path forKey:NSFilePathErrorKey];
					}
				}
				[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
				[userInfo setObject:[reply description] forKey:NSLocalizedFailureReasonErrorKey];
				error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
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
			[userInfo setObject:directoryPath forKey:ConnectionDirectoryExistsFilenameKey];
			[userInfo setObject:directoryPath forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:[reply description] forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;			
		}			
		default:
			break;
	}
	
    [[self client] connectionDidCreateDirectory:directoryPath error:error];
	[self setState:CKConnectionIdleState];
}

- (void)_receivedReplyInConnectionDeleteDirectoryState:(CKFTPReply *)reply
{
	NSError *error = nil;
	switch ([reply replyCode])
	{
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[[self request] URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];			
			break;
		}			
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			NSString *localizedDescription = [NSString stringWithFormat:@"%@: %@", LocalizedStringInConnectionKitBundle(@"Failed to delete directory", @"couldn't delete the file"), [[self currentDirectory] stringByAppendingPathComponent:[self currentDeletion]]];
			[userInfo setObject:[self currentDeletion] forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:[reply description] forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;			
		}									
		default:
			break;
	}
	
	// Uses same _fileDeletes queue, hope that's safe to do.  (Any chance one could get ahead of another?)
	[[self client] connectionDidDeleteDirectory:[_fileDeletes objectAtIndex:0] error:error];
    
	[self dequeueDeletion];
	[self setState:CKConnectionIdleState];
}

- (void)_receivedReplyInConnectionRenameFromState:(CKFTPReply *)reply
{
	NSError *error = nil;
	switch ([reply replyCode])
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
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[[self request] URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];			
			break;
		}			
		default:
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(@"No such file", @"No such file"), NSLocalizedDescriptionKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;
		}
	}
	
	//Unlike other methods, we check that error isn't nil here, because we're sending the finished delegate message on error, whereas the "successful" codes send downloadProgressed messages.
	if (error)
	{
		[[self client] connectionDidRename:[_fileRenames objectAtIndex:0] to:[_fileRenames objectAtIndex:1] error:error];
        
		[_fileRenames removeObjectAtIndex:0];
		[_fileRenames removeObjectAtIndex:0];							 
		[self setState:CKConnectionIdleState];				
	}
}

- (void)_receivedReplyInConnectionAwaitingRenameState:(CKFTPReply *)reply
{
	NSString *fromPath = [_fileRenames objectAtIndex:0];
	NSString *toPath = [_fileRenames objectAtIndex:1];
	
	NSError *error = nil;
	switch ([reply replyCode])
	{
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[[self request] URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];			
			break;
		}			
		case 450: //Requested file action not taken. File unavailable. //File in Use
		{
			NSString *remotePath = [[self currentUpload] remotePath];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File in Use", @"FTP file in use"), NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  remotePath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;
		}			
		case 550: //Requested action not taken, file not found. //Permission Denied
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"Permission Denied", @"Permission Denied"), NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  fromPath, @"fromPath", 
									  toPath, @"toPath", nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;			
		}
		default:
			break;
	}
	
	[[self client] connectionDidRename:fromPath to:toPath error:error];
    
	[_fileRenames removeObjectAtIndex:0];
	[_fileRenames removeObjectAtIndex:0];							 
	[self setState:CKConnectionIdleState];	
}

- (void)_receivedReplyInConnectionDeleteFileState:(CKFTPReply *)reply
{
	NSError *error = nil;
	switch ([reply replyCode])
	{
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[[self request] URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];			
			break;
		}			
		case 450: //Requested file action not taken. File unavailable.
		{
			NSString *remotePath = [[self currentUpload] remotePath];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File in Use", @"FTP file in use"), NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  remotePath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;
		}			
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			NSString *localizedDescription = [NSString stringWithFormat:@"%@: %@", LocalizedStringInConnectionKitBundle(@"Failed to delete file", @"couldn't delete the file"), [[self currentDirectory] stringByAppendingPathComponent:[self currentDeletion]]];
			[userInfo setObject:[self currentDeletion] forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:[reply description] forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;			
		}						
		default:
			break;
	}
	

    [[self client] connectionDidDeleteFile:[self currentDeletion] error:error];
    
	[self dequeueDeletion];	
	[self setState:CKConnectionIdleState];
}

- (void)_receivedReplyInConnectionDownloadingFileState:(CKFTPReply *)reply
{
	NSError *error = nil;
	switch ([reply replyCode])
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
					[fm removeItemAtPath:[download localPath] error:nil];
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
				
				[[self client] download:[download remotePath] didReceiveDataOfLength:len];
				
				if ([download delegateRespondsToTransferTransferredData])
				{
					[[download delegate] transfer:[download userInfo] transferredDataOfLength:len];
				}
				int percent = 100.0 * (float)_transferSent / ((float)_transferSize * 1.0);

                [[self client] download:[download remotePath] didProgressToPercent:[NSNumber numberWithInt:percent]];
				
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
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[[self request] URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];			
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
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  remotePath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;
		}	
		case 451: //Requested acion aborted, local error in processing
		{
			NSString *remotePath = [[self currentDownload] remotePath];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"Action Aborted. Local Error", @"FTP Abort"), NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  remotePath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;
		}
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			CKInternalTransferRecord *download = [self currentDownload];
			NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"File %@ does not exist on server", @"FTP file download error"), [download remotePath]];
			[userInfo setObject:[download remotePath] forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:[reply description] forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
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
		
		[[self client] downloadDidFinish:[download remotePath] error:error];
        
		if ([download delegateRespondsToTransferDidFinish])
			[[download delegate] transferDidFinish:[download userInfo] error:error];
		
		[download release];
		
		//Dequeue any dependent commands.
		[self dequeueDependentsOfCommand:[self lastCommand]];
		[self setState:CKConnectionIdleState];
	}
}

- (void)_receivedReplyInConnectionUploadingFileState:(CKFTPReply *)reply
{
	NSError *error = nil;
	switch ([reply replyCode])
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
				_transferSize = [[[[NSFileManager defaultManager] attributesOfItemAtPath:file error:nil] objectForKey:NSFileSize] longLongValue] - offset;
				
				[_readHandle seekToFileOffset:offset]; 
				NSData *chunk = [_readHandle readDataOfLength:kStreamChunkSize];
				[chunk getBytes:&bytes];
				chunkLength = [chunk length];		// actual length of bytes read
			}
			
			//kick start the transfer
			[_dataSendStream write:bytes maxLength:chunkLength];
			_transferSent += chunkLength;
			_transferCursor += chunkLength;
			
			[[self client] upload:remoteFile didSendDataOfLength:chunkLength];
			
			if ([d delegateRespondsToTransferTransferredData])
			{
				[[d delegate] transfer:[d userInfo] transferredDataOfLength:chunkLength];
			}
			
			int percent = (float)_transferSent / ((float)_transferSize * 1.0);
			if (percent > _transferLastPercent)
			{
				[[self client] upload:remoteFile didProgressToPercent:[NSNumber numberWithInt:percent]];	// send message if we have increased %
				
				if ([d delegateRespondsToTransferProgressedTo])
				{
					[[d delegate] transfer:[d userInfo] progressedTo:[NSNumber numberWithInt:percent]];
				}
			}
			_transferLastPercent = percent;			
			break;
		}
            
        case 125:   // Windows NT servers seem to use 125 unlike the rest of the world...
		case 150:   // File status okay, about to open data connection.
		{
			CKInternalTransferRecord *d = [self currentUpload];
			NSString *file = [d localPath];	// actual path to file, or destination name if from data
			NSString *remoteFile = [d remotePath];
			NSData *data = [d data];
			
			if (nil == file && nil == data)
			{
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
										  LocalizedStringInConnectionKitBundle(@"Failed to upload file. Local file does not exist.", @"Failed to upload file. Local file does not exist."), NSLocalizedDescriptionKey,
										  [reply description], NSLocalizedFailureReasonErrorKey,
										  file, NSFilePathErrorKey, nil];
				error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
				break;
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
					if (![[NSFileManager defaultManager] fileExistsAtPath:file])
					{
						[self closeDataConnection];
						NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
												  LocalizedStringInConnectionKitBundle(@"Failed to upload file. Local file does not exist.", @"Failed to upload file. Local file does not exist."), NSLocalizedDescriptionKey,
												  [reply description], NSLocalizedFailureReasonErrorKey,
												  file, NSFilePathErrorKey, nil];
						error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
						break;
					}
					[self setReadHandle:[NSFileHandle fileHandleForReadingAtPath:file]];
					NSAssert((nil != _readHandle), @"_readHandle is nil!");
					NSData *chunk = [_readHandle readDataOfLength:kStreamChunkSize];
					bytes = (uint8_t *)[chunk bytes];
					chunkLength = [chunk length];		// actual length of bytes read
                    
                    NSNumber *size = [[[NSFileManager defaultManager] attributesOfItemAtPath:file error:nil] objectForKey:NSFileSize];
                    _transferSize = [size unsignedLongLongValue];
				}
				
				//kick start the transfer
				[_dataSendStream write:bytes maxLength:chunkLength];
				_transferSent += chunkLength;
				_transferCursor += chunkLength;
				
				
				if ([d delegateRespondsToTransferTransferredData])
				{
					[[d delegate] transfer:[d userInfo] transferredDataOfLength:chunkLength];
				}
				
				[[self client] upload:remoteFile didSendDataOfLength:chunkLength];
				
				int percent = (float)_transferSent / ((float)_transferSize * 1.0);
				if (percent > _transferLastPercent)
				{
					[[self client] upload:remoteFile didProgressToPercent:[NSNumber numberWithInt:percent]];	// send message if we have increased %
					
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
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[[self request] URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];			
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
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  remotePath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;
		}
		case 452: //Requested action not taken. Insufficient storage space in system.
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"No Storage Space Available", @"FTP Error"), NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[self currentUpload] remotePath], NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			[self sendCommand:[CKFTPCommand commandWithCode:@"ABOR"]];			
			break;
		}
		case 532: //Need account for storing files.
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"You need an Account to Upload Files", @"FTP Error"), NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[[self request] URL] host], ConnectionHostKey,
									  [[self currentUpload] remotePath], NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;
		}
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			CKInternalTransferRecord *upload = [self currentUpload];
			NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"You do not have access to write file %@", @"FTP file upload error"), [upload remotePath]];
			[userInfo setValue:[upload remotePath] forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:[reply description] forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;			
		}
		case 552: //Requested file action aborted, storage allocation exceeded.
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"Cannot Upload File. Storage quota on server exceeded", @"FTP upload error"), NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[self currentUpload] remotePath], NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
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
		
		[[self client] uploadDidFinish:[upload remotePath] error:error];
        
		if ([upload delegateRespondsToTransferDidFinish])
			[[upload delegate] transferDidFinish:[upload userInfo] error:error];
		
		[upload release];
		
		[self dequeueDependentsOfCommand:[self lastCommand]];
		[self setState:CKConnectionIdleState];
	}
}

- (void)_receivedReplyInConnectionSentOffsetState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
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

- (void)_receivedReplyInConnectionSentFeatureRequestState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
	{
		case 211: //System status, or system help ready
		{
			//parse features
			if ([[reply description] rangeOfString:@"SIZE"].location != NSNotFound)
				_ftpFlags.hasSize = YES;
			else
				_ftpFlags.hasSize = NO;
			
            if ([[reply description] rangeOfString:@"ADAT"].location != NSNotFound)
				_ftpFlags.hasADAT = YES;
			else
				_ftpFlags.hasADAT = NO;
			
            if ([[reply description] rangeOfString:@"AUTH"].location != NSNotFound)
				_ftpFlags.hasAUTH = YES;
			else
				_ftpFlags.hasAUTH = NO;
			
            if ([[reply description] rangeOfString:@"CCC"].location != NSNotFound)
				_ftpFlags.hasCCC = YES;
			else
				_ftpFlags.hasCCC = NO;
			
            if ([[reply description] rangeOfString:@"CONF"].location != NSNotFound)
				_ftpFlags.hasCONF = YES;
			else
				_ftpFlags.hasCONF = NO;
			
            if ([[reply description] rangeOfString:@"ENC"].location != NSNotFound)
				_ftpFlags.hasENC = YES;
			else
				_ftpFlags.hasENC = NO;
			
            if ([[reply description] rangeOfString:@"MIC"].location != NSNotFound)
				_ftpFlags.hasMIC = YES;
			else
				_ftpFlags.hasMIC = NO;
			
            if ([[reply description] rangeOfString:@"PBSZ"].location != NSNotFound)
				_ftpFlags.hasPBSZ = YES;
			else
				_ftpFlags.hasPBSZ = NO;
			
            if ([[reply description] rangeOfString:@"PROT"].location != NSNotFound)
				_ftpFlags.hasPROT = YES;
			else
				_ftpFlags.hasPROT = NO;
			
            if ([[reply description] rangeOfString:@"MDTM"].location != NSNotFound)
				_ftpFlags.hasMDTM = YES;
			else
				_ftpFlags.hasMDTM = NO;
			
            if ([[reply description] rangeOfString:@"SITE"].location != NSNotFound)
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
        case 550: //Operation not permitted
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

- (void)_receivedReplyInConnectionSentQuitState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
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

- (void)_receivedReplyInConnectionSettingPermissionsState:(CKFTPReply *)reply
{
	NSError *error = nil;
	switch ([reply replyCode])
	{
		case 421:
		{
			NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"FTP service not available; Remote server has closed connection", @"FTP service timed out");
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[[self request] URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];			
			break;
		}			
		case 450: //Requested file action not taken. File unavailable.
		{
			NSString *remotePath = [[self currentUpload] remotePath];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"File in Use", @"FTP file in use"), NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  remotePath, NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;
		}		
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Failed to set permissions for path %@", @"FTP Upload error"), [self currentPermissionChange]];
			[userInfo setObject:[self currentPermissionChange] forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:[reply description] forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;			
		}				
		case 553: //Requested action not taken. Illegal file name.
		{
			NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Failed to set permissions for path %@", @"FTP Upload error"), [self currentPermissionChange]];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  localizedDescription, NSLocalizedDescriptionKey,
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [self currentPermissionChange], NSFilePathErrorKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
			break;
		}
		default:
			break;
	}

    [[self client] connectionDidSetPermissionsForFile:[_filePermissions objectAtIndex:0] error:error];
    
	[self dequeuePermissionChange];
	[self setState:CKConnectionIdleState];
}

- (void)_receivedReplyInConnectionSentSizeState:(CKFTPReply *)reply
{
	NSError *error = nil;
	switch ([reply replyCode])
	{
		case 213: //File status
		{
			CKInternalTransferRecord *download = [self currentDownload];
			if ([[reply description] rangeOfString:@"("].location != NSNotFound)
			{
				NSScanner *sizeScanner = [NSScanner scannerWithString:[reply description]];
				NSCharacterSet *bracketSet = [NSCharacterSet characterSetWithCharactersInString:@"()"];
				[sizeScanner scanUpToCharactersFromSet:bracketSet intoString:nil];
				if ( [sizeScanner scanLocation] < [[reply description] length] )
				{
					[sizeScanner setScanLocation:[sizeScanner scanLocation] + 1];
					sscanf([[[reply description] substringFromIndex:[sizeScanner scanLocation]] cStringUsingEncoding:NSUTF8StringEncoding],
						   "%llu", &_transferSize);
				}
			}
			else
			{
				// some servers return 213 4937728
				NSScanner *sizeScanner = [NSScanner scannerWithString:[reply description]];
				NSCharacterSet *sp = [NSCharacterSet whitespaceCharacterSet];
				[sizeScanner scanUpToCharactersFromSet:sp intoString:nil];
				if ( [sizeScanner scanLocation] < [[reply description] length] )
				{
					[sizeScanner setScanLocation:[sizeScanner scanLocation] + 1];
					sscanf([[[reply description] substringFromIndex:[sizeScanner scanLocation]] cStringUsingEncoding:NSUTF8StringEncoding],
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
									  [reply description], NSLocalizedFailureReasonErrorKey,
									  [[[self request] URL] host], ConnectionHostKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];			
			break;
		}			
		case 550: //Requested action not taken, file not found.
		{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			CKInternalTransferRecord *download = [self currentDownload];
			NSString *localizedDescription = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"File %@ does not exist on server", @"FTP file download error"), [download remotePath]];
			[userInfo setObject:[download remotePath] forKey:NSFilePathErrorKey];
			[userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:[reply description] forKey:NSLocalizedFailureReasonErrorKey];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:[reply replyCode] userInfo:userInfo];
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
		
		[[self client] downloadDidFinish:[download remotePath] error:error];
        
		if ([download delegateRespondsToTransferDidFinish])
			[[download delegate] transferDidFinish:[download userInfo] error:error];
		
		[download release];
		
		//Dequeue any dependent commands
		[self dequeueDependentsOfCommand:[self lastCommand]];
		[self setState:CKConnectionIdleState];
	}
}

- (void)_receivedReplyInConnectionSentDisconnectState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
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

- (void)_receivedReplyInFTPSettingPassiveState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
	{
		case 227: //Entering Passive Mode
		{
			int i[6];
			int j;
			unsigned char n[6];
			char *buf = (char *)[[reply description] UTF8String];
			char *start = strchr(buf,'(');
			if ( !start )
				start = strchr(buf,'=');
			if ( !start ||
				( sscanf(start, "(%d,%d,%d,%d,%d,%d)",&i[0], &i[1], &i[2], &i[3], &i[4], &i[5]) != 6 &&
				 sscanf(start, "=%d,%d,%d,%d,%d,%d", &i[0], &i[1], &i[2], &i[3], &i[4], &i[5]) != 6 ) )
			{
				_ftpFlags.canUsePASV = NO;
				
                NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"All data connection modes have been exhausted. Check with the server administrator.", @"FTP no data stream types available");
                NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                          localizedDescription, NSLocalizedDescriptionKey,
                                          [reply description], NSLocalizedFailureReasonErrorKey,
                                          [[[self request] URL] host], ConnectionHostKey, nil];
                NSError *err = [NSError errorWithDomain:CKFTPErrorDomain code:FTPErrorNoDataModes userInfo:userInfo];
                [[self client] connectionDidReceiveError:err];
                
				_state = CKConnectionSentQuitState;
				[self sendCommand:[CKFTPCommand commandWithCode:@"QUIT"]];
			}
			for (j=0; j<6; j++)
			{
				n[j] = (unsigned char) (i[j] & 0xff);
			}
			int port = i[4] << 8 | i[5];
			//port = ntohs(i[5] << 8 | i[4]);
			NSString *hostString = [NSString stringWithFormat:@"%d.%d.%d.%d", i[0], i[1], i[2], i[3]];
						
			NSHost *host = [CKCacheableHost hostWithAddress:hostString];
			[host setValue:[NSArray arrayWithObject:[[[self request] URL] host]] forKey:@"names"]; // KVC hack
			
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

- (void)_receivedReplyInFTPSettingEPSVState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
	{
		case 229: //Extended Passive Mode Entered
		{
			//get the port number
			int port = 0;
			char *cmd = (char *)[[reply description] UTF8String];
			char *start = strchr(cmd,'|');
			if ( !start || sscanf(start, "|||%d|", &port) != 1)
			{
				_ftpFlags.canUseEPSV = NO;
				CKConnectionCommand *cmd = [self nextAvailableDataConnectionType];
				_state = [cmd sentState];
				[self sendCommand:[cmd command]];
			}
			NSHost *host = [CKCacheableHost hostWithName:[[[self request] URL] host]];
			[host setValue:[NSArray arrayWithObject:[[[self request] URL] host]] forKey:@"names"]; // KVC hack
			
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

- (void)_receivedReplyInFTPSettingActiveState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
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

- (void)_receivedReplyInFTPSettingEPRTState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
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

- (void)_receivedReplyInFTPAwaitingRemoteSystemTypeState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
	{
		case 215: //NAME system type
		{
			if ([[[reply description] lowercaseString] rangeOfString:@"windows"].location != NSNotFound)
			{
				_ftpFlags.isMicrosoft = YES;
				[self setState:FTPChangeDirectoryListingStyle];
				[self sendCommand:[CKFTPCommand commandWithCode:@"SITE" argumentField:@"DIRSTYLE"]];
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

- (void)_receivedReplyInFTPChangeDirectoryListingStyleState:(CKFTPReply *)reply
{
	switch ([reply replyCode])
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
	[self sendCommand:[CKFTPCommand commandWithCode:@"QUIT"]];
}

- (void)threadedCancelTransfer
{
	[self sendCommand:[CKFTPCommand commandWithCode:@"ABOR"]];
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
	else if ((aStream == _receiveStream || aStream == _sendStream) && eventCode == NSStreamEventEndEncountered && (GET_STATE == CKConnectionDownloadingFileState || GET_STATE == CKConnectionUploadingFileState))
	{
		//In the event we're downloading or uploading, and the control stream ends, we *do not* close down. This would mess up our internal state and prevent us from completeing the transfer. Instead, we set a flag which we look for when the dataStreams close down.
		_isWaitingForTransferToFinishToCloseStreams = YES;
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
	if (!_currentReply)
		_currentReply = [[CKStreamedFTPReply alloc] init];
    
    NSData *excessData = nil;
    [_currentReply appendData:data nextData:&excessData];
	
    while ([_currentReply isComplete])
    {
        [self parseCommand:_currentReply];
        [_currentReply release];
		
        if (excessData)
        {
            _currentReply = [[CKStreamedFTPReply alloc] init];
            [_currentReply appendData:excessData nextData:&excessData];
        }
        else
        {
            _currentReply = nil;
        }
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
				 If this is uncommented, it'll cause massive CPU load when we're doing transfers.
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
							[fm removeItemAtPath:[download localPath] error:nil];
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
								
                                [[self client] download:file didProgressToPercent:[NSNumber numberWithInt:percent]];	// send message if we have increased %
								
								_transferLastPercent = percent;
							}
						}
						
						[[self client] download:file didReceiveDataOfLength:len];
						
						
						if ([download delegateRespondsToTransferTransferredData])
						{
							[[download delegate] transfer:[download userInfo] transferredDataOfLength:len];
						}
					}
				}
				else
				{
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
			[[self client] appendFormat:@"Receive Stream Error: %@" toTranscript:CKTranscriptSent, [_receiveStream streamError]];
			
			

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
					
					[[self client] uploadDidFinish:[upload remotePath] error:[_receiveStream streamError]];
                    
					if ([upload delegateRespondsToTransferDidFinish])
						[[upload delegate] transferDidFinish:[upload userInfo] error:[_receiveStream streamError]];
					
					[upload release];

					//Dequeue any dependent commands.
					[self dequeueDependentsOfCommand:[self lastCommand]];
					[self setState:CKConnectionIdleState];
				}
				if (GET_STATE == CKConnectionDownloadingFileState)
				{
					CKInternalTransferRecord *download = [[self currentDownload] retain];
					[self dequeueDownload];
					
					[[self client] downloadDidFinish:[download remotePath] error:[_receiveStream streamError]];
                    
					if ([download delegateRespondsToTransferDidFinish])
						[[download delegate] transferDidFinish:[download userInfo] error:[_receiveStream streamError]];
					
					[download release];
					
					//Dequeue any dependent commands.
					[self dequeueDependentsOfCommand:[self lastCommand]];
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
			[[self client] appendFormat:@"Send Stream Error: %@" toTranscript:CKTranscriptSent, [_receiveStream streamError]];
			
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
			else
            {
				KTLog(CKStreamDomain, KTLogDebug, @"NSStreamEventErrorOccurred: %@", [_dataReceiveStream streamError]);
				[[self client] connectionDidReceiveError:[_dataReceiveStream streamError]];
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
						[[self client] upload:remoteFile didSendDataOfLength:chunkLength];
                    
					//}
					int percent = 100.0 * (float)_transferSent / ((float)_transferSize * 1.0);
					if (percent > _transferLastPercent)
					{
						[[self client] upload:remoteFile didProgressToPercent:[NSNumber numberWithInt:percent]];	// send message if we have increased %
						
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
		
		[[self client] downloadDidFinish:[download remotePath] error:nil];
		
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
		
		[[self client] uploadDidFinish:[upload remotePath] error:nil];
		
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
		[[self client] appendLine:results toTranscript:CKTranscriptData];

		NSArray *contents = [self parseLines:results];
		NSError *error = nil;
		if (contents)
		{
			KTLog(CKParsingDomain, KTLogDebug, @"Contents of Directory %@:\n%@", _currentPath, [contents shortDescription]);

			[self cacheDirectory:_currentPath withContents:contents];
		}
		else
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(@"Directory Parsing Error", @"Error parsing directory listing"), NSLocalizedDescriptionKey, nil];
			error = [NSError errorWithDomain:CKFTPErrorDomain code:0 userInfo:userInfo];
		}
		
		[[self client] connectionDidReceiveContents:contents ofDirectory:_currentPath error:error];
		
		[results release];
		[_dataBuffer setLength:0];

		if (_ftpFlags.received226)
		{
			[self setState:CKConnectionIdleState];
		}
	}
	
	if (_isWaitingForTransferToFinishToCloseStreams)
	{
		_isWaitingForTransferToFinishToCloseStreams = NO;
		[self closeStreams];
		[self setState:CKConnectionNotConnectedState];
		[[self client] connectionDidDisconnectFromHost:[[[self request] URL] host]];
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

	[[self client] appendLine:LocalizedStringInConnectionKitBundle(@"Data Stream Timed Out", @"Failed to open a data stream connection")
                   toTranscript:CKTranscriptData];
	
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
	//Reset all flags.
	memset(&_ftpFlags, NO, sizeof(_ftpFlags));
	
	//Set the flags that are yes by default
	_ftpFlags.canUseActive = YES;
	_ftpFlags.canUseEPRT = YES;
	_ftpFlags.canUsePASV = YES;
	_ftpFlags.canUseEPSV = YES;
	_ftpFlags.hasSize = YES;	
	
	[_lastAuthenticationChallenge release];
	_lastAuthenticationChallenge = nil;
	
	[_currentAuthenticationCredential release];
	_currentAuthenticationCredential = nil;
	
	[_currentPath release];
	_currentPath = nil;
	
	[_topQueuedChangeDirectoryPath release];
	_topQueuedChangeDirectoryPath = nil;
	
	[_rootPath release];
	_rootPath = nil;
	
	[super closeStreams];
}

#pragma mark -
#pragma mark Operations

- (void)changeToDirectory:(NSString *)dirPath
{
	[self _changeToDirectory:dirPath forDependentCommand:nil];
}

/*!
	@abstract Returns the commands necessary to safely change to the given directory.
	@param dirPath The directory to change to.
	@param dependentCommand A command that is dependent on the successful change of working directory to dirPath.
	@result An array of CKConnectionCommands, in the order that they should be added to the queue.
	@discussion If necessary, the change to dirPath as the current working directory will be split into several CWD commands. This is to faciliate success directory changes on (the many) FTP servers that do not support long paths. In this method, path changes are split into, at most, 100 character chunks.
 */
- (NSArray *)_commandsToChangeToDirectory:(NSString *)dirPath forDependentCommand:(CKConnectionCommand *)dependentCommand
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"dirPath is nil!");
	
	NSMutableArray *commandsInQueueOrder = [NSMutableArray array]; //The CKConnectionCommands in the order they should be queued.
	
		//If we're already going to be in the parent directory of dirPath when our command gets executed, just change to the last path component.
	NSString *parentDirectoryPath = [dirPath stringByDeletingLastPathComponent];
	if ([self topQueuedChangeDirectoryPath] && [[self topQueuedChangeDirectoryPath] isEqualToString:parentDirectoryPath])
	{
		CKConnectionCommand *pwd = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"PWD"]
													 awaitState:CKConnectionIdleState 
													  sentState:CKConnectionAwaitingCurrentDirectoryState
													  dependant:nil
													   userInfo:nil];
		CKConnectionCommand *cwd = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"CWD" argumentField:[dirPath lastPathComponent]]
													 awaitState:CKConnectionIdleState 
													  sentState:CKConnectionChangingDirectoryState
                                                     dependants:[NSArray arrayWithObjects:pwd, dependentCommand, nil]
													   userInfo:dirPath];		
		[commandsInQueueOrder addObject:cwd];
		[commandsInQueueOrder addObject:pwd];
		return (NSArray *)commandsInQueueOrder;
	}
	
	//We can't just move by one directory level. Quite unfortunately, because some FTP servers have limits on the length of paths that can be sent, we should split the CWDs into roughly 100 character chunks.
	
	NSString *thisCWDChunkPath = [NSString string]; /* This change-working-directory chunk's path */
	NSArray *pathComponents = [dirPath pathComponents]; /* The path components of dirPath to enumerate */
	NSEnumerator *pathComponentsEnumerator = [pathComponents objectEnumerator]; /* The enumerator for the path components of dirPath */
	NSString *pathComponent; /*The enumerative path component of dirPath */
	NSString *basePath = [NSString string];
	while ((pathComponent = [pathComponentsEnumerator nextObject]))
	{
		//Is appending this path component going to push us over our 100 character max?
		if (([thisCWDChunkPath length] + [pathComponent length]) >= 100)
		{
			CKConnectionCommand *pwd = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"PWD"]
														 awaitState:CKConnectionIdleState 
														  sentState:CKConnectionAwaitingCurrentDirectoryState
														  dependant:nil
														   userInfo:nil];
			CKConnectionCommand *cwd = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"CWD" argumentField:thisCWDChunkPath]
														 awaitState:CKConnectionIdleState 
														  sentState:CKConnectionChangingDirectoryState
                                                         dependants:[NSArray arrayWithObjects:pwd, dependentCommand, nil]
														   userInfo:[basePath stringByAppendingPathComponent:thisCWDChunkPath]];
			
			[commandsInQueueOrder addObject:cwd];
			[commandsInQueueOrder addObject:pwd];
			
			basePath = [basePath stringByAppendingPathComponent:thisCWDChunkPath];
			thisCWDChunkPath = [NSString string];
		}
		
		thisCWDChunkPath = [thisCWDChunkPath stringByAppendingPathComponent:pathComponent];
	}
	
	//Did we end up with leftover components?
	if ([thisCWDChunkPath length] > 0)
	{
		CKConnectionCommand *pwd = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"PWD"]
													 awaitState:CKConnectionIdleState 
													  sentState:CKConnectionAwaitingCurrentDirectoryState
													  dependant:nil
													   userInfo:nil];
		CKConnectionCommand *cwd = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"CWD" argumentField:thisCWDChunkPath]
													 awaitState:CKConnectionIdleState 
													  sentState:CKConnectionChangingDirectoryState
                                                     dependants:[NSArray arrayWithObjects:pwd, dependentCommand, nil]
													   userInfo:[basePath stringByAppendingPathComponent:thisCWDChunkPath]];
		
		[commandsInQueueOrder addObject:cwd];
		[commandsInQueueOrder addObject:pwd];
	}
		
	return (NSArray *)commandsInQueueOrder;
}

- (void)_changeToDirectory:(NSString *)dirPath forDependentCommand:(CKConnectionCommand *)dependentCommand
{
	NSArray *commandsInQueueOrder = [self _commandsToChangeToDirectory:dirPath forDependentCommand:dependentCommand];
	
	NSEnumerator *commandsEnumerator = [commandsInQueueOrder objectEnumerator];
	CKConnectionCommand *command;
	while ((command = [commandsEnumerator nextObject]))
		[self queueCommand:command];
	
	[self setTopQueuedChangeDirectoryPath:dirPath];
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
	CKConnectionCommand *mkdir = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"MKD" argumentField:[dirPath lastPathComponent]]
												 awaitState:CKConnectionIdleState 
												  sentState:CKConnectionCreateDirectoryState
												  dependant:nil
												   userInfo:dirPath];
	
	// Move to the parent path. This prevents issues with path being too long in the command.
	NSString *parentDirectory = [dirPath stringByDeletingLastPathComponent];
	if ([parentDirectory length] > 0 && ![[self topQueuedChangeDirectoryPath] isEqualToString:parentDirectory])
		[self _changeToDirectory:parentDirectory forDependentCommand:mkdir];
	
	[self queueCommand:mkdir];
}

- (void)threadedSetPermissions:(NSNumber *)perms forFile:(NSString *)path
{
	unsigned long permissions = [perms unsignedLongValue];
    
    NSString *arguments = [NSString stringWithFormat:@"CHMOD %lo %@", permissions, path];
	CKFTPCommand *cmd = [[CKFTPCommand alloc] initWithCommandCode:@"SITE" argumentField:arguments];
    
	CKConnectionCommand *com = [CKConnectionCommand command:cmd
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionSettingPermissionsState
											  dependant:nil
											   userInfo:path];
	[self pushCommandOnHistoryQueue:com];
	[self sendCommand:cmd];
    [cmd release];
    
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
												 userInfo:dirPath];
	CKConnectionCommand *mkdir = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"MKD" argumentField:[dirPath lastPathComponent]]											   awaitState:CKConnectionIdleState 
                                                    sentState:CKConnectionCreateDirectoryState
                                                    dependant:chmod
                                                     userInfo:dirPath];
	
	//Move to the parent path. This prevents issues with path being too long in the command.
	NSString *parentDirectory = [dirPath stringByDeletingLastPathComponent];
	if ([parentDirectory length] > 0 && ![[self topQueuedChangeDirectoryPath] isEqualToString:parentDirectory])
		[self _changeToDirectory:parentDirectory forDependentCommand:mkdir];
	
	[self queuePermissionChange:dirPath];
	[self queueCommand:mkdir];
	[self queueCommand:chmod];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"no file/path specified");
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(threadedSetPermissions:forFile:)
													  target:self
												   arguments:[NSArray arrayWithObjects: [NSNumber numberWithUnsignedLong:permissions], [path lastPathComponent], nil]];
	[self queuePermissionChange:path];
	CKConnectionCommand *chmod = [CKConnectionCommand command:inv
											   awaitState:CKConnectionIdleState 
												sentState:CKConnectionSettingPermissionsState
												dependant:nil
												 userInfo:path];
	
	//Move to the parent path. This prevents issues with path being too long in the command.
	NSString *parentDirectory = [path stringByDeletingLastPathComponent];
	if ([parentDirectory length] > 0 && ![[self topQueuedChangeDirectoryPath] isEqualToString:parentDirectory])
		[self _changeToDirectory:parentDirectory forDependentCommand:chmod];
	
	[self queueCommand:chmod];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"dirPath is nil!");
	
	[self queueDeletion:dirPath];
	CKConnectionCommand *rm = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"RMD" argumentField:[dirPath lastPathComponent]]
											awaitState:CKConnectionIdleState 
											 sentState:CKConnectionDeleteDirectoryState
											 dependant:nil
											  userInfo:dirPath];
	
	//Move to the parent path. This prevents issues with path being too long in the command.
	NSString *parentDirectory = [dirPath stringByDeletingLastPathComponent];
	if ([parentDirectory length] > 0 && ![[self topQueuedChangeDirectoryPath] isEqualToString:parentDirectory])
		[self _changeToDirectory:parentDirectory forDependentCommand:rm];
	
	[self queueCommand:rm];
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSAssert(fromPath && ![fromPath isEqualToString:@""], @"fromPath is nil!");
    NSAssert(toPath && ![toPath isEqualToString:@""], @"toPath is nil!");
			
	[self queueRename:fromPath];
	[self queueRename:toPath];
	CKConnectionCommand *to = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"RNTO" argumentField:toPath]
											awaitState:CKConnectionRenameToState 
											 sentState:CKConnectionAwaitingRenameState
											 dependant:nil
											  userInfo:toPath];
	CKConnectionCommand *from = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"RNFR" argumentField:fromPath]
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
	CKConnectionCommand *del = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"DELE" argumentField:[path lastPathComponent]]
                                                 awaitState:CKConnectionIdleState 
                                                  sentState:CKConnectionDeleteFileState
                                                  dependant:nil
                                                   userInfo:path];
	
	//Move to the parent path. This prevents issues with path being too long in the command.
	NSString *parentDirectory = [path stringByDeletingLastPathComponent];
	if ([parentDirectory length] > 0 && ![[self topQueuedChangeDirectoryPath] isEqualToString:parentDirectory])
		[self _changeToDirectory:parentDirectory forDependentCommand:del];
	
	[self queueCommand:del];
}

/*!	Upload file to the given directory
*/
- (CKTransferRecord *)_uploadFile:(NSString *)localPath 
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
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                      LocalizedStringInConnectionKitBundle(@"Local File already exists", @"FTP download error"), NSLocalizedDescriptionKey,
                                      remotePath, NSFilePathErrorKey, nil];
            NSError *error = [NSError errorWithDomain:CKFTPErrorDomain code:FTPDownloadFileExists userInfo:userInfo];
            [[self client] connectionDidReceiveError:error];
			
			return nil;
		}
	}
		
	[self startBulkCommands];
		
	/*
	 TYPE I
	 SIZE file
	 PASV/EPSV/ERPT/PORT
	 RETR file
	 TYPE A
	 */	
	
	CKTransferRecord *record = [CKTransferRecord downloadRecordForConnection:self
															sourceRemotePath:remotePath
														destinationLocalPath:localPath
																		size:0 
																 isDirectory:NO];
	
	CKInternalTransferRecord *download = [CKInternalTransferRecord recordWithLocal:localPath
																			  data:nil
																			offset:0
																			remote:remotePath
																		  delegate:delegate ? delegate : record
																		  userInfo:record];
	[self queueDownload:download];
	
	CKConnectionCommand *retr = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"RETR" argumentField:[remotePath lastPathComponent]]
                                                  awaitState:CKConnectionIdleState 
                                                   sentState:CKConnectionDownloadingFileState
                                                   dependant:nil
                                                    userInfo:download];
    
	CKConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	[dataCmd addDependantCommand:retr];
	
	CKConnectionCommand *size = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"SIZE" argumentField: [remotePath lastPathComponent]]
											  awaitState:CKConnectionIdleState 
											   sentState:CKConnectionSentSizeState
											   dependant:dataCmd
												userInfo:nil];
	
	if (!_ftpFlags.setBinaryTransferMode)
	{
		CKConnectionCommand *bin = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"TYPE" argumentField:@"I"]
											 awaitState:CKConnectionIdleState
											  sentState:FTPModeChangeState
											  dependant:nil
											   userInfo:nil];
		[self queueCommand:bin];
		_ftpFlags.setBinaryTransferMode = YES;
	}
	
	//Move to the parent path. This prevents issues with path being too long in the command.
	NSString *parentDirectory = [remotePath stringByDeletingLastPathComponent];
	if ([parentDirectory length] > 0 && ![[self topQueuedChangeDirectoryPath] isEqualToString:parentDirectory])
		[self _changeToDirectory:parentDirectory forDependentCommand:retr];		
	
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
	CKTransferRecord *record = [CKTransferRecord downloadRecordForConnection:self
															sourceRemotePath:remotePath
														destinationLocalPath:localPath
																		size:0 
																 isDirectory:NO];
	CKInternalTransferRecord *download = [CKInternalTransferRecord recordWithLocal:localPath
																			  data:nil
																			offset:offset
																			remote:remotePath
																		  delegate:delegate ? delegate : record
																		  userInfo:record];
	[self queueDownload:download];
	
	CKConnectionCommand *retr = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"RETR" argumentField: remotePath]
											  awaitState:CKConnectionIdleState 
											   sentState:CKConnectionDownloadingFileState
											   dependant:nil
												userInfo:download];
	
	CKConnectionCommand *rest = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"REST" argumentField:[off description]]
											  awaitState:CKConnectionIdleState 
											   sentState:CKConnectionSentOffsetState
											   dependant:retr
												userInfo:nil];
	
	CKConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	[dataCmd addDependantCommand:rest];
	
	CKConnectionCommand *size = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"SIZE" argumentField: remotePath]
											  awaitState:CKConnectionIdleState 
											   sentState:CKConnectionSentSizeState
											   dependant:dataCmd
												userInfo:nil];
	
	if (!_ftpFlags.setBinaryTransferMode) {
		CKConnectionCommand *bin = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"TYPE" argumentField:@"I"]
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
	CKConnectionCommand *ls = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"LIST" argumentField:@"-a"] 
											awaitState:CKConnectionIdleState 
											 sentState:CKConnectionAwaitingDirectoryContentsState 
											 dependant:nil 
											  userInfo:[self currentDirectory]];
	CKConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	[dataCmd addDependantCommand:ls];
	
	[self queueCommand:dataCmd];
	[self queueCommand:ls];
}

- (void)threadedContentsOfDirectory:(NSString *)dirPath
{
	NSString *currentDir = [NSString stringWithString:[self currentDirectory]];
	
	[self startBulkCommands];
	// If we're being asked for the contents of a directory other than the directory we're in now, we'll need to change back to the current directory once we've listed dirPath
	if (![currentDir isEqualToString:dirPath])
	{
		NSArray *changeBackCommands = [self _commandsToChangeToDirectory:currentDir forDependentCommand:nil];
		//We enumerate in reverse because we're adding to the front of the queue, and changeBackCommands is in add-to-queue order
		NSEnumerator *commandsEnumerator = [changeBackCommands reverseObjectEnumerator];
		CKConnectionCommand *command;
		while ((command = [commandsEnumerator nextObject]))
			[_commandQueue insertObject:command atIndex:0];
	}

	CKConnectionCommand *dataCmd = [self pushDataConnectionOnCommandQueue];
	CKConnectionCommand *ls = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"LIST" argumentField:@"-a"]
											awaitState:CKConnectionIdleState 
											 sentState:CKConnectionAwaitingDirectoryContentsState 
											 dependant:nil 
											  userInfo:dirPath];
	[dataCmd addDependantCommand:ls];
	
	[_commandQueue insertObject:ls atIndex:0];
	[_commandQueue insertObject:dataCmd atIndex:0];
	
	NSArray *changeToNewDirCommands = [self _commandsToChangeToDirectory:dirPath forDependentCommand:ls];
	//We enumerate in reverse because we're adding to the front of the queue, and changeToNewDirCommands is in add-to-queue order
	NSEnumerator *commandsEnumerator = [changeToNewDirCommands reverseObjectEnumerator];
	CKConnectionCommand *command;
	while ((command = [commandsEnumerator nextObject]))
		[_commandQueue insertObject:command atIndex:0];

	[self endBulkCommands];
	
	[self setState:CKConnectionIdleState];
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
	
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(threadedContentsOfDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObject:dirPath]];
	CKConnectionCommand *ls = [CKConnectionCommand command:inv
											awaitState:CKConnectionIdleState 
											 sentState:CKConnectionAwaitingDirectoryContentsState 
											 dependant:nil 
											  userInfo:dirPath];
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
	NSString *preferredDataConnectionType = [[self request] FTPDataConnectionType];
		
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
        NSString *localizedDescription = LocalizedStringInConnectionKitBundle(@"Exhausted all connection types to server. Please contact server administrator", @"FTP no data streams available");
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  localizedDescription, NSLocalizedDescriptionKey,
                                  [[[self request] URL] host], ConnectionHostKey, nil];
        NSError *err = [NSError errorWithDomain:CKFTPErrorDomain code:FTPErrorNoDataModes userInfo:userInfo];
        [[self client] connectionDidReceiveError:err];
	}
	
	CKConnectionCommand *command;
	if (connectionTypeString)
	{
		command = [CKConnectionCommand command:[CKFTPCommand commandWithCode:connectionTypeString]
								  awaitState:CKConnectionIdleState
								   sentState:sendState
								   dependant:nil
									userInfo:nil];
	}
	else
	{
		command = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"QUIT"]
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
		
	CFStreamCreatePairWithSocket(kCFAllocatorDefault, connectedFrom, &read, &write);
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
	if (!_activeSocket)
	{
		return NO;
	}
	
	CFSocketSetSocketFlags(_activeSocket,kCFSocketCloseOnInvalidate);
	int on = 1;
	setsockopt(CFSocketGetNative(_activeSocket), SOL_SOCKET, SO_REUSEPORT, &on, sizeof(on));
	setsockopt(CFSocketGetNative(_activeSocket), SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
	
	//add to the runloop
	CFRunLoopSourceRef src = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _activeSocket, 0);
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
		
		return NO;
	}
	return YES;
}

- (CKFTPCommand *)setupEPRTConnection
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
	
    return [CKFTPCommand commandWithCode:@"EPRT" argumentField:[NSString stringWithFormat:
                                                                @"|1|%@|%u|",
                                                                [[NSHost currentHost] ipv4Address],
                                                                port]];
}

- (CKFTPCommand *)setupActiveConnection
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
		return [CKFTPCommand commandWithCode:@"PASV"];
	}
	div_t portDiv = div(_lastActivePort, 256);
	NSString *ip = [[[[NSHost currentHost] ipv4Address] componentsSeparatedByString:@"."] componentsJoinedByString:@","];
	return [CKFTPCommand commandWithCode:@"PORT" argumentField:[NSString stringWithFormat:
                                                                @"%@,%d,%d",
                                                                ip,
                                                                portDiv.quot,
                                                                portDiv.rem]];
}

- (NSArray *)parseLines:(NSString *)line
{
	return [NSFileManager directoryListingItemsFromListing:line];
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
	
	CKConnectionCommand *store = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"STOR" argumentField:[remotePath lastPathComponent]]
                                                   awaitState:CKConnectionIdleState
                                                    sentState:CKConnectionUploadingFileState
                                                    dependant:nil
                                                     userInfo:nil];
	CKConnectionCommand *rest = nil;
	if (offset != 0) {
		rest = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"REST" argumentField:[NSString stringWithFormat:@"%qu", offset]]
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
		NSDictionary *attribs = [[NSFileManager defaultManager] attributesOfItemAtPath:localPath error:nil];
		uploadSize = [[attribs objectForKey:NSFileSize] unsignedLongLongValue];
	}
	
	CKTransferRecord *record = [CKTransferRecord uploadRecordForConnection:self 
														   sourceLocalPath:localPath
													 destinationRemotePath:remotePath
																	  size:uploadSize 
															   isDirectory:NO];
	
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
		CKConnectionCommand *bin = [CKConnectionCommand command:[CKFTPCommand commandWithCode:@"TYPE" argumentField:@"I"]
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

	//Move to the parent path. This prevents issues with path being too long in the command.
	NSString *parentDirectory = [remotePath stringByDeletingLastPathComponent];
	if ([parentDirectory length] > 0 && ![[self topQueuedChangeDirectoryPath] isEqualToString:parentDirectory])
		[self _changeToDirectory:parentDirectory forDependentCommand:store];
	
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
	[self sendCommand:[CKFTPCommand commandWithCode:@"NOOP"]];
}

#pragma mark -
#pragma mark Accessors

- (NSFileHandle *)writeHandle
{
    return _writeHandle; 
}

- (void)setWriteHandle:(NSFileHandle *)aWriteHandle
{
	if (aWriteHandle == _writeHandle)
		return;
	
	[_writeHandle closeFile];
	[_writeHandle release];
	_writeHandle = [aWriteHandle retain];
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

- (NSString *)topQueuedChangeDirectoryPath
{
	return _topQueuedChangeDirectoryPath;
}

- (void)setTopQueuedChangeDirectoryPath:(NSString *)path
{
	if (_topQueuedChangeDirectoryPath == path)
		return;
	[_topQueuedChangeDirectoryPath release];
	_topQueuedChangeDirectoryPath = [path copy];
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
    
    NSURLProtectionSpace *protectionSpace = [[CKURLProtectionSpace alloc] initWithHost:[[[self request] URL] host]
                                                                                  port:[self port]
                                                                              protocol:[[[self request] URL] scheme]
                                                                                 realm:nil
                                                                  authenticationMethod:NSURLAuthenticationMethodDefault];
    
    _lastAuthenticationChallenge = [[NSURLAuthenticationChallenge alloc]
                                    initWithProtectionSpace:protectionSpace
                                    proposedCredential:nil
                                    previousFailureCount:previousFailureCount
                                    failureResponse:nil
                                    error:nil
                                    sender:self];
    
    [protectionSpace release];
    
    // As the delegate to handle the challenge
    [[self client] connectionDidReceiveAuthenticationChallenge:_lastAuthenticationChallenge];    
}

/*  FTP's horrible design requires us to send the username or account name and then wait for a response
 *  before sending the password. This method performs the second half of the operation and sends the
 *  password that our delegate previously supplied.
 */
- (void)sendPassword
{
    NSString *password = [[[self currentAuthenticationCredential] password] copy];
    NSAssert(password, @"Somehow a password-less credential has entered the FTP system");
    
    // Dispose of the credentials once the password has been sent
    [self setCurrentAuthenticationCredential:nil];
       
    [self sendCommand:[CKFTPCommand commandWithCode:@"PASS" argumentField:password]];
    [self setState:CKConnectionSentPasswordState];
    [password release];
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
	[self disconnect];
	[[self client] connectionDidCancelAuthenticationChallenge:challenge];
}

/*  Start login
 */
- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSParameterAssert(credential);
    NSParameterAssert([[credential user] length] > 0);
    
    if (challenge == _lastAuthenticationChallenge)
    {
        // Store the credentials ready for the password request
        [self setCurrentAuthenticationCredential:credential];
        
        if ([credential password])
        {
            // Send the username
            [self setState:CKConnectionSentUsernameState];
            [self sendCommand:[CKFTPCommand commandWithCode:@"USER" argumentField:[credential user]]];
        }
        else
        {
			[self continueWithoutCredentialForAuthenticationChallenge:challenge];
        }
    }
}

@end


#pragma mark -


@implementation CKConnectionRequest (CKFTPConnection)

static NSString *CKFTPDataConnectionTypeKey = @"CKFTPDataConnectionType";

- (NSString *)FTPDataConnectionType { return [self propertyForKey:CKFTPDataConnectionTypeKey]; }

@end

@implementation CKMutableConnectionRequest (CKFTPConnection)

- (void)setFTPDataConnectionType:(NSString *)type
{
    if (type)
        [self setProperty:type forKey:CKFTPDataConnectionTypeKey];
    else
        [self removePropertyForKey:CKFTPDataConnectionTypeKey];
}

@end

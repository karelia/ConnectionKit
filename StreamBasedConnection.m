/*
 Copyright (c) 2005, Greg Hulands <ghulands@mac.com>
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

#import "StreamBasedConnection.h"

#import "ConnectionThreadManager.h"
#import "InterThreadMessaging.h"
#import "NSData+Connection.h"
#import "NSObject+Connection.h"
#import "NSFileManager+Connection.h"
#import "RunLoopForwarder.h"
#import "CKCacheableHost.h"
#import "CKTransferRecord.h"
#import "AbstractConnectionProtocol.h"
#import "CKInternalTransferRecord.h"
#import "NSString+Connection.h"

#import <sys/types.h> 
#import <sys/socket.h> 
#import <netinet/in.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <poll.h>
#import <netdb.h>
#import <sys/types.h>
#import <sys/sysctl.h>

#import <Security/Security.h>
#import <CoreServices/CoreServices.h>

const unsigned int kStreamChunkSize = 2048;
const NSTimeInterval kStreamTimeOutValue = 10.0; // 10 second timeout

NSString *StreamBasedErrorDomain = @"StreamBasedErrorDomain";
NSString *SSLErrorDomain = @"SSLErrorDomain";

OSStatus SSLReadFunction(SSLConnectionRef connection, void *data, size_t *dataLength);
OSStatus SSLWriteFunction(SSLConnectionRef connection, const void *data, size_t *dataLength);

@interface StreamBasedConnection (Private)
- (void)checkQueue;
- (void)processFileCheckingQueue;
- (void)recalcUploadSpeedWithBytesSent:(unsigned)length;
- (void)recalcDownloadSpeedWithBytesSent:(unsigned)length;

// SSL Stuff
- (void)initializeSSL;
- (void)negotiateSSLWithData:(NSData *)data;
- (int)handshakeWithInputData:(NSMutableData *)inputData
				   outputData:(NSMutableData *)outputData;

@end

@implementation StreamBasedConnection

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
			 error:(NSError **)error
{
	if (self = [super initWithHost:host port:port username:username password:password error:error])
	{
		_sendBufferLock = [[NSLock alloc] init];
		_sendBuffer = [[NSMutableData data] retain];
		_createdThread = [NSThread currentThread];
		myStreamFlags.sendOpen = NO;
		myStreamFlags.readOpen = NO;
		
		myStreamFlags.wantsSSL = NO;
		myStreamFlags.isNegotiatingSSL = NO;
		myStreamFlags.sslOn = NO;
		myStreamFlags.allowsBadCerts = NO;
		myStreamFlags.initializedSSL = NO;
		myStreamFlags.isDeleting = NO;
		
		_fileCheckLock = [[NSLock alloc] init];
		
		_recursiveS3RenamesQueue = [[NSMutableArray alloc] init];
		_recursivelyRenamedDirectoriesToDelete = [[NSMutableArray alloc] init];
		_recursiveS3RenameLock = [[NSLock alloc] init];
		
		_recursiveDeletionsQueue = [[NSMutableArray alloc] init];
		_emptyDirectoriesToDelete = [[NSMutableArray alloc] init];
		_filesToDelete = [[NSMutableArray alloc] init];
		_recursiveDeletionLock = [[NSLock alloc] init];
		
		_recursiveDownloadQueue = [[NSMutableArray alloc] init];
		_recursiveDownloadLock = [[NSLock alloc] init];
		
		mySSLEncryptedSendBuffer = [[NSMutableData data] retain];
		
		[NSThread prepareForConnectionInterThreadMessages];
	}
	
	return self;
}

- (void)dealloc
{
	if (mySSLContext) SSLDisposeContext(mySSLContext);
	if (mySSLIdentity) CFRelease(mySSLIdentity);
	[mySSLSendBuffer release];
	[mySSLRecevieBuffer release];
	[mySSLRawReadBuffer release];
	[mySSLEncryptedSendBuffer release];
	
	// NSStream has a problem in that if you release and set the delegate to nil in the same runloop pass it will still send messages
	// autoreleasing will stop the crashes.
	[_sendStream setDelegate:nil];
	[_receiveStream setDelegate:nil];
	[_sendStream autorelease];
	[_receiveStream autorelease];
	
	[_sendBufferLock release];
	[_sendBuffer release];
	[_fileCheckingConnection setDelegate:nil];
	[_fileCheckingConnection forceDisconnect];
	[_fileCheckingConnection release];
	[_fileCheckLock release];
	[_fileCheckInFlight release];
	
	[_recursiveS3RenameLock release];
	[_recursiveS3RenamesQueue release];
	[_recursivelyRenamedDirectoriesToDelete release];
	
	[_recursiveDeletionsQueue release];
	[_recursiveDeletionConnection setDelegate:nil];
	[_recursiveDeletionConnection forceDisconnect];
	[_recursiveDeletionConnection release];
	[_emptyDirectoriesToDelete release];
	[_filesToDelete release];
	[_recursiveDeletionLock release];
	
	[_recursiveDownloadConnection setDelegate:nil];
	[_recursiveDownloadConnection forceDisconnect];
	[_recursiveDownloadConnection release];
	[_recursiveDownloadQueue release];
	[_recursiveDownloadLock release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Accessors

- (void)setSendStream:(NSStream *)stream
{
	if (stream != _sendStream) {
		[_sendStream autorelease];
		_sendStream = [stream retain];
	}
}

- (void)setReceiveStream:(NSStream *)stream
{
	if (stream != _receiveStream) {
		[_receiveStream autorelease];
		_receiveStream = [stream retain];
	}
}

- (NSStream *)sendStream
{
	return _sendStream;
}

- (NSStream *)receiveStream
{
	return _receiveStream;
}

- (BOOL)sendStreamOpen
{
	return myStreamFlags.sendOpen;
}

- (BOOL)receiveStreamOpen
{
	return myStreamFlags.readOpen;
}

- (void)sendStreamDidOpen {}
- (void)sendStreamDidClose {}
- (void)receiveStreamDidOpen {}
- (void)receiveStreamDidClose {}

- (NSString *)remoteIPAddress
{
	struct sockaddr sock;
	socklen_t len = sizeof(sock);
	
	if (getsockname([self socket], &sock, &len) >= 0) {
		char *addr = inet_ntoa(((struct sockaddr_in *)&sock)->sin_addr);
		return [NSString stringWithCString:addr];
	}
	return nil;
}

- (unsigned)localPort
{
	struct sockaddr sock;
	socklen_t len = sizeof(sock);
	
	if (getsockname([self socket], &sock, &len) >= 0) {
		return ntohs(((struct sockaddr_in *)&sock)->sin_port);
	}
	
	return 0;
}

- (CFSocketNativeHandle)socket
{
	CFSocketNativeHandle native;
	CFDataRef nativeProp = CFReadStreamCopyProperty ((CFReadStreamRef)_receiveStream, kCFStreamPropertySocketNativeHandle);
	if (nativeProp == NULL)
	{
		return -1;
	}
	CFDataGetBytes (nativeProp, CFRangeMake(0, CFDataGetLength(nativeProp)), (UInt8 *)&native);
	CFRelease (nativeProp);
	return native;
}

#pragma mark -
#pragma mark Threading Support

- (void)runloopForwarder:(RunLoopForwarder *)rlw returnedValue:(void *)value 
{
	//by default we do nothing, subclasses are implementation specific based on their current state
}

- (void)scheduleStreamsOnRunLoop
{
	[_receiveStream setDelegate:self];
	[_sendStream setDelegate:self];
	
	[_receiveStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_sendStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	
	[_receiveStream open];
	[_sendStream open];
}

#pragma mark -
#pragma mark Queue Support

- (void)endBulkCommands
{
	[super endBulkCommands];
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] checkQueue];
}

- (void)sendCommand:(id)command
{
	// Subclasses handle this
}

#pragma mark -
#pragma mark AbstractConnection Overrides

- (void)setDelegate:(id)delegate
{
	[super setDelegate:delegate];
	// Also tell the forwarder to use this delegate.
	[_forwarder setDelegate:delegate];	// note that its delegate it not retained.
}

- (BOOL)openStreamsToPort:(unsigned)port
{
	NSHost *host = [CKCacheableHost hostWithName:_connectionHost];
	if(!host){
		KTLog(TransportDomain, KTLogError, @"Cannot find the host: %@", _connectionHost);
		
        if (_flags.didConnect) {
			NSError *error = [NSError errorWithDomain:ConnectionErrorDomain 
												 code:EHOSTUNREACH
											 userInfo:
				[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(@"Host Unavailable", @"Couldn't open the port to the host"), NSLocalizedDescriptionKey,
					_connectionHost, ConnectionHostKey, nil]];
			[_forwarder connection:self didConnectToHost:_connectionHost error:error];
		}
		return NO;
	}
	/* If the host has multiple names it can screw up the order in the list of name */
	if ([[host names] count] > 1) {
		[host setValue:[NSArray arrayWithObject:_connectionHost] forKey:@"names"]; // KVC hack
	}
	
	if ([[host addresses] count] > 1) {
		NSEnumerator *e = [[host addresses] objectEnumerator];
		NSString *cur;
		
		while (cur = [e nextObject])
		{
			if ([cur rangeOfString:@"."].location != NSNotFound)
			{
				[host setValue:[NSArray arrayWithObject:cur] forKey:@"addresses"];
			}
		}
	}
	[self closeStreams];		// make sure streams are closed before opening/allocating new ones
	
	KTLog(TransportDomain, KTLogDebug, @"Opening streams to host: %@", host);
	
	int sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	
	KTLog(TransportDomain, KTLogDebug, @"Socket: %d", port);
	
	// Set TCP Keep Alive
	int opt = 1;
	if (setsockopt(sock, SOL_SOCKET, SO_KEEPALIVE, &opt, sizeof(opt)))
	{
		NSLog(@"Failed to set socket keep alive setting");
	}
	
	struct sockaddr_in addr;
	bzero((char *) &addr, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	addr.sin_addr.s_addr = inet_addr([[host address] UTF8String]);
	
	KTLog(TransportDomain, KTLogDebug, @"Connecting to %@:%d", [host address], port);
	
	if (connect(sock, (struct sockaddr *) &addr, sizeof(addr)) == 0)
	{
		CFStreamCreatePairWithSocket(kCFAllocatorDefault, 
									 sock, 
									 (CFReadStreamRef *)(&_receiveStream),
									 (CFWriteStreamRef *)(&_sendStream));		// "Ownership follows the Create Rule."

		// CFStreamCreatePairWithSocket does not close the socket by default
		CFReadStreamSetProperty((CFReadStreamRef)_receiveStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
		CFWriteStreamSetProperty((CFWriteStreamRef)_sendStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
	}
	else
	{
		KTLog(TransportDomain, KTLogDebug, @"connect() failed");
	}
	
	if(!_receiveStream || !_sendStream){
		KTLog(TransportDomain, KTLogError, @"Cannot create a stream to the host: %@", _connectionHost);
		
		if (_flags.error)
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"Stream Unavailable", @"Error creating stream"), NSLocalizedDescriptionKey,
									  _connectionHost, ConnectionHostKey, nil];
			NSError *error = [NSError errorWithDomain:ConnectionErrorDomain code:EHOSTUNREACH userInfo:userInfo];
			[_forwarder connection:self didReceiveError:error];
		}
		return NO;
	}
	return YES;
}

- (void)threadedConnect
{
	myStreamFlags.reportedError = NO;
	[self scheduleStreamsOnRunLoop];
	[super threadedConnect];
}

- (void)connect
{
	_isForceDisconnecting = NO;
	
	int connectionPort = [_connectionPort intValue];
	if (0 == connectionPort)
	{
		connectionPort = 21;	// standard FTP control port
	}
	
	if ([self openStreamsToPort:connectionPort])
	{
		// only call super if we have successfully opened the ports and put them on the runloop
		[super connect];
	}
}

/*!	Disconnect from host.  Called by foreground thread.
*/
- (void)disconnect
{
	ConnectionCommand *con = [ConnectionCommand command:[NSInvocation invocationWithSelector:@selector(threadedDisconnect) target:self arguments:[NSArray array]]
											 awaitState:ConnectionIdleState
											  sentState:ConnectionSentDisconnectState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:con];
	[_fileCheckingConnection disconnect];
}

- (void)threadedDisconnect
{
	[self setState:ConnectionNotConnectedState];
	[self closeStreams];
	[_fileCheckingConnection disconnect];
	[_recursiveDeletionConnection disconnect];
	[_recursiveDownloadConnection disconnect];
	
	[super threadedDisconnect];
}

- (void)threadedForceDisconnect
{
	[self setState:ConnectionNotConnectedState];
	_isForceDisconnecting = YES;
	[self closeStreams];

	[super threadedForceDisconnect];
}

- (void)forceDisconnect
{
	[self setState:ConnectionNotConnectedState];
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedForceDisconnect];
	[_fileCheckingConnection forceDisconnect];
	[_recursiveDeletionConnection forceDisconnect];
	[_recursiveDownloadConnection forceDisconnect];
}

- (void) cleanupConnection
{
	[_fileCheckingConnection cleanupConnection];
	[_recursiveDeletionConnection cleanupConnection];
	[_recursiveDownloadConnection cleanupConnection];
}

- (BOOL)isBusy
{
	return ([super isBusy] || [_recursiveDownloadConnection isBusy] || [_recursiveDeletionConnection isBusy] || [_fileCheckingConnection isBusy]); 
}

#pragma mark -
#pragma mark Stream Delegate Methods

- (void)recalcUploadSpeedWithBytesSent:(unsigned)length
{
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	NSTimeInterval diff = now - _lastChunkSent;
	_uploadSpeed = length / diff;
	_lastChunkSent = now;
}

- (void)recalcDownloadSpeedWithBytesSent:(unsigned)length
{
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	NSTimeInterval diff = now - _lastChunkReceived;
	_downloadSpeed = length / diff;
	_lastChunkReceived = now;
}

- (void)closeStreams
{
	[_receiveStream close];
	[_sendStream close];
	[_receiveStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_sendStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_receiveStream setDelegate:nil];
	[_sendStream setDelegate:nil];
	[_receiveStream release];
	[_sendStream release];
	_receiveStream = nil;
	_sendStream = nil;
	[_sendBuffer setLength:0];
	myStreamFlags.sendOpen = NO;
	myStreamFlags.readOpen = NO;
}

- (void)processReceivedData:(NSData *)data
{
	// we do nothing. subclass has to do the work.
}

- (NSData *)availableData
{
	NSData *data = nil;
	[self availableData:&data ofLength:kStreamChunkSize];
	return data;
}

- (int)availableData:(NSData **)dataOut ofLength:(int)length
{
	if ([_receiveStream streamStatus] != NSStreamStatusOpen)
	{
		*dataOut = nil;
		return 0;
	}
	struct pollfd fds;
	fds.fd = [self socket];
	fds.events = POLLIN;
	int hasBytes = poll(&fds, 1, 10);
	
	if (hasBytes > 0)
	//if ([_receiveStream hasBytesAvailable])
	{
		uint8_t *buf = (uint8_t *)malloc(sizeof(uint8_t) * length);
		int len = [_receiveStream read:buf maxLength:length];
		NSData *data = nil;
		
		if (len >= 0)
		{
			data = [NSData dataWithBytesNoCopy:buf length:len freeWhenDone:YES];
		}
		
		*dataOut = data;
		return len;
	}
	*dataOut = nil;
	return 0;
}

- (BOOL)shouldChunkData
{
	return YES;
}

- (NSMutableData *)outputDataBuffer
{
	NSMutableData *dataBuffer = nil;
	
	if (myStreamFlags.wantsSSL)
	{
		if (!myStreamFlags.sslOn && myStreamFlags.isNegotiatingSSL)
		{
			dataBuffer = mySSLEncryptedSendBuffer;
		}
	}
	else
	{
		dataBuffer = _sendBuffer;
	}
	
	return dataBuffer;
}

- (void) sendQueuedOutput
{
	NSMutableData *dataBuffer = [self outputDataBuffer];
	
	[_sendBufferLock lock];
	unsigned chunkLength = [dataBuffer length];
	if ([self shouldChunkData])
	{
		chunkLength = MIN(kStreamChunkSize, [dataBuffer length]);
	}
	if (chunkLength > 0)
	{
		NSData *chunk = [dataBuffer subdataWithRange:NSMakeRange(0,chunkLength)];
		
		KTLog(OutputStreamDomain, KTLogDebug, @"<< %@", [chunk shortDescription]);
		uint8_t *bytes = (uint8_t *)[chunk bytes];
		[(NSOutputStream *)_sendStream write:bytes maxLength:chunkLength];
		[self recalcUploadSpeedWithBytesSent:chunkLength];
		[self stream:_sendStream sentBytesOfLength:chunkLength];
		[dataBuffer replaceBytesInRange:NSMakeRange(0,chunkLength)
							  withBytes:NULL
								 length:0];
		_lastChunkSent = [NSDate timeIntervalSinceReferenceDate];
	}
	else
	{
		// KTLog(OutputStreamDomain, KTLogDebug, @"NOTHING NEEDED TO BE SENT RIGHT NOW");
	}
	[_sendBufferLock unlock];
}	

- (unsigned)sendData:(NSData *)data // returns how many bytes it sent. If the buffer was not empty and it was appended, then it will return 0
{
	if (myStreamFlags.wantsSSL)
	{
		if (!myStreamFlags.sslOn && !myStreamFlags.isNegotiatingSSL)
		{
			//put into the normal send buffer that is not encrypted.	
			[_sendBufferLock lock];
			[_sendBuffer appendData:data];
			[_sendBufferLock unlock];
			return 0;
		}
	}
	BOOL bufferWasEmpty = NO;
	NSMutableData *dataBuffer = [self outputDataBuffer];
	
	if (!dataBuffer) 
	{
		KTLog(SSLDomain, KTLogFatal, @"No Data Buffer in sendData:");
		return 0;
	}
	
	[_sendBufferLock lock];
	bufferWasEmpty = [dataBuffer length] == 0;
	[dataBuffer appendData:data];
	[_sendBufferLock unlock];
	unsigned chunkLength = 0;
	
	if (bufferWasEmpty) {
		// prime the sending
		if (([_sendStream streamStatus] == NSStreamStatusOpen) && [_sendStream hasSpaceAvailable])
		{
			// KTLog(OutputStreamDomain, KTLogDebug, @"Buffer was empty, and there is space available, so sending this queued output");
			// It's already ready for us, go ahead and send out some data
			[self sendQueuedOutput];
		}
		else
		{
			// KTLog(OutputStreamDomain, KTLogDebug, @"Buffer was empty, but no space available, so we will WAIT for the event and not send now");
		}
	}
	else
	{
		// KTLog(OutputStreamDomain, KTLogDebug, @"Buffer was NOT empty, so we have just appended it and we'll let it get sent out when it's ready");
	}
		// wait for the stream to open
//		NSDate *start = [NSDate date];
//		while (([_sendStream streamStatus] != NSStreamStatusOpen) || ![_sendStream hasSpaceAvailable])
//		{
//			if (abs([start timeIntervalSinceNow]) > kStreamTimeOutValue)
//			{
//				[self closeStreams];
//				if (_flags.error)
//				{
//					NSError *error = [NSError errorWithDomain:StreamBasedErrorDomain
//														 code:StreamErrorTimedOut
//													 userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInConnectionKitBundle(@"Timed Out waiting for remote host.", @"time out") forKey:NSLocalizedDescriptionKey]];
//					[_forwarder connection:self didReceiveError:error];
//				}
//				return 0;
//			}
//			[NSThread sleepUntilDate:[NSDate distantPast]];
//		}

	return chunkLength;
}

- (void)handleReceiveStreamEvent:(NSStreamEvent)theEvent
{
	switch (theEvent)
	{
		case NSStreamEventHasBytesAvailable:
		{
			uint8_t *buf = (uint8_t *)malloc(sizeof(uint8_t) * kStreamChunkSize);
			int len = [_receiveStream read:buf maxLength:kStreamChunkSize];
			if (len >= 0)
			{
				NSData *data = [NSData dataWithBytesNoCopy:buf length:len freeWhenDone:NO];
				KTLog(InputStreamDomain, KTLogDebug, @"%d >> %@", len, [data shortDescription]);
				[self stream:_receiveStream readBytesOfLength:len];
				[self recalcDownloadSpeedWithBytesSent:len];
				if (myStreamFlags.wantsSSL && myStreamFlags.isNegotiatingSSL)
				{
					[self negotiateSSLWithData:data];
				}
				else
				{
					[self processReceivedData:data];
				}
			}
			
			free(buf);
			break;
		}
		case NSStreamEventOpenCompleted:
		{
			myStreamFlags.readOpen = YES;
			
			if (myStreamFlags.wantsSSL)
			{
				if (myStreamFlags.sendOpen)
				{
					myStreamFlags.isNegotiatingSSL = YES;
					[self initializeSSL];
				}
			}
			else
			{
				[self receiveStreamDidOpen];
			}
			
			KTLog(InputStreamDomain, KTLogDebug, @"Command receive stream opened");
			break;
		}
		case NSStreamEventErrorOccurred:
		{
			KTLog(InputStreamDomain, KTLogError, @"receive stream error: %@", [_receiveStream streamError]);
			
			NSError *error = nil;
			
			ConnectionState theState = GET_STATE;
			
			if (theState == ConnectionNotConnectedState) 
			{
				error = [NSError errorWithDomain:ConnectionErrorDomain
											code:ConnectionStreamError
										userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%@ %@?", LocalizedStringInConnectionKitBundle(@"Is the service running on the server", @"Stream Error before opening"), [self host]], NSLocalizedDescriptionKey, [self host], ConnectionHostKey, nil]];
			}
			else
			{
				// we want to catch the connection reset by peer error
				error = [_receiveStream streamError];
				BOOL isResetByPeerError = [[error domain] isEqualToString:NSPOSIXErrorDomain] && ([error code] == ECONNRESET || [error code] == EPIPE);
				if (isResetByPeerError)
				{
					KTLog(TransportDomain, KTLogInfo, @"Connection was reset by peer/broken pipe, attempting to reconnect.", [_receiveStream streamError]);
					error = nil;
				}

				_flags.isConnected = NO;
				if (_flags.didDisconnect)
					[_forwarder connection:self didDisconnectFromHost:[self host]];
				
				if (_flags.error && !myStreamFlags.reportedError) 
				{
					myStreamFlags.reportedError = YES;
					[_forwarder connection:self didReceiveError:error];
				}
				
				if (isResetByPeerError)
				{
					// resetup connection again
					[self closeStreams];
					[self setState:ConnectionNotConnectedState];
					// roll back to the first command in this chain of commands
					NSArray *cmds = [[self lastCommand] sequencedChain];
					NSEnumerator *e = [cmds reverseObjectEnumerator];
					ConnectionCommand *cur;
					
					while (cur = [e nextObject])
					{
						[self pushCommandOnCommandQueue:cur];
					}
					
					NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(openStreamsToPort:)
																	  target:self
																   arguments:[NSArray array]];
					int port = [[self port] intValue];
					[inv setArgument:&port atIndex:2];
					[inv performSelector:@selector(invoke) inThread:_createdThread];
					
					while (_sendStream == nil || _receiveStream == nil)
					{
						[NSThread sleepUntilDate:[NSDate distantPast]];
					}
					
					[self scheduleStreamsOnRunLoop];
					break;
				}
			}
			
			if (theState == ConnectionUploadingFileState || [self numberOfUploads] > 0) 
			{
				//We have uploads in the queue, so we need to dequeue them with the error
				while ([self numberOfUploads] > 0)
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
					ConnectionCommand *nextCommand = ([_commandQueue count] > 0) ? [_commandQueue objectAtIndex:0] : nil;
					if (nextCommand)
					{
						NSEnumerator *e = [[nextCommand dependantCommands] objectEnumerator];
						ConnectionCommand *dependent;
						while (dependent = [e nextObject])
						{
							[_commandQueue removeObject:dependent];
						}
						
						[_commandQueue removeObject:nextCommand];
					}
					[_queueLock unlock];		
				}
			}
			if (theState == ConnectionDownloadingFileState || theState == ConnectionSentSizeState || [self numberOfDownloads] > 0)
			{
				//We have downloads in the queue, so we need to dequeue them with the error
				while ([self numberOfDownloads] > 0)
				{
					CKInternalTransferRecord *download = [[self currentDownload] retain];
					[self dequeueDownload];
					
					if (_flags.downloadFinished)
						[_forwarder connection:self downloadDidFinish:[download remotePath] error:error];
					if ([download delegateRespondsToTransferDidFinish])
						[[download delegate] transferDidFinish:[download userInfo] error:error];
					
					[download release];
					
					//At this point the top of the command queue is something associated with this download. Remove it and all of its dependents.
					[_queueLock lock];
					ConnectionCommand *nextCommand = ([_commandQueue count] > 0) ? [_commandQueue objectAtIndex:0] : nil;
					if (nextCommand)
					{
						NSEnumerator *e = [[nextCommand dependantCommands] objectEnumerator];
						ConnectionCommand *dependent;
						while (dependent = [e nextObject])
						{
							[_commandQueue removeObject:dependent];
						}
						
						[_commandQueue removeObject:nextCommand];
					}
					[_queueLock unlock];
				}
			}
			
			break;
		}
		case NSStreamEventEndEncountered:
		{
			myStreamFlags.readOpen = NO;
			KTLog(InputStreamDomain, KTLogDebug, @"Command receive stream ended");
			[self closeStreams];
			[self setState:ConnectionNotConnectedState];
			if (_flags.didDisconnect) {
				[_forwarder connection:self didDisconnectFromHost:_connectionHost];
			}
			[self receiveStreamDidClose];
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

- (void)handleSendStreamEvent:(NSStreamEvent)theEvent
{
	switch (theEvent)
	{
		case NSStreamEventHasBytesAvailable:
		{
			// This can be called in here when send and receive stream are the same.
			[self handleReceiveStreamEvent:theEvent];
			break;
		}
		case NSStreamEventOpenCompleted:
		{
			myStreamFlags.sendOpen = YES;
			
			if (myStreamFlags.wantsSSL)
			{
				if (myStreamFlags.readOpen)
				{
					myStreamFlags.isNegotiatingSSL = YES;
					[self initializeSSL];
				}
			}
			else
			{
				[self sendStreamDidOpen];
			}
			
			KTLog(OutputStreamDomain, KTLogDebug, @"Command send stream opened");
			
			break;
		}
		case NSStreamEventErrorOccurred:
		{
			KTLog(OutputStreamDomain, KTLogError, @"send stream error: %@", [_receiveStream streamError]);
			
			NSError *error = nil;
			
			if (GET_STATE == ConnectionNotConnectedState) 
			{
				error = [NSError errorWithDomain:ConnectionErrorDomain
											code:ConnectionStreamError
										userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%@ %@?", LocalizedStringInConnectionKitBundle(@"Is the service running on the server", @"Stream Error before opening"), [self host]], NSLocalizedDescriptionKey, [self host], ConnectionHostKey, nil]];
			}
			else 
			{
				// we want to catch the connection reset by peer error
				error = [_sendStream streamError];
				if ([[error domain] isEqualToString:NSPOSIXErrorDomain] && ([error code] == ECONNRESET || [error code] == EPIPE))
				{
					KTLog(TransportDomain, KTLogInfo, @"Connection was reset by peer/broken pipe, attempting to reconnect.", [_sendStream streamError]);
					error = nil;
					
					// resetup connection again
					[self closeStreams];
					[self setState:ConnectionNotConnectedState];
					
					// roll back to the first command in this chain of commands
					NSArray *cmds = [[self lastCommand] sequencedChain];
					NSEnumerator *e = [cmds reverseObjectEnumerator];
					ConnectionCommand *cur;
					
					while (cur = [e nextObject])
					{
						[self pushCommandOnCommandQueue:cur];
					}
					
					NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(openStreamsToPort:)
																	  target:self
																   arguments:[NSArray array]];
					int port = [[self port] intValue];
					[inv setArgument:&port atIndex:2];
					[inv performSelector:@selector(invoke) inThread:_createdThread];
					
					while (_sendStream == nil || _receiveStream == nil)
					{
						[NSThread sleepUntilDate:[NSDate distantPast]];
					}
					
					[self scheduleStreamsOnRunLoop];
					break;
				}
			}
			
			if (_flags.error && !myStreamFlags.reportedError) 
			{
				myStreamFlags.reportedError = YES;
				[_forwarder connection:self didReceiveError:error];
			}
			break;
		}
		case NSStreamEventEndEncountered:
		{
			myStreamFlags.sendOpen = NO;
			KTLog(OutputStreamDomain, KTLogDebug, @"Command send stream ended");
			[self closeStreams];
			[self setState:ConnectionNotConnectedState];
			if (_flags.didDisconnect) {
				[_forwarder connection:self didDisconnectFromHost:_connectionHost];
			}
			[self sendStreamDidClose];
			break;
		}
		case NSStreamEventNone:
		{
			break;
		}
		case NSStreamEventHasSpaceAvailable:
		{
			// KTLog(OutputStreamDomain, KTLogDebug, @"Space available, sending any queued output");
			[self sendQueuedOutput];
			break;
		}
		default:
		{
			KTLog(OutputStreamDomain, KTLogError, @"Composite Event Code!  Need to deal with this!");
			break;
		}
	}
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)theEvent
{
	if (stream == (NSStream *)_sendStream) {
		[self handleSendStreamEvent:theEvent];
	} else if (stream == (NSStream *)_receiveStream) {
		[self handleReceiveStreamEvent:theEvent];
	} else {
		KTLog(TransportDomain, KTLogError, @"StreamBasedConnection: unknown stream (%@)", stream);
	}
}

- (void)stream:(id<OutputStream>)stream sentBytesOfLength:(unsigned)length
{
	// we do nothing - just allow subclasses to know that something was sent
}

- (void)stream:(id<InputStream>)stream readBytesOfLength:(unsigned)length
{
	// we do nothing - just allow subclasses to know that something was read
}

#pragma mark -
#pragma mark File Checking

- (void)processFileCheckingQueue
{
	if (!_fileCheckingConnection) 
	{
		_fileCheckingConnection = [self copy];
		[_fileCheckingConnection setDelegate:self];
		[_fileCheckingConnection setName:@"File Checking Connection"];
		[_fileCheckingConnection setTranscript:[self propertyForKey:@"FileCheckingTranscript"]];
		[_fileCheckingConnection connect];		
	}
	[_fileCheckLock lock];
	if (!_fileCheckInFlight && [self numberOfFileChecks] > 0)
	{
		_fileCheckInFlight = [[self currentFileCheck] copy];
		NSString *dir = [_fileCheckInFlight stringByDeletingLastPathComponent];
		if (!dir)
			NSLog(@"%@: %@", NSStringFromSelector(_cmd), _fileCheckInFlight);
		[_fileCheckingConnection changeToDirectory:dir];
		[_fileCheckingConnection directoryContents];
	}
	[_fileCheckLock unlock];
}

- (void)checkExistenceOfPath:(NSString *)path
{
	NSString *dir = [path stringByDeletingLastPathComponent];
	
	//if we pass in a relative path (such as xxx.tif), then the last path is @"", with a length of 0, so we need to add the current directory
	//according to docs, passing "/" to stringByDeletingLastPathComponent will return "/", conserving a 1 size
	//
	if (!dir || [dir length] == 0)
	{
		path = [[self currentDirectory] stringByAppendingPathComponent:path];
	}
	[_fileCheckLock lock];
	[self queueFileCheck:path];
	[_fileCheckLock unlock];
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processFileCheckingQueue];
}

#pragma mark -
#pragma mark Recursive S3 Directory Rename Support Methods
- (void)processRecursiveS3RenamingQueue
{
	if (!_recursiveS3RenameConnection)
	{
		_recursiveS3RenameConnection = [self copy];
		[_recursiveS3RenameConnection setName:@"Recursive S3 Renaming"];
		[_recursiveS3RenameConnection setDelegate:self];
		[_recursiveS3RenameConnection setTranscript:[self propertyForKey:@"RecursiveS3RenamingTranscript"]];
		[_recursiveS3RenameConnection connect];
	}
	[_recursiveS3RenameLock lock];
	if (!myStreamFlags.isRecursivelyRenamingForS3 && [_recursiveS3RenamesQueue count] > 0)
	{
		myStreamFlags.isRecursivelyRenamingForS3 = YES;
		NSDictionary *renameDictionary = [_recursiveS3RenamesQueue objectAtIndex:0];
		NSString *fromDirectoryPath = [renameDictionary objectForKey:@"FromDirectoryPath"];
		
		/*
		 Here's the plan:
		 (a) Create a new directory at the toDirectoryPath. Cache the old path for deletion later.
		 (b) Recursively list the contents of fromDirectoryPath.
		 (c) Create new directories at the appropriate paths for directories. Cache the old directory paths for deletion later.
		 (d) Rename the files.
		 (e) When we're done listing and done renaming, delete the old directory paths.
		 */
		
		_numberOfS3RenameListingsRemaining++;
		[_recursiveS3RenameConnection changeToDirectory:fromDirectoryPath];
		[_recursiveS3RenameConnection directoryContents];
	}
	[_recursiveS3RenameLock unlock];
}
- (void)recursivelyRenameS3Directory:(NSString *)fromDirectoryPath to:(NSString *)toDirectoryPath
{
	[_recursiveS3RenameLock lock];
	NSDictionary *renameDictionary = [NSDictionary dictionaryWithObjectsAndKeys:fromDirectoryPath, @"FromDirectoryPath", toDirectoryPath, @"ToDirectoryPath", nil];
	[_recursiveS3RenamesQueue addObject:renameDictionary];
	[_recursiveS3RenameLock unlock];
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processRecursiveS3RenamingQueue];
}

#pragma mark -
#pragma mark Recursive Deletion Support Methods
- (void)temporarilyTakeOverRecursiveDeletionDelegate
{
	previousWorkingDirectory = [[NSString stringWithString:[self currentDirectory]] retain];
	previousDelegate = [self delegate];
	_recursiveDeletionConnection = self;
	[_recursiveDeletionConnection setDelegate:self];
}
- (void)restoreRecursiveDeletionDelegate
{
	if (!previousDelegate)
		return;
	[self changeToDirectory:previousWorkingDirectory];
	[_recursiveDeletionConnection setDelegate:previousDelegate];
	previousDelegate = nil;
	[previousWorkingDirectory release];
	previousWorkingDirectory = nil;
	_recursiveDeletionConnection = nil;
}
- (void)processRecursiveDeletionQueue
{
	if (!_recursiveDeletionConnection)
	{
		_recursiveDeletionConnection = [self copy];
		[_recursiveDeletionConnection setName:@"recursive deletion"];
		[_recursiveDeletionConnection setDelegate:self];
		[_recursiveDeletionConnection setTranscript:[self propertyForKey:@"RecursiveDirectoryDeletionTranscript"]];
		[_recursiveDeletionConnection connect];
	}
	
	[_recursiveDeletionLock lock];
	if (!myStreamFlags.isDeleting && [_recursiveDeletionsQueue count] > 0)
	{
		_numberOfDeletionListingsRemaining++;
		myStreamFlags.isDeleting = YES;
		NSString *directoryPath = [_recursiveDeletionsQueue objectAtIndex:0];
		[_emptyDirectoriesToDelete addObject:directoryPath];

		[_recursiveDeletionConnection changeToDirectory:directoryPath];
		[_recursiveDeletionConnection directoryContents];
	}
	[_recursiveDeletionLock unlock];
}

- (void)recursivelyDeleteDirectory:(NSString *)path
{
	[_recursiveDeletionLock lock];
	[_recursiveDeletionsQueue addObject:[path stringByStandardizingPath]];
	[_recursiveDeletionLock unlock];	
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processRecursiveDeletionQueue];
}

#pragma mark -
#pragma mark Recursive Downloading Support
- (void)recursivelySendTransferDidFinishMessage:(CKTransferRecord *)record
{
	[record transferDidFinish:record error:nil];
	NSEnumerator *contentsEnumerator = [[record contents] objectEnumerator];
	CKTransferRecord *child;
	while ((child = [contentsEnumerator nextObject]))
	{
		[self recursivelySendTransferDidFinishMessage:child];
	}
}
- (void)temporarilyTakeOverRecursiveDownloadingDelegate
{
	previousWorkingDirectory = [[NSString stringWithString:[self currentDirectory]] retain];
	previousDelegate = [self delegate];
	_recursiveDownloadConnection = self;
	[_recursiveDownloadConnection setDelegate:self];
}
- (void)restoreRecursiveDownloadingDelegate
{
	if (!previousDelegate)
		return;
	[self changeToDirectory:previousWorkingDirectory];
	[_recursiveDownloadConnection setDelegate:previousDelegate];
	previousDelegate = nil;
	[previousWorkingDirectory release];
	previousWorkingDirectory = nil;
	_recursiveDownloadConnection = nil;
}
- (void)processRecursiveDownloadingQueue
{
	if (!_recursiveDownloadConnection)
	{
		_recursiveDownloadConnection = [self copy];
		[_recursiveDownloadConnection setName:@"recursive download"];
		[_recursiveDownloadConnection setDelegate:self];
		[_recursiveDownloadConnection setTranscript:[self propertyForKey:@"RecursiveDownloadTranscript"]];
	}
	if (![_recursiveDownloadConnection isConnected])
	{
		[_recursiveDownloadConnection connect];
	}
	[_recursiveDownloadLock lock];
	if (!myStreamFlags.isDownloading && [_recursiveDownloadQueue count] > 0)
	{
		myStreamFlags.isDownloading = YES;
		NSDictionary *rec = [_recursiveDownloadQueue objectAtIndex:0];
		_numberOfDownloadListingsRemaining++;
		[self setProperty:[NSNumber numberWithBool:YES] forKey:@"IsDiscoveringFilesToDownload"];
		[_recursiveDownloadConnection changeToDirectory:[rec objectForKey:@"remote"]];
		[_recursiveDownloadConnection directoryContents];
	}
	[_recursiveDownloadLock unlock];
}

- (CKTransferRecord *)recursivelyDownload:(NSString *)remotePath
									   to:(NSString *)localPath
								overwrite:(BOOL)flag
{
	CKTransferRecord *rec = [CKTransferRecord rootRecordWithPath:remotePath];
	
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	
	[d setObject:rec forKey:@"record"];
	[d setObject:remotePath forKey:@"remote"];
	[d setObject:[localPath stringByAppendingPathComponent:[remotePath lastPathComponent]] forKey:@"local"];
	[d setObject:[NSNumber numberWithBool:NO] forKey:@"HasListedFirstDirectory"];
	[d setObject:[NSNumber numberWithBool:flag] forKey:@"overwrite"];
	
	[_recursiveDownloadLock lock];
	[_recursiveDownloadQueue addObject:d];
	[_recursiveDownloadLock unlock];
	
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processRecursiveDownloadingQueue];
	
	return rec;
}

#pragma mark -
#pragma mark Peer Connection Delegate Methods

- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveError:(NSError *)error
{
	if (con == _recursiveDeletionConnection &&
		[[error localizedDescription] containsSubstring:@"failed to delete file"] &&
		[[error localizedFailureReason] containsSubstring:@"permission denied"])
	{
		//Permission Error while deleting a file in recursive deletion. We handle it as if it successfully deleted the file, but don't give any delegate notifications about this specific file.
		[_recursiveDeletionLock lock];
		if ([_filesToDelete count] == 0 && _numberOfDeletionListingsRemaining == 0)
		{
			_numberOfDirDeletionsRemaining += [_emptyDirectoriesToDelete count];
			NSEnumerator *e = [_emptyDirectoriesToDelete reverseObjectEnumerator];
			NSString *cur;
			while (cur = [e nextObject])
			{
				[_recursiveDeletionConnection deleteDirectory:cur];
			}
			[_emptyDirectoriesToDelete removeAllObjects];
		}
		[_recursiveDeletionLock unlock];		
		return;
	}
	else if (con == _recursiveDeletionConnection &&
			 [[error localizedDescription] containsSubstring:@"failed to delete directory"])
	{
		//Permission Error while deleting a directory in recursive deletion. We handle it as if it successfully deleted the directory. If the error is for the actual ancestor directory, we send out an error.
		[_recursiveDeletionLock lock];
		_numberOfDirDeletionsRemaining--;
		if (_numberOfDirDeletionsRemaining == 0 && [_recursiveDeletionsQueue count] > 0)
		{
			[_recursiveDeletionsQueue removeObjectAtIndex:0];
			if (_flags.error)
			{
				[_forwarder connection:self didReceiveError:error];
			}
			if ([_recursiveDeletionsQueue count] == 0)
			{
				myStreamFlags.isDeleting = NO;				
				[_recursiveDeletionConnection disconnect];
			}
			else
			{
				NSString *directoryPath = [_recursiveDeletionsQueue objectAtIndex:0];
				[_emptyDirectoriesToDelete addObject:directoryPath];
				_numberOfDeletionListingsRemaining++;
				[_recursiveDeletionConnection changeToDirectory:directoryPath];
				[_recursiveDeletionConnection directoryContents];
			}
		}
		[_recursiveDeletionLock unlock];	
		return;
	}
	//If any of these connections are nil, they were released by the didDisconnect method. We need them, however.
	//In testing, this is because the host didn't support the number of additional concurrent connections we requested to open.
	//To remedy this, we point the nil connection to ourself connection, who will perform that work as well.
		
	NSLog(@"%@", [error description]);
	if ([_recursiveDeletionsQueue count] > 0 && con == _recursiveDeletionConnection)
	{
		if (previousDelegate)
			return;

		[self temporarilyTakeOverRecursiveDeletionDelegate];
		
		[_recursiveDeletionLock lock];
		NSString *pathToDelete = [_recursiveDeletionsQueue objectAtIndex:0];
		[_recursiveDeletionLock unlock];
		
		[_recursiveDeletionConnection changeToDirectory:pathToDelete];
		[_recursiveDeletionConnection directoryContents];
	}
	else if ([_recursiveDownloadQueue count] > 0 && con == _recursiveDownloadConnection)
	{
		if (previousDelegate)
			return;
		
		[self temporarilyTakeOverRecursiveDownloadingDelegate];
		
		[_recursiveDownloadLock lock];
		NSString *pathToDownload = [[_recursiveDownloadQueue objectAtIndex:0] objectForKey:@"remote"];
		[_recursiveDownloadLock unlock];
		
		[_recursiveDownloadConnection changeToDirectory:pathToDownload];
		[_recursiveDownloadConnection directoryContents];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didChangeToDirectory:(NSString *)dirPath error:(NSError *)error;
{
	if (!error)
		return;
	//We had some difficulty changing to a directory. We're obviously not going to list that directory, we lets just remove it from whatever queue we need to
	if (con == _fileCheckingConnection)
	{
		[_fileCheckLock lock];
		
		NSEnumerator *e = [[NSArray arrayWithArray:_fileCheckQueue] nextObject];
		NSString *filePathToCheck;
		while (filePathToCheck = [e nextObject])
		{
			if (![[filePathToCheck stringByDeletingLastPathComponent] isEqualToString:dirPath])
				continue;
			if (_flags.fileCheck)
				[_forwarder connection:self checkedExistenceOfPath:filePathToCheck pathExists:NO error:error];
			
			[_fileCheckQueue removeObject:filePathToCheck];
			if ([filePathToCheck isEqualToString:_fileCheckInFlight])
			{
				[_fileCheckInFlight autorelease];
				_fileCheckInFlight = nil;
				[self performSelector:@selector(processFileCheckingQueue) withObject:nil afterDelay:0];
			}
		}
		[_fileCheckLock unlock];
	}
	else if (con == _recursiveDeletionConnection)
	{
		[_recursiveDeletionLock lock];
		_numberOfDeletionListingsRemaining--;
		[_recursiveDeletionLock unlock];
	}
	else if (con == _recursiveDownloadConnection)
	{
		
	}
	else if (con == _recursiveS3RenameConnection)
	{
	}
}
- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host
{
	if (con == _fileCheckingConnection)
	{
		[_fileCheckingConnection release];
		_fileCheckingConnection = nil;
	}
	else if (con == _recursiveDeletionConnection)
	{
		[_recursiveDeletionConnection release];
		_recursiveDeletionConnection = nil;
	}
	else if (con == _recursiveDownloadConnection)
	{
		[_recursiveDownloadConnection release];
		_recursiveDownloadConnection = nil;
	}
	else if (con == _recursiveS3RenameConnection)
	{
		[_recursiveS3RenameConnection release];
		_recursiveS3RenameConnection = nil;
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath error:(NSError *)error
{
	if (con == _fileCheckingConnection)
	{
		if (_flags.fileCheck) 
		{
			NSArray *currentDirectoryContentsFilenames = [contents valueForKey:cxFilenameKey];
			NSMutableArray *fileChecksToRemoveFromQueue = [NSMutableArray array];
			[_fileCheckLock lock];
			NSEnumerator *pathsToCheckForEnumerator = [_fileCheckQueue objectEnumerator];
			NSString *currentPathToCheck;
			while ((currentPathToCheck = [pathsToCheckForEnumerator nextObject]))
			{
				if (![[currentPathToCheck stringByDeletingLastPathComponent] isEqualToString:dirPath])
				{
					continue;
				}
				[fileChecksToRemoveFromQueue addObject:currentPathToCheck];
				BOOL currentDirectoryContainsFile = [currentDirectoryContentsFilenames containsObject:[currentPathToCheck lastPathComponent]];
				[_forwarder connection:self checkedExistenceOfPath:currentPathToCheck pathExists:currentDirectoryContainsFile error:nil];
			}
			[_fileCheckQueue removeObjectsInArray:fileChecksToRemoveFromQueue];
			[_fileCheckLock unlock];
		}
		[_fileCheckInFlight autorelease];
		_fileCheckInFlight = nil;
		[self performSelector:@selector(processFileCheckingQueue) withObject:nil afterDelay:0.0];
	}
	else if (con == _recursiveDeletionConnection)
	{
		[_recursiveDeletionLock lock];
		_numberOfDeletionListingsRemaining--;
		
		if (![dirPath hasPrefix:[_recursiveDeletionsQueue objectAtIndex:0]])
		{
			//If we get here, we received a listing for something that is *not* a subdirectory of the root path we were asked to delete. Log it, and return.
			NSLog(@"Received Listing For Inappropriate Path when Recursively Deleting.");
			[_recursiveDeletionLock unlock];
			return;
		}
		
		NSEnumerator *e = [contents objectEnumerator];
		NSDictionary *cur;
		
		if (_flags.discoverFilesToDeleteInAncestor) 
			[_forwarder connection:self didDiscoverFilesToDelete:contents inAncestorDirectory:[_recursiveDeletionsQueue objectAtIndex:0]];
		if (_flags.discoverFilesToDeleteInDirectory)
			[_forwarder connection:self didDiscoverFilesToDelete:contents inDirectory:dirPath];
		
		while ((cur = [e nextObject]))
		{
			if ([[cur objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
			{
				_numberOfDeletionListingsRemaining++;
				[_recursiveDeletionConnection changeToDirectory:[dirPath stringByAppendingPathComponent:[cur objectForKey:cxFilenameKey]]];
				[_recursiveDeletionConnection directoryContents];
			}
			else
			{
				[_filesToDelete addObject:[dirPath stringByAppendingPathComponent:[cur objectForKey:cxFilenameKey]]];
			}
		}
		
		if (![_recursiveDeletionsQueue containsObject:[dirPath stringByStandardizingPath]])
		{
			[_emptyDirectoriesToDelete addObject:[dirPath stringByStandardizingPath]];
		}
		if (_numberOfDeletionListingsRemaining == 0)
		{
			if ([_filesToDelete count] > 0)
			{
				//We finished listing what we need to delete. Let's delete it now.
				NSEnumerator *e = [_filesToDelete objectEnumerator];
				NSString *pathToDelete;
				while (pathToDelete = [e nextObject])
				{
					[_recursiveDeletionConnection deleteFile:pathToDelete];
				}
			}
			else
			{
				//We've finished listing directories and deleting files. Let's delete directories.
				_numberOfDirDeletionsRemaining += [_emptyDirectoriesToDelete count];
				NSEnumerator *e = [_emptyDirectoriesToDelete reverseObjectEnumerator];
				NSString *cur;
				while (cur = [e nextObject])
				{
					[_recursiveDeletionConnection deleteDirectory:cur];
				}
				[_emptyDirectoriesToDelete removeAllObjects];				
			}
		}
		[_recursiveDeletionLock unlock];
	}
	else if (con == _recursiveDownloadConnection) 
	{
		[_recursiveDownloadLock lock];
		NSMutableDictionary *rec = [_recursiveDownloadQueue objectAtIndex:0];
		CKTransferRecord *root = [rec objectForKey:@"record"];
		NSString *remote = [rec objectForKey:@"remote"]; 
//		if (![[rec objectForKey:@"HasListedFirstDirectory"] boolValue] && ![dirPath isEqualToString:remote])
//		{
//			//We received a listing for a directory OTHER than what we initially requested. We must be downloading a symbolic link.
//			//To preseve the initial request, modify our rec so we can determine the relative paths properly
//			[rec setObject:dirPath forKey:@"remote"];
//			[root setName:dirPath];
//			remote = dirPath;
//		}
		NSString *local = [rec objectForKey:@"local"]; 
		BOOL overwrite = [[rec objectForKey:@"overwrite"] boolValue];
		_numberOfDownloadListingsRemaining--;
		[_recursiveDownloadLock unlock];
		
		// setup the local relative directory
		NSString *relativePath = [dirPath substringFromIndex:[remote length]]; 
		NSString *localDir = [local stringByAppendingPathComponent:relativePath];
		[[NSFileManager defaultManager] recursivelyCreateDirectory:localDir attributes:nil];
		
		NSEnumerator *e = [contents objectEnumerator];
		NSDictionary *cur;
		
		while ((cur = [e nextObject]))
		{
			if ([[cur objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
			{
				[_recursiveDownloadLock lock];
				_numberOfDownloadListingsRemaining++;
				[_recursiveDownloadLock unlock];
				[_recursiveDownloadConnection changeToDirectory:[dirPath stringByAppendingPathComponent:[cur objectForKey:cxFilenameKey]]];
				[_recursiveDownloadConnection directoryContents];
			}
			else if ([[cur objectForKey:NSFileType] isEqualToString:NSFileTypeRegular])
			{
				CKTransferRecord *down = [self downloadFile:[dirPath stringByAppendingPathComponent:[cur objectForKey:cxFilenameKey]] 
												toDirectory:localDir
												  overwrite:overwrite
												   delegate:nil];
				[down setSize:[[cur objectForKey:NSFileSize] unsignedLongLongValue]];
				[CKTransferRecord mergeTextPathRecord:down withRoot:root];
			}
		}
		if (_numberOfDownloadListingsRemaining == 0)
		{
			[self setProperty:[NSNumber numberWithBool:NO] forKey:@"IsDiscoveringFilesToDownload"];
			if ([[root description] isEqualToString:[[CKTransferRecord rootRecordWithPath:remote] description]])
			{
				//We tried to download an entirely empty folder. We're finished.
				if (_flags.downloadFinished)
					[_forwarder connection:self downloadDidFinish:dirPath error:nil];
				//Ordinarily the children get finished, and in transferDidFinish:, we check to see if the parent is finished too. If it is, it gets notifications (thus, recursing.) Here, we have no children, and therefore no children to get the transferDidFinish: message, so this root will not be marked as "finished" unless we recursively mark its children (and their children, etc.) as finished.
				[self recursivelySendTransferDidFinishMessage:root];
			}
			[_recursiveDownloadLock lock];
			myStreamFlags.isDownloading = NO;
			[_recursiveDownloadQueue removeObjectAtIndex:0];
			[_recursiveDownloadLock unlock];
			
			if ([_recursiveDownloadQueue count] > 0)
				[self performSelector:@selector(processRecursiveDownloadingQueue) withObject:nil afterDelay:0.0];
			else
				[self restoreRecursiveDownloadingDelegate];
		}
	}
	else if (con == _recursiveS3RenameConnection)
	{
		[_recursiveS3RenameLock lock];
		NSString *fromRootPath = [[_recursiveS3RenamesQueue objectAtIndex:0] objectForKey:@"FromDirectoryPath"];
		NSString *toRootPath = [[_recursiveS3RenamesQueue objectAtIndex:0] objectForKey:@"ToDirectoryPath"];
		NSString *toDirPath = [toRootPath stringByAppendingPathComponent:[dirPath substringFromIndex:[fromRootPath length]]];
		[con createDirectory:toDirPath];
		
		NSEnumerator *contentsEnumerator = [contents objectEnumerator];
		NSDictionary *itemDict;
		while ((itemDict = [contentsEnumerator nextObject]))
		{
			NSString *itemRemotePath = [dirPath stringByAppendingPathComponent:[itemDict objectForKey:cxFilenameKey]];
			if ([[itemDict objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
			{
				_numberOfS3RenameListingsRemaining++;
				[con changeToDirectory:itemRemotePath];
				[con directoryContents];
			}
			else
			{
				_numberOfS3RenamesRemaining++;
				NSString *newItemRemotePath = [toDirPath stringByAppendingPathComponent:[itemRemotePath lastPathComponent]];
				[con rename:itemRemotePath to:newItemRemotePath];
			}
		}
		
		_numberOfS3RenameListingsRemaining--;
		[_recursivelyRenamedDirectoriesToDelete addObject:dirPath];
		
		if (_numberOfS3RenamesRemaining == 0 && _numberOfS3RenameListingsRemaining == 0)
		{
			NSEnumerator *renamedDirectoriesToDelete = [_recursivelyRenamedDirectoriesToDelete reverseObjectEnumerator];
			NSString *path;
			while ((path = [renamedDirectoriesToDelete nextObject]))
			{
				_numberOfS3RenameDirectoryDeletionsRemaining++;
				[con deleteDirectory:path];
			}
			[_recursivelyRenamedDirectoriesToDelete removeAllObjects];
		}		
		
		[_recursiveS3RenameLock unlock];
	}
}

- (void)connection:(AbstractConnection *)conn didRename:(NSString *)fromPath to:(NSString *)toPath error:(NSError *)error
{
	if (conn == _recursiveS3RenameConnection)
	{
		[_recursiveS3RenameLock lock];
		_numberOfS3RenamesRemaining--;
		if (_numberOfS3RenamesRemaining == 0 && _numberOfS3RenameListingsRemaining == 0)
		{
			NSEnumerator *renamedDirectoriesToDelete = [_recursivelyRenamedDirectoriesToDelete reverseObjectEnumerator];
			NSString *path;
			while ((path = [renamedDirectoriesToDelete nextObject]))
			{
				_numberOfS3RenameDirectoryDeletionsRemaining++;
				[conn deleteDirectory:path];
			}
			[_recursivelyRenamedDirectoriesToDelete removeAllObjects];
		}
		[_recursiveS3RenameLock unlock];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteFile:(NSString *)path error:(NSError *)error
{
	if (con == _recursiveDeletionConnection)
	{
		if (_flags.deleteFileInAncestor) {
			[_forwarder connection:self didDeleteFile:[path stringByStandardizingPath] inAncestorDirectory:[_recursiveDeletionsQueue objectAtIndex:0] error:error];
		}
		
		[_recursiveDeletionLock lock];
		[_filesToDelete removeObject:path];
		if ([_filesToDelete count] == 0 && _numberOfDeletionListingsRemaining == 0)
		{
			_numberOfDirDeletionsRemaining += [_emptyDirectoriesToDelete count];
			NSEnumerator *e = [_emptyDirectoriesToDelete reverseObjectEnumerator];
			NSString *cur;
			while (cur = [e nextObject])
			{
				[_recursiveDeletionConnection deleteDirectory:cur];
			}
			[_emptyDirectoriesToDelete removeAllObjects];
		}
		[_recursiveDeletionLock unlock];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteDirectory:(NSString *)dirPath error:(NSError *)error
{
	if (con == _recursiveDeletionConnection)
	{
		[_recursiveDeletionLock lock];
		_numberOfDirDeletionsRemaining--;
		if (_numberOfDirDeletionsRemaining == 0 && [_recursiveDeletionsQueue count] > 0)
		{
			[_recursiveDeletionsQueue removeObjectAtIndex:0];
			if (_flags.deleteDirectory) 
			{
				if (previousDelegate && _recursiveDeletionConnection == self && [_recursiveDeletionConnection delegate] == self)
				{
					//In connection:didReceiveError, we were notified that the deletion connection we attempted to open up failed to open. To remedy this, we used OURSELF as the deletion connection, temporarily setting our delegate to OURSELF so we'd receive the calls we needed to perform the deletion. 
					//Now that we're done, let's restore our delegate.
					[self restoreRecursiveDeletionDelegate];
					[_forwarder connection:self didDeleteDirectory:dirPath error:error];
					if ([_recursiveDeletionsQueue count] > 0)
						[self temporarilyTakeOverRecursiveDeletionDelegate];
				}
				else
				{
					[_forwarder connection:self didDeleteDirectory:dirPath error:error];
				}
			}			
			if ([_recursiveDeletionsQueue count] == 0)
			{
				myStreamFlags.isDeleting = NO;				
				[_recursiveDeletionConnection disconnect];
			}
			else
			{
				NSString *directoryPath = [_recursiveDeletionsQueue objectAtIndex:0];
				[_emptyDirectoriesToDelete addObject:directoryPath];
				_numberOfDeletionListingsRemaining++;
				[_recursiveDeletionConnection changeToDirectory:directoryPath];
				[_recursiveDeletionConnection directoryContents];
			}
		}
		else
		{
			if (_flags.deleteDirectoryInAncestor)
			{
				NSString *ancestorDirectory = [_recursiveDeletionsQueue objectAtIndex:0];
				if (previousDelegate && _recursiveDeletionConnection == self && [_recursiveDeletionConnection delegate] == self)
				{
					[self restoreRecursiveDeletionDelegate];
					[_forwarder connection:self didDeleteDirectory:[dirPath stringByStandardizingPath] inAncestorDirectory:ancestorDirectory error:error];
					[self temporarilyTakeOverRecursiveDeletionDelegate];
				}
				else
				{
					[_forwarder connection:self didDeleteDirectory:[dirPath stringByStandardizingPath] inAncestorDirectory:ancestorDirectory error:error];
				}
			}
		}
		[_recursiveDeletionLock unlock];
	}
	else if (con == _recursiveS3RenameConnection)
	{
		[_recursiveS3RenameLock lock];
		
		_numberOfS3RenameDirectoryDeletionsRemaining--;
		if (_numberOfS3RenameDirectoryDeletionsRemaining == 0)
		{
			_numberOfS3RenameListingsRemaining = 0;
			_numberOfS3RenamesRemaining = 0;
			_numberOfS3RenameDirectoryDeletionsRemaining = 0;
			myStreamFlags.isRecursivelyRenamingForS3 = NO;
			NSDictionary *renameDictionary = [_recursiveS3RenamesQueue objectAtIndex:0];
			NSString *fromDirectoryPath = [NSString stringWithString:[renameDictionary objectForKey:@"FromDirectoryPath"]];
			NSString *toDirectoryPath = [NSString stringWithString:[renameDictionary objectForKey:@"ToDirectoryPath"]];
			[_recursiveS3RenamesQueue removeObjectAtIndex:0];
			
			if ([_recursiveS3RenamesQueue count] > 0)
			{
				[self processRecursiveS3RenamingQueue];
			}
			else
			{
				[con disconnect];
				if (_flags.rename)
					[_forwarder connection:self didRename:fromDirectoryPath to:toDirectoryPath error:nil];
			}
		}
		
		[_recursiveS3RenameLock unlock];
	}
}

#pragma mark -
#pragma mark SSL Support

- (NSString *)sslErrorStringWithCode:(OSStatus)code
{
	return [NSString stringWithFormat:@"%s: %s", GetMacOSStatusErrorString(code), GetMacOSStatusCommentString(code)];
}

- (void)initializeSSL
{
	SecKeychainRef keychainRef = nil;
	SecIdentitySearchRef searchRef = nil;
	
	if (SecKeychainCopyDefault(&keychainRef))
	{
		KTLog(SSLDomain, KTLogFatal, @"Unable to get default keychain");
	}
	
	if (SecIdentitySearchCreate(keychainRef, CSSM_KEYUSE_SIGN, &searchRef))
	{
		KTLog(SSLDomain, KTLogFatal, @"Unable to create keychain search");
	}
	
	if (SecIdentitySearchCopyNext(searchRef, &mySSLIdentity))
	{
		KTLog(SSLDomain, KTLogFatal, @"Unable to get next search result");
	}
	
	if (keychainRef) CFRelease(keychainRef);
	if (searchRef) CFRelease(searchRef);

	[mySSLRawReadBuffer autorelease];
	mySSLRawReadBuffer = [[NSMutableData data] retain];
	
	[self negotiateSSLWithData:nil];
}

- (void)negotiateSSLWithData:(NSData *)data
{
	NSMutableData *outputData = [NSMutableData data];
	[mySSLRawReadBuffer appendData:data];
	int ret = [self handshakeWithInputData:mySSLRawReadBuffer outputData:outputData];
	
	if ([outputData length])
	{
		[self sendData:outputData];
	}
	
	if (ret < 0)
	{
		if (_flags.error)
		{
			NSError *err = [NSError errorWithDomain:SSLErrorDomain code:1 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"SSL Error Occurred", NSLocalizedDescriptionKey, [self host], ConnectionHostKey, nil]];
			[_forwarder connection:self didReceiveError:err];
		}
		return;
	}
	
	if (ret == 1)
	{
		myStreamFlags.isNegotiatingSSL = NO;
		myStreamFlags.sslOn = YES;
		
		//[self ONB_provideEncryptedData];
		return;
	}
}

- (int)handshakeWithInputData:(NSMutableData *)inputData
				   outputData:(NSMutableData *)outputData
{
	OSStatus ret;
	
	// If we haven't yet set up the SSL context, we should do so now.
	if (!mySSLContext)
	{
		if (ret = SSLNewContext((Boolean)NO, &mySSLContext))
		{
			KTLog(SSLDomain, KTLogError, @"Error creating new context");
			return ret;
		}
		
		if (ret = SSLSetIOFuncs(mySSLContext, SSLReadFunction, SSLWriteFunction))
		{
			KTLog(SSLDomain, KTLogError, @"Error setting IO Functions");
			return ret;
		}
		
		if (ret = SSLSetConnection(mySSLContext, self))
		{
			KTLog(SSLDomain, KTLogError, @"Error setting connection");
			return ret;
		}
		
		// we need to manually verify the certificates so that if they aren't valid, the connection isn't terminated straight away
		if (ret = SSLSetEnableCertVerify(mySSLContext, (Boolean)NO))
		{
			KTLog(SSLDomain, KTLogError, @"Error calling SSLSetEnableCertVerify");
			return ret;
		}
		
		if (mySSLIdentity)
		{
			CFArrayRef certificates = CFArrayCreate(kCFAllocatorDefault,
													(const void **)&mySSLIdentity,
													mySSLIdentity ? 1 : 0,
													NULL);
			
			if (certificates)
			{
				ret = SSLSetCertificate(mySSLContext, certificates);
				CFRelease(certificates);
			}
			if (ret)
			{
				KTLog(SSLDomain, KTLogError, @"Error setting certificates: %d", ret);
				return ret;
			}
			else
			{
				KTLog(SSLDomain, KTLogDebug, @"Set up certificates successfully");
			}
		}
	}
	
	mySSLRecevieBuffer = inputData;
	mySSLSendBuffer = outputData;
	ret = SSLHandshake(mySSLContext);
	
	if (ret == errSSLWouldBlock)
		return 0;
	
	if (! ret)
		return 1;
	
	return ret;
}

- (NSData *)encryptData:(NSData *)data inputData:(NSMutableData *)inputData
{
	if ((! data) || (! [data length]))
		return [NSData data];
	
	mySSLRecevieBuffer = inputData;
	mySSLSendBuffer = [NSMutableData dataWithCapacity:2*[data length]];
	unsigned int totalLength = [data length];
	unsigned int processed = 0;
	const void *buffer = [data bytes];
	
	while (processed < totalLength)
	{
		size_t written = 0;
		
		int ret = SSLWrite(mySSLContext, buffer + processed, totalLength - processed, &written);
		if (noErr != ret)
		{
			return nil;
		}
		
		processed += written;
	}
	
	return [NSData dataWithData:mySSLSendBuffer];
}

- (NSData *)decryptData:(NSMutableData *)data outputData:(NSMutableData *)outputData
{
	if ((! data) || (! [data length]))
		return [NSData data];
	
	mySSLRecevieBuffer = data;
	mySSLSendBuffer = outputData;
	NSMutableData *decryptedData = [NSMutableData dataWithCapacity:[data length]];
	int ret = 0;
	
	while (! ret)
	{
		size_t read = 0;
		char buf[1024];
		
		ret = SSLRead(mySSLContext, buf, 1024, &read);
		if (ret && (ret != errSSLWouldBlock) && (ret != errSSLClosedGraceful))
		{
			KTLog(SSLDomain, KTLogFatal, @"Error in SSLRead: %d", ret);
			return nil;
		}
		
		[decryptedData appendBytes:buf length:read];
	}
	
	return [NSData dataWithData:decryptedData];
}

- (OSStatus)handleSSLWriteFromData:(const void *)data size:(size_t *)size
{
	[mySSLSendBuffer appendBytes:data length:*size];
	return errSSLWouldBlock;
}

- (OSStatus)handleSSLReadToData:(void *)data size:(size_t *)size
{
	size_t askedSize = *size;
	*size = MIN(askedSize, [mySSLRecevieBuffer length]);
	if (! *size)
	{
		return errSSLWouldBlock;
	}
	
	NSRange byteRange = NSMakeRange(0, *size);
	[mySSLRecevieBuffer getBytes:data range:byteRange];
	[mySSLRecevieBuffer replaceBytesInRange:byteRange withBytes:NULL length:0];
	
	if (askedSize > *size)
		return errSSLWouldBlock;
	
	return noErr;
}

- (void)setSSLOn:(BOOL)flag
{
	myStreamFlags.wantsSSL = flag;
	if (myStreamFlags.wantsSSL)
	{
		if (!myStreamFlags.sslOn)
		{
			if ([_sendStream streamStatus] == NSStreamStatusOpen)
			{
				// start the handshake now.
				
			}
		}
	}
	else
	{
		if (myStreamFlags.sslOn)
		{
			// turn ssl off
			
		}
	}
}

@end

OSStatus SSLReadFunction(SSLConnectionRef connection, void *data, size_t *dataLength)
{
	CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1, (Boolean)YES);
	return [(StreamBasedConnection *)connection handleSSLReadToData:data size:dataLength];
}

OSStatus SSLWriteFunction(SSLConnectionRef connection, const void *data, size_t *dataLength)
{
	OSStatus result = [(StreamBasedConnection *)connection handleSSLWriteFromData:data size:dataLength];
	// give the runloop a run after writing to have an opportunity to read
	CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1, (Boolean)YES);
	return result;
}

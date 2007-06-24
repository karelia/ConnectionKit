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

#import "StreamBasedConnection.h"

#import "ConnectionThreadManager.h"
#import "InterThreadMessaging.h"
#import "NSData+Connection.h"
#import "NSObject+Connection.h"
#import "NSFileManager+Connection.h"
#import "RunLoopForwarder.h"
#import "CKCacheableHost.h"
#import "CKTransferRecord.h"

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
		
		_recursiveDeletionsQueue = [[NSMutableArray alloc] init];
		_emptyDirectoriesToDelete = [[NSMutableArray alloc] init];
		_deletionLock = [[NSLock alloc] init];
		
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
	[_fileCheckInFlight release];
	
	[_recursiveDeletionsQueue release];
	[_recursiveListingConnection setDelegate:nil];
	[_recursiveListingConnection forceDisconnect];
	[_recursiveListingConnection release];
	[_recursiveDeletionConnection setDelegate:nil];
	[_recursiveDeletionConnection forceDisconnect];
	[_recursiveDeletionConnection release];
	[_emptyDirectoriesToDelete release];
	[_deletionLock release];
	
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

- (void)openStreamsToPort:(unsigned)port
{
	NSHost *host = [CKCacheableHost hostWithName:_connectionHost];
	if(!host){
		KTLog(TransportDomain, KTLogError, @"Cannot find the host: %@", _connectionHost);
		
        if (_flags.error) {
			NSError *error = [NSError errorWithDomain:ConnectionErrorDomain 
												 code:EHOSTUNREACH
											 userInfo:
				[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInThisBundle(@"Host Unavailable", @"Couldn't open the port to the host"), NSLocalizedDescriptionKey,
					_connectionHost, @"host", nil]];
            [_forwarder connection:self didReceiveError:error];
		}
		return;
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
	if (setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &opt, sizeof(opt)))
	{
		NSLog(@"Failed to set tcp no delay setting");
	}
	opt = 240; // 2 minutes
	if (setsockopt(sock, IPPROTO_TCP, TCP_KEEPALIVE, &opt, sizeof(opt)))
	{
		NSLog(@"Failed to set tcp keep alive setting");
	}
	
	struct sockaddr_in addr;
	bzero((char *) &addr, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	addr.sin_addr.s_addr = inet_addr([[host address] cString]);
	
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
		
		if (_flags.error) {
			NSError *error = [NSError errorWithDomain:ConnectionErrorDomain 
												 code:EHOSTUNREACH
											 userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInThisBundle(@"Stream Unavailable", @"Error creating stream")
																				  forKey:NSLocalizedDescriptionKey]];
			[_forwarder connection:self didReceiveError:error];
		}
		return;
	}
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
	[self emptyCommandQueue];
	
	int connectionPort = [_connectionPort intValue];
	if (0 == connectionPort)
	{
		connectionPort = 21;	// standard FTP control port
	}
	
	[self openStreamsToPort:connectionPort];
	
	[super connect];
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
	[_recursiveListingConnection disconnect];
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
	[_recursiveListingConnection forceDisconnect];
	[_recursiveDeletionConnection forceDisconnect];
	[_recursiveDownloadConnection forceDisconnect];
}

- (void) cleanupConnection
{
	[_fileCheckingConnection cleanupConnection];
	[_recursiveListingConnection cleanupConnection];
	[_recursiveDeletionConnection cleanupConnection];
	[_recursiveDownloadConnection cleanupConnection];
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
//													 userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInThisBundle(@"Timed Out waiting for remote host.", @"time out") forKey:NSLocalizedDescriptionKey]];
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
			
			if (GET_STATE == ConnectionNotConnectedState) 
			{
				error = [NSError errorWithDomain:ConnectionErrorDomain
											code:ConnectionStreamError
										userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@ %@?", LocalizedStringInThisBundle(@"Is the service running on the server", @"Stream Error before opening"), [self host]]
																			 forKey:NSLocalizedDescriptionKey]];
			}
			else
			{
				// we want to catch the connection reset by peer error
				error = [_receiveStream streamError];
				if ([[error domain] isEqualToString:NSPOSIXErrorDomain] && ([error code] == ECONNRESET || [error code] == EPIPE))
				{
					KTLog(TransportDomain, KTLogInfo, @"Connection was reset by peer/broken pipe, attempting to reconnect.", [_receiveStream streamError]);
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
										userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@ %@?", LocalizedStringInThisBundle(@"Is the service running on the server", @"Stream Error before opening"), [self host]]
																			 forKey:NSLocalizedDescriptionKey]];
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
		_fileCheckingConnection = [[[self class] alloc] initWithHost:[self host]
																port:[self port]
															username:[self username]
															password:[self password]
															   error:nil];
		[_fileCheckingConnection setDelegate:self];
		[_fileCheckingConnection setTranscript:[self propertyForKey:@"FileCheckingTranscript"]];
	}
	if (![_fileCheckingConnection isConnected])
	{
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
#pragma mark Recursive Deletion Support Methods

- (void)processRecursiveDeletionQueue
{
	if (!_recursiveListingConnection)
	{
		_recursiveListingConnection = [self copy];
		[_recursiveListingConnection setName:@"recursive listing"];
		[_recursiveListingConnection setDelegate:self];
		[_recursiveListingConnection setTranscript:[self propertyForKey:@"RecursiveDirectoryDeletionTranscript"]];
		_recursiveDeletionConnection = [self copy];
		[_recursiveDeletionConnection setName:@"recursive deletion"];
		[_recursiveDeletionConnection setDelegate:self];
		[_recursiveDeletionConnection setTranscript:[self propertyForKey:@"RecursiveDirectoryDeletionTranscript"]];
	}
	if (![_recursiveListingConnection isConnected])
	{
		[_recursiveListingConnection connect];
	}
	if (![_recursiveDeletionConnection isConnected])
	{
		[_recursiveDeletionConnection connect];
	}
	[_deletionLock lock];
	if (!myStreamFlags.isDeleting && [_recursiveDeletionsQueue count] > 0)
	{
		_numberOfListingsRemaining++;
		myStreamFlags.isDeleting = YES;
		[_recursiveListingConnection contentsOfDirectory:[_recursiveDeletionsQueue objectAtIndex:0]];
	}
	[_deletionLock unlock];
}

- (void)recursivelyDeleteDirectory:(NSString *)path
{
	[_deletionLock lock];
	[_recursiveDeletionsQueue addObject:[path stringByStandardizingPath]];
	[_emptyDirectoriesToDelete addObject:[path stringByStandardizingPath]];
	[_deletionLock unlock];
	
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processRecursiveDeletionQueue];
}

#pragma mark -
#pragma mark Recursive Downloading Support

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
		_downloadListingsRemaining++;
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
	[d setObject:[NSNumber numberWithBool:flag] forKey:@"overwrite"];
	
	[_recursiveDownloadLock lock];
	[_recursiveDownloadQueue addObject:d];
	[_recursiveDownloadLock unlock];
	
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] processRecursiveDownloadingQueue];
	
	return rec;
}

#pragma mark -
#pragma mark Peer Connection Delegate Methods

- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host
{
	if (con == _fileCheckingConnection)
	{
		[_fileCheckingConnection release];
		_fileCheckingConnection = nil;
	}
	else if (con == _recursiveListingConnection)
	{
		[_editingConnection release];
		_editingConnection = nil;
	}
	else if (con == _recursiveDeletionConnection)
	{
		[_editingConnection release];
		_editingConnection = nil;
	}
	else if (con == _recursiveListingConnection)
	{
		[_recursiveListingConnection release];
		_recursiveListingConnection = nil;
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath;
{
	if (con == _fileCheckingConnection)
	{
		if (_flags.fileCheck) {
			NSString *name = [_fileCheckInFlight lastPathComponent];
			NSEnumerator *e = [contents objectEnumerator];
			NSDictionary *cur;
			BOOL foundFile = NO;
			
			while (cur = [e nextObject]) 
			{
				if ([[cur objectForKey:cxFilenameKey] isEqualToString:name]) 
				{
					[_forwarder connection:self checkedExistenceOfPath:_fileCheckInFlight pathExists:YES];
					foundFile = YES;
					break;
				}
			}
			if (!foundFile)
			{
				[_forwarder connection:self checkedExistenceOfPath:_fileCheckInFlight pathExists:NO];
			}
		}
		[self dequeueFileCheck];
		[_fileCheckInFlight autorelease];
		_fileCheckInFlight = nil;
		[self performSelector:@selector(processFileCheckingQueue) withObject:nil afterDelay:0.0];
	}
	else if (con == _recursiveListingConnection)
	{
		[_deletionLock lock];
		_numberOfListingsRemaining--;
		NSEnumerator *e = [contents objectEnumerator];
		NSDictionary *cur;
		
		if (_flags.discoverFilesToDeleteInAncestor) 
		{
			[_forwarder connection:self didDiscoverFilesToDelete:contents inAncestorDirectory:[_recursiveDeletionsQueue objectAtIndex:0]];
		}
		if (_flags.discoverFilesToDeleteInDirectory)
		{
			[_forwarder connection:self didDiscoverFilesToDelete:contents inDirectory:dirPath];
		}
		
		while ((cur = [e nextObject]))
		{
			if ([[cur objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
			{
				_numberOfListingsRemaining++;
				[_recursiveListingConnection contentsOfDirectory:[dirPath stringByAppendingPathComponent:[cur objectForKey:cxFilenameKey]]];
			}
			else
			{
				_numberOfDeletionsRemaining++;
				[_recursiveDeletionConnection deleteFile:[dirPath stringByAppendingPathComponent:[cur objectForKey:cxFilenameKey]]];
			}
		}
		if (![_recursiveDeletionsQueue containsObject:[dirPath stringByStandardizingPath]])
		{
			[_emptyDirectoriesToDelete addObject:[dirPath stringByStandardizingPath]];
		}
		if (_numberOfDeletionsRemaining == 0 && _numberOfListingsRemaining == 0)
		{
			NSEnumerator *e = [_emptyDirectoriesToDelete reverseObjectEnumerator];
			NSString *cur;
			while (cur = [e nextObject])
			{
				_numberOfDirDeletionsRemaining++;
				[_recursiveDeletionConnection deleteDirectory:cur];
			}
			[_emptyDirectoriesToDelete removeAllObjects];
		}
		[_deletionLock unlock];
	}
	else if (con == _recursiveDownloadConnection) 
	{
		[_recursiveDownloadLock lock];
		NSDictionary *rec = [_recursiveDownloadQueue objectAtIndex:0];
		CKTransferRecord *root = [rec objectForKey:@"record"];
		NSString *remote = [rec objectForKey:@"remote"];
		NSString *local = [rec objectForKey:@"local"];
		BOOL overwrite = [[rec objectForKey:@"overwrite"] boolValue];
		_downloadListingsRemaining--;
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
				_downloadListingsRemaining++;
				[_recursiveDownloadLock unlock];
				[_recursiveDownloadConnection changeToDirectory:[dirPath stringByAppendingPathComponent:[cur objectForKey:cxFilenameKey]]];
				[_recursiveDownloadConnection directoryContents];
			}
			else
			{
				CKTransferRecord *down = [self downloadFile:[dirPath stringByAppendingPathComponent:[cur objectForKey:cxFilenameKey]] 
												toDirectory:localDir
												  overwrite:overwrite
												   delegate:nil];
				[down setSize:[[cur objectForKey:NSFileSize] unsignedLongLongValue]];
				[CKTransferRecord mergeTextPathRecord:down withRoot:root];
			}
		}
		if (_downloadListingsRemaining == 0)
		{
			[_recursiveDownloadLock lock];
			myStreamFlags.isDownloading = NO;
			[_recursiveDownloadQueue removeObjectAtIndex:0];
			
			if ([_recursiveDownloadQueue count] > 0)
			{
				[self performSelector:@selector(processRecursiveDownloadingQueue) withObject:nil afterDelay:0.0];
			}
			
			[_recursiveDownloadLock unlock];
		}
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteFile:(NSString *)path
{
	if (con == _recursiveDeletionConnection)
	{
		if (_flags.deleteFileInAncestor) {
			[_forwarder connection:self didDeleteFile:[path stringByStandardizingPath] inAncestorDirectory:[_recursiveDeletionsQueue objectAtIndex:0]];
		}
		
		[_deletionLock lock];
		_numberOfDeletionsRemaining--;
		if (_numberOfDeletionsRemaining == 0 && _numberOfListingsRemaining == 0)
		{
			NSEnumerator *e = [_emptyDirectoriesToDelete reverseObjectEnumerator];
			NSString *cur;
			while (cur = [e nextObject])
			{
				_numberOfDirDeletionsRemaining++;
				[_recursiveDeletionConnection deleteDirectory:cur];
			}
			[_emptyDirectoriesToDelete removeAllObjects];
		}
		[_deletionLock unlock];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteDirectory:(NSString *)dirPath
{
	if (con == _recursiveDeletionConnection)
	{
		[_deletionLock lock];
		_numberOfDirDeletionsRemaining--;
		[_deletionLock unlock];
		if (_numberOfDirDeletionsRemaining == 0 && [_recursiveDeletionsQueue count] > 0 && _numberOfListingsRemaining == 0)
		{
			_numberOfDeletionsRemaining = 0;
			myStreamFlags.isDeleting = NO;
			[_recursiveDeletionsQueue removeObjectAtIndex:0];
			if (_flags.deleteDirectory) {
				[_forwarder connection:self didDeleteDirectory:dirPath];
			}
		} else {
			if (_flags.deleteDirectoryInAncestor) {
				[_forwarder connection:self didDeleteDirectory:[dirPath stringByStandardizingPath] inAncestorDirectory:[_recursiveDeletionsQueue objectAtIndex:0]];
			}
		}
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
			NSError *err = [NSError errorWithDomain:SSLErrorDomain code:1 userInfo:[NSDictionary dictionaryWithObject:@"SSL Error Occurred" forKey:NSLocalizedDescriptionKey]];
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
		
		int ret;
		if (ret = SSLWrite(mySSLContext, buffer + processed, totalLength - processed, &written))
			return nil;
		
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

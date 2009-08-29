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

#import "CKStreamBasedConnection.h"

#import "CKConnectionThreadManager.h"

#import "NSData+Connection.h"
#import "NSObject+Connection.h"
#import "RunLoopForwarder.h"
#import "CKCacheableHost.h"
#import "CKTransferRecord.h"
#import "CKConnectionProtocol.h"
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

@interface CKStreamBasedConnection (Private)
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

@implementation CKStreamBasedConnection

- (id)initWithRequest:(CKConnectionRequest *)request
{
	if ([[[request URL] host] length] == 0) // our subclasses need a hostname to connect to
    {
        [self release];
        return nil;
    }
    
    if (self = [super initWithRequest:request])
	{
		_sendBufferLock = [[NSLock alloc] init];
		_sendBufferQueue = [[NSMutableArray alloc] init];
		_currentSendBufferReadLocation = 0;
		
		_createdThread = [NSThread currentThread];
		myStreamFlags.sendOpen = NO;
		myStreamFlags.readOpen = NO;
		
		myStreamFlags.wantsSSL = NO;
		myStreamFlags.isNegotiatingSSL = NO;
		myStreamFlags.sslOn = NO;
		myStreamFlags.allowsBadCerts = NO;
		myStreamFlags.initializedSSL = NO;
			
		mySSLEncryptedSendBuffer = [[NSMutableData data] retain];
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
	[_sendBufferQueue release];
	
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
		return [NSString stringWithData:[NSData dataWithBytes:addr length:strlen(addr)] encoding:NSASCIIStringEncoding];
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
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] checkQueue];
}

- (void)sendCommand:(id)command
{
	// Subclasses handle this
}

#pragma mark -
#pragma mark CKAbstractConnection Overrides

- (BOOL)openStreamsToPort:(unsigned)port
{
	NSHost *host = [CKCacheableHost hostWithName:[[[self request] URL] host]];
	if(!host){
		KTLog(CKTransportDomain, KTLogError, @"Cannot find the host: %@", [[[self request] URL] host]);
		
        NSError *error = [NSError errorWithDomain:CKConnectionErrorDomain 
                                             code:EHOSTUNREACH
                                         userInfo:
            [NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(@"Host Unavailable", @"Couldn't open the port to the host"), NSLocalizedDescriptionKey,
                [[[self request] URL] host], ConnectionHostKey, nil]];
        [[self client] connectionDidConnectToHost:[[[self request] URL] host] error:error];
		
		return NO;
	}
	/* If the host has multiple names it can screw up the order in the list of name */
	if ([[host names] count] > 1) {
		[host setValue:[NSArray arrayWithObject:[[[self request] URL] host]] forKey:@"names"]; // KVC hack
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
	
	KTLog(CKTransportDomain, KTLogDebug, @"Opening streams to host: %@", host);
	
	int sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	
	KTLog(CKTransportDomain, KTLogDebug, @"Socket: %d", port);
	
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
	
	KTLog(CKTransportDomain, KTLogDebug, @"Connecting to %@:%d", [host address], port);
	
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
		KTLog(CKTransportDomain, KTLogDebug, @"connect() failed");
	}
	
	if (!_receiveStream || !_sendStream)
	{
		KTLog(CKTransportDomain, KTLogError, @"Cannot create a stream to the host: %@", [[[self request] URL] host]);
		
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  LocalizedStringInConnectionKitBundle(@"Stream Unavailable", @"Error creating stream"), NSLocalizedDescriptionKey,
                                  [[[self request] URL] host], ConnectionHostKey, nil];
        NSError *error = [NSError errorWithDomain:CKConnectionErrorDomain code:EHOSTUNREACH userInfo:userInfo];
		[[self client] connectionDidConnectToHost:[[[self request] URL] host] error:error];
		[[self client] connectionDidReceiveError:error];
        
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
	if (_isConnecting || [self isConnected]) return;
	
	
	_isForceDisconnecting = NO;
	
	int connectionPort = [self port];
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
	CKConnectionCommand *con = [CKConnectionCommand command:[NSInvocation invocationWithSelector:@selector(threadedDisconnect) target:self arguments:[NSArray array]]
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionSentDisconnectState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:con];
}

- (void)threadedDisconnect
{
	[self setState:CKConnectionNotConnectedState];
	[self closeStreams];
	[super threadedDisconnect];
}

- (void)threadedForceDisconnect
{
	[self setState:CKConnectionNotConnectedState];
	_isForceDisconnecting = YES;
	[self closeStreams];

	[super threadedForceDisconnect];
}

- (void)forceDisconnect
{
	[self setState:CKConnectionNotConnectedState];
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedForceDisconnect];
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
		[_sendBufferLock lock];
		if ([_sendBufferQueue count] > 0)
			dataBuffer = [_sendBufferQueue objectAtIndex:0];
		else
			dataBuffer = nil;
		[_sendBufferLock unlock];
	}
	
	return dataBuffer;
}

- (void)sendQueuedOutput
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSMutableData *dataBuffer = [self outputDataBuffer];
	
	[_sendBufferLock lock];
	unsigned chunkLength = [dataBuffer length];
	if ([self shouldChunkData])
	{
		unsigned long long remainingBytes = [dataBuffer length] - _currentSendBufferReadLocation;
		chunkLength = MIN(kStreamChunkSize, remainingBytes);
	}
	if (chunkLength > 0)
	{
		NSRange chunkRange = NSMakeRange(_currentSendBufferReadLocation, chunkLength);
		uint8_t *bytes = (uint8_t *)[[dataBuffer subdataWithRange:chunkRange] bytes];
		[(NSOutputStream *)_sendStream write:bytes maxLength:chunkLength];
		[self recalcUploadSpeedWithBytesSent:chunkLength];
		[self stream:_sendStream sentBytesOfLength:chunkLength];
		_currentSendBufferReadLocation += chunkLength;
		
		//We're finished sending this chunk when our next byte to read is BEYOND the last byte.
		NSUInteger lastByteToReadLocation = [dataBuffer length] - 1;
		if (_currentSendBufferReadLocation > lastByteToReadLocation)
		{
			//We've sent all the bytes from this queued data object. Remove it from the queue.
			[_sendBufferQueue removeObjectAtIndex:0];
			
			//Now that the object we'll be getting from [self outputDataBuffer] will be new, reset the read location
			_currentSendBufferReadLocation = 0;
		}
		_lastChunkSent = [NSDate timeIntervalSinceReferenceDate];
	}
	else
	{
		// KTLog(OutputStreamDomain, KTLogDebug, @"NOTHING NEEDED TO BE SENT RIGHT NOW");
	}
	[_sendBufferLock unlock];
	
	[pool release];
}	

- (unsigned)sendData:(NSData *)data // returns how many bytes it sent. If the buffer was not empty and it was appended, then it will return 0
{
	//Only queue it if we actually have data to send.
	if ([data length] <= 0)
		return 0;
	
	if (myStreamFlags.wantsSSL)
	{
		if (!myStreamFlags.sslOn && !myStreamFlags.isNegotiatingSSL)
		{
			//put into the normal send buffer that is not encrypted.	
			[_sendBufferLock lock];
			[_sendBufferQueue addObject:data];
			[_sendBufferLock unlock];
			return 0;
		}
	}
	BOOL bufferWasEmpty = NO;
	
	[_sendBufferLock lock];
	bufferWasEmpty = [_sendBufferQueue count] == 0;
	[_sendBufferQueue addObject:data];
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
				/*
				 If this is uncommented, it'll cause massive CPU load when we're doing transfers.
				 From Greg: "if you enable this, you computer will heat your house this winter"
				 KTLog(CKInputStreamDomain, KTLogDebug, @"%d >> %@", len, [data shortDescription]);
				 */
				
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
			
			KTLog(CKInputStreamDomain, KTLogDebug, @"Command receive stream opened");
			break;
		}
		case NSStreamEventErrorOccurred:
		{
			KTLog(CKInputStreamDomain, KTLogError, @"receive stream error: %@", [_receiveStream streamError]);
			
			NSError *error = nil;
			
			CKConnectionState theState = GET_STATE;
			
			if (theState == CKConnectionNotConnectedState) 
			{
				error = [NSError errorWithDomain:CKConnectionErrorDomain
											code:CKConnectionStreamError
										userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%@ %@?", LocalizedStringInConnectionKitBundle(@"Is the service running on the server", @"Stream Error before opening"), [[[self request] URL] host]], NSLocalizedDescriptionKey, [[[self request] URL] host], ConnectionHostKey, nil]];
			}
			else
			{
				// we want to catch the connection reset by peer error
				error = [_receiveStream streamError];
				BOOL isResetByPeerError = [[error domain] isEqualToString:NSPOSIXErrorDomain] && ([error code] == ECONNRESET || [error code] == EPIPE);
				if (isResetByPeerError)
				{
					KTLog(CKTransportDomain, KTLogInfo, @"Connection was reset by peer/broken pipe, attempting to reconnect.", [_receiveStream streamError]);
					error = nil;
				}

				_isConnected = NO;
				[[self client] connectionDidDisconnectFromHost:[[[self request] URL] host]];
				
				if (!myStreamFlags.reportedError) 
				{
					myStreamFlags.reportedError = YES;
					[[self client] connectionDidReceiveError:error];
				}
				
				if (isResetByPeerError)
				{
					// resetup connection again
					[self closeStreams];
					[self setState:CKConnectionNotConnectedState];
					// roll back to the first command in this chain of commands
					NSArray *cmds = [[self lastCommand] sequencedChain];
					NSEnumerator *e = [cmds reverseObjectEnumerator];
					CKConnectionCommand *cur;
					
					while (cur = [e nextObject])
					{
						[self pushCommandOnCommandQueue:cur];
					}
					
					NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(openStreamsToPort:)
																	  target:self
																   arguments:[NSArray array]];
					int port = [self port];
					[inv setArgument:&port atIndex:2];
					[inv performSelector:@selector(invoke) onThread:_createdThread withObject:nil waitUntilDone:NO];
					
					while (_sendStream == nil || _receiveStream == nil)
					{
						[NSThread sleepUntilDate:[NSDate distantPast]];
					}
					
					[self scheduleStreamsOnRunLoop];
					break;
				}
			}
			
			if (theState == CKConnectionUploadingFileState || [self numberOfUploads] > 0) 
			{
				//We have uploads in the queue, so we need to dequeue them with the error
				while ([self numberOfUploads] > 0)
				{
					CKInternalTransferRecord *upload = [[self currentUpload] retain];
					[self dequeueUpload];
					
					[[self client] uploadDidFinish:[upload remotePath] error:error];
                    
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
				}
			}
			if (theState == CKConnectionDownloadingFileState || theState == CKConnectionSentSizeState || [self numberOfDownloads] > 0)
			{
				//We have downloads in the queue, so we need to dequeue them with the error
				while ([self numberOfDownloads] > 0)
				{
					CKInternalTransferRecord *download = [[self currentDownload] retain];
					[self dequeueDownload];
					
					[[self client] downloadDidFinish:[download remotePath] error:error];
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
				}
			}
			
			break;
		}
		case NSStreamEventEndEncountered:
		{
			myStreamFlags.readOpen = NO;
			KTLog(CKInputStreamDomain, KTLogDebug, @"Command receive stream ended");
			[self closeStreams];
			[self setState:CKConnectionNotConnectedState];
			
            [[self client] connectionDidDisconnectFromHost:[[[self request] URL] host]];
			
			[self receiveStreamDidClose];
			break;
		}
		case NSStreamEventNone:
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
			
			KTLog(CKOutputStreamDomain, KTLogDebug, @"Command send stream opened");
			
			break;
		}
		case NSStreamEventErrorOccurred:
		{
			KTLog(CKOutputStreamDomain, KTLogError, @"send stream error: %@", [_receiveStream streamError]);
			
			NSError *error = nil;
			
			if (GET_STATE == CKConnectionNotConnectedState) 
			{
				error = [NSError errorWithDomain:CKConnectionErrorDomain
											code:CKConnectionStreamError
										userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%@ %@?", LocalizedStringInConnectionKitBundle(@"Is the service running on the server", @"Stream Error before opening"), [[[self request] URL] host]], NSLocalizedDescriptionKey, [[[self request] URL] host], ConnectionHostKey, nil]];
			}
			else 
			{
				// we want to catch the connection reset by peer error
				error = [_sendStream streamError];
				if ([[error domain] isEqualToString:NSPOSIXErrorDomain] && ([error code] == ECONNRESET || [error code] == EPIPE))
				{
					KTLog(CKTransportDomain, KTLogInfo, @"Connection was reset by peer/broken pipe, attempting to reconnect.", [_sendStream streamError]);
					error = nil;
					
					// resetup connection again
					[self closeStreams];
					[self setState:CKConnectionNotConnectedState];
					
					// roll back to the first command in this chain of commands
					NSArray *cmds = [[self lastCommand] sequencedChain];
					NSEnumerator *e = [cmds reverseObjectEnumerator];
					CKConnectionCommand *cur;
					
					while (cur = [e nextObject])
					{
						[self pushCommandOnCommandQueue:cur];
					}
					
					NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(openStreamsToPort:)
																	  target:self
																   arguments:[NSArray array]];
					int port = [self port];
					[inv setArgument:&port atIndex:2];
					[inv performSelector:@selector(invoke) onThread:_createdThread withObject:nil waitUntilDone:NO];
					
					while (_sendStream == nil || _receiveStream == nil)
					{
						[NSThread sleepUntilDate:[NSDate distantPast]];
					}
					
					[self scheduleStreamsOnRunLoop];
					break;
				}
			}
			
			if (!myStreamFlags.reportedError) 
			{
				myStreamFlags.reportedError = YES;
				[[self client] connectionDidReceiveError:error];
			}
			break;
		}
		case NSStreamEventEndEncountered:
		{
			myStreamFlags.sendOpen = NO;
			KTLog(CKOutputStreamDomain, KTLogDebug, @"Command send stream ended");
			[self closeStreams];
			[self setState:CKConnectionNotConnectedState];
			
            [[self client] connectionDidDisconnectFromHost:[[[self request] URL] host]];
			
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
			KTLog(CKOutputStreamDomain, KTLogError, @"Composite Event Code!  Need to deal with this!");
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
		KTLog(CKTransportDomain, KTLogError, @"StreamBasedConnection: unknown stream (%@)", stream);
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
		KTLog(CKSSLDomain, KTLogFatal, @"Unable to get default keychain");
	}
	
	if (SecIdentitySearchCreate(keychainRef, CSSM_KEYUSE_SIGN, &searchRef))
	{
		KTLog(CKSSLDomain, KTLogFatal, @"Unable to create keychain search");
	}
	
	if (SecIdentitySearchCopyNext(searchRef, &mySSLIdentity))
	{
		KTLog(CKSSLDomain, KTLogFatal, @"Unable to get next search result");
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
		NSError *err = [NSError errorWithDomain:SSLErrorDomain code:1 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"SSL Error Occurred", NSLocalizedDescriptionKey, [[[self request] URL] host], ConnectionHostKey, nil]];
		[[self client] connectionDidReceiveError:err];
		
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
			KTLog(CKSSLDomain, KTLogError, @"Error creating new context");
			return ret;
		}
		
		if (ret = SSLSetIOFuncs(mySSLContext, SSLReadFunction, SSLWriteFunction))
		{
			KTLog(CKSSLDomain, KTLogError, @"Error setting IO Functions");
			return ret;
		}
		
		if (ret = SSLSetConnection(mySSLContext, self))
		{
			KTLog(CKSSLDomain, KTLogError, @"Error setting connection");
			return ret;
		}
		
		// we need to manually verify the certificates so that if they aren't valid, the connection isn't terminated straight away
		if (ret = SSLSetEnableCertVerify(mySSLContext, (Boolean)NO))
		{
			KTLog(CKSSLDomain, KTLogError, @"Error calling SSLSetEnableCertVerify");
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
				KTLog(CKSSLDomain, KTLogError, @"Error setting certificates: %d", ret);
				return ret;
			}
			else
			{
				KTLog(CKSSLDomain, KTLogDebug, @"Set up certificates successfully");
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
			KTLog(CKSSLDomain, KTLogFatal, @"Error in SSLRead: %d", ret);
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
	return [(CKStreamBasedConnection *)connection handleSSLReadToData:data size:dataLength];
}

OSStatus SSLWriteFunction(SSLConnectionRef connection, const void *data, size_t *dataLength)
{
	OSStatus result = [(CKStreamBasedConnection *)connection handleSSLWriteFromData:data size:dataLength];
	// give the runloop a run after writing to have an opportunity to read
	CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1, (Boolean)YES);
	return result;
}

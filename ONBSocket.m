// This code derives from Aaron Jacobs's OneButton Socket, which was
// at the time of writing normally licensed under the terms of the
// GNU General Public License.  You can find the "standard" version
// in the CVS repository of OneButton FTP (www.onebutton.org).
//
// The SPECIFIC INCARNATION of OneButton Socket upon which this
// code is based was specially distributed to Greg Hulands on 2006-01-05
// under the terms of a modified BSD-style license rather than the GPL.
// This does not indicate that any other version of OneButton Socket
// is or will be distributed under any license but the GPL.

/*
 * Copyright (c) 2005, Aaron Jacobs.
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above two paragraph
 *       note about licensing of OneButton Socket, the above copyright notice,
 *       this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of Aaron Jacobs nor the names of OneButton Socket or
 *       OneButton FTP may be used to endorse or promote products derived from
 *       this software without specific prior written permission from Aaron Jacobs.
 *
 * THIS SOFTWARE IS PROVIDED BY AARON JACOBS "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL AARON JACOBS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
 * OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 * WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */

/*
	Thanks to Dustin Voss and his public domain AsyncSocket class for both
	the inspiration for this class and its method of listening for connections and
	handling communication with a delegate.
*/

#import "ONBSocket.h"
#import "ONBSSLContext.h"
#import "InterThreadMessaging.h"
#import <netinet/in.h>

@interface ONBSocket ( ONBSocketPrivateMethods )

// If the current thread is the main thread, send the given message to the socket thread.  Otherwise
// send the message to the main thread.  Only wait for so long, and if we block for too long
// waiting to send the message then retry later.
- (void)ONB_performSelectorOnOtherThread:(SEL)selector;

- (void)ONB_performSelectorOnOtherThread:(SEL)selector
								withObject:(id)object;

- (void)ONB_performSelectorOnOtherThread:(SEL)selector
								withObject:(id)object1
								withObject:(id)object2;

- (void)ONB_performSelectorOnOtherThread:(SEL)selector
								withObject:(id)object1
								withObject:(id)object2
								withObject:(id)object3;

- (void)ONB_tryToSendMessagesToOtherThread:(id)trash;

@end

@interface ONBSocket ( ONBSocketMainThreadPrivateMethods )

- (void)ONB_didConnect;
- (void)ONB_didReadData:(NSData *)data userInfo:(NSDictionary *)userInfo;
- (void)ONB_didDisconnectWithError:(NSError *)error remainingData:(NSData *)remainingData;
- (void)ONB_didTimeOutForReadWithUserInfo:(NSDictionary *)userInfo;
- (void)ONB_didTimeOutForWriteWithUserInfo:(NSDictionary *)userInfo;
- (void)ONB_setTransferSpeed:(NSNumber *)speed;
- (void)ONB_setReceiveSpeed:(NSNumber *)speed;
- (void)ONB_sslHandshakeSucceeded;
- (void)ONB_sslHandshakeFailedWithError:(NSError *)error;
- (void)ONB_acceptingOnPort:(NSNumber *)port;
- (void)ONB_setLocalHost:(NSString *)host;
- (void)ONB_createNewSocketWithInputStream:(NSInputStream *)inputStream
								outputStream:(NSOutputStream *)outputStream;

- (void)ONB_adoptInputStream:(NSInputStream *)inputStream
				outputStream:(NSOutputStream *)outputStream;

@end

@interface ONBSocket ( ONBSocketSocketThreadPrivateMethods )

// Set up the run loop on the socket thread.
- (void)ONB_startSocketThread:(id)trash;

// Shut down the socket thread.
- (void)ONB_shutDownSocketThread;

- (void)ONB_acceptConnectionsOnPort:(NSNumber *)port;
- (void)ONB_connectToHost:(NSString *)host port:(NSNumber *)port;
- (void)ONB_readDataOfLength:(NSNumber *)length timeout:(NSNumber *)timeout userInfo:(NSDictionary *)userInfo;
- (void)ONB_readDataUntilData:(NSData *)terminator timeout:(NSNumber *)timeout userInfo:(NSDictionary *)userInfo;
- (void)ONB_readAllAvailableDataWithTimeout:(NSNumber *)timeout userInfo:(NSDictionary *)userInfo;
- (void)ONB_writeData:(NSData *)data timeout:(NSNumber *)timeout userInfo:(NSDictionary *)userInfo;
- (void)ONB_enableSSL;
- (void)ONB_setUpInputStream:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream;

// Disconnect and send the given error object to the delegate if they
// respond to the appropriate selector.
- (void)ONB_disconnectWithError:(NSError *)error;

// Time out the read/write described by the timer's userInfo object
- (void)ONB_readTimedOut:(NSTimer *)timeoutTimer;
- (void)ONB_writeTimedOut:(NSTimer *)timeoutTimer;

// Close the streams, remove them from the run loop, and release them
- (void)ONB_cleanUpStreams;

// Add a read request to the queue
- (void)ONB_addReadRequest:(NSMutableDictionary *)readRequest;

// Add a write request to the queue
- (void)ONB_addWriteRequest:(NSDictionary *)writeRequest;

// If appropriate, take some decrypted data and use it to fill
// pending read requests
- (void)ONB_workOnReadRequests:(NSTimer *)timer;

// If appropriate, take some data from the top-most write request, encrypt it,
// and put it on the encrypted write data buffer
- (void)ONB_provideEncryptedData;

// The first read request in the queue has been completed.  Tell the delegate
// and then remove it from the queue.
- (void)ONB_finishedReadRequestWithData:(NSData *)data;

// The first write request in the queue has been completed.  Tell the delegate
// and then remove it from the queue.
- (void)ONB_finishedWriteRequest;

// Add the given encrypted (or raw if SSL is not on) data to the buffer for
// output by the output stream.
- (void)ONB_addDataToEncryptedWriteBuffer:(NSData *)data;

// Add the given encrypted (or raw if SSL is not on) data to the buffer for
// decrypting.
- (void)ONB_addDataToRawDataBuffer:(NSData *)data;

// Add the given decrypted data to the buffer for filling read requests.
- (void)ONB_addDataToDecryptedReadBuffer:(NSData *)data;

// Call this if an error occured while trying to read from the input stream.
- (void)ONB_errorWhileReading;

// Call this if an error occured while trying to write to the output stream.
- (void)ONB_errorWhileWriting;

// Call this if an error occured while trying to perform an SSL handshake.
- (void)ONB_errorDuringHandshake:(int)error;

// Call this if a stream reports an error.
- (void)ONB_errorForStream:(NSStream *)stream;

// Indicate that there is space available for writing on the output stream.
- (void)ONB_outputStreamIsWritable;

// Indicate that there are bytes available for reading on the input stream.
- (void)ONB_inputStreamIsReadable;

// Call this when a stream has finished opening.
- (void)ONB_streamOpenCompleted;

// Call this if a stream reports that its end has been reached.
- (void)ONB_endOfStream:(NSStream *)stream;

// Try to perform an SSL handshake with the other party using any data that has
// come in from the input stream.
- (void)ONB_performHandshake;

// Handle a callback from the CFSocket accepting connects.
- (void)ONB_handleCFSocketCallbackOfType:(CFSocketCallBackType)type
									socket:(CFSocketRef)socket
									address:(NSData *)address
									data:(const void *)data;

// Clean up CFSocket-related objects.
- (void)ONB_cleanUpSockets;

@end

@interface NSData ( ONBDataSearching )

- (NSRange)rangeOfData:(NSData *)data;
- (NSRange)rangeOfData:(NSData *)data range:(NSRange)searchRange;

@end

@implementation NSData ( ONBDataSearching )

- (NSRange)rangeOfData:(NSData *)data
{
	return [self rangeOfData:data range:NSMakeRange(0, [self length])];
}

- (NSRange)rangeOfData:(NSData *)data range:(NSRange)searchRange
{
	const char *big = [self bytes];
	unsigned int bigLength = [self length];
	
	const char *little = [data bytes];
	unsigned int littleLength = [data length];
	
	if ((searchRange.location < 0) || (searchRange.location >= bigLength) ||
		(searchRange.length < 0) || (searchRange.length + searchRange.location > bigLength))
	{
		[NSException raise:NSRangeException
					format:@"Invalid range (%u, %u) for rangeOfData:range:!",
							searchRange.location,
							searchRange.length];
		return NSMakeRange(NSNotFound, 0);
	}
	
	big += searchRange.location;
	bigLength = searchRange.length;

	NSRange range = NSMakeRange(NSNotFound, 0);
	
	if ((! data) || (! littleLength) || (! bigLength) || (littleLength > bigLength))
		return range;
	
	unsigned int bigOffset;
	unsigned int littleOffset;
	for (bigOffset=0; bigOffset<bigLength - littleLength + 1; bigOffset++)
	{
		for (littleOffset=0; littleOffset<littleLength; littleOffset++)
			if (big[bigOffset + littleOffset] != little[littleOffset])
				break;
		
		if (littleOffset == littleLength)
		{
			range.location = bigOffset + searchRange.location;
			range.length = littleLength;
			return range;
		}
	}
	
	return range;
}

@end

void ONB_SocketCallback(CFSocketRef socket,
						CFSocketCallBackType callbackType,
						CFDataRef address,
						const void *data,
						void *info)
{
	ONBSocket *socketObject = (ONBSocket *)info;
	[socketObject ONB_handleCFSocketCallbackOfType:callbackType
											socket:socket
											address:(NSData *)address
											data:data];
}

@implementation ONBSocket

- (id)init
{
	return [self initWithDelegate:nil];
}

- (id)initWithDelegate:(id)delegate
{
	if (! (self = [super init]))
		return nil;
	
	[self setDelegate:delegate];
	
	ONB_toldSocketThreadToShutDown = NO;
	ONB_socketThreadInvocations = [[NSMutableArray alloc] initWithCapacity:20];
	[self setVerifySSLCertificates:YES];
	[self setSSLServerMode:NO];
	[self setSSLIdentity:nil];
	
	ONB_transferSpeed = 0.0;
	ONB_receiveSpeed = 0.0;
	
	// Start up the socket thread and wait for it to set up.
	[NSThread prepareForConnectionInterThreadMessages];
	ONB_mainThread = [[NSThread currentThread] retain];
	ONB_socketThread = nil;
	
	[NSThread detachNewThreadSelector:@selector(ONB_startSocketThread:) toTarget:self withObject:nil];
	while (! ONB_socketThread)
		sched_yield();
		
	return self;
}

- (void)dealloc
{
	[self setDelegate:nil];

	[ONB_mainThread release];
	[ONB_socketThreadInvocations release];
	
	[self ONB_setLocalHost:nil];
	
	[self setSSLIdentity:nil];
	
	[super dealloc];
}

- (oneway void)release
{
	// When we call detachNewThreadSelector:toTarget:withObject: in our initalizer to
	// start up the socket thread, NSThread retains us.  So we need to detect when
	// the NSThread retain in the only retain left and then shut down the socket thread.
	if (([self retainCount] == 2) && (! ONB_toldSocketThreadToShutDown))
	{
		// Prevent us from calling this twice.
		ONB_toldSocketThreadToShutDown = YES;

		if ([[NSThread currentThread] isEqual:ONB_socketThread])
			[self ONB_shutDownSocketThread];
		else
			[self ONB_performSelectorOnOtherThread:@selector(ONB_shutDownSocketThread)];
	}

	[super release];
}

- (id)delegate
{
	return ONB_delegate;
}

- (void)setDelegate:(id)delegate
{
	// The delegate is a weak reference.
	ONB_delegate = delegate;
}

- (void)acceptConnectionsOnPort:(UInt16)port
{
	[self ONB_performSelectorOnOtherThread:@selector(ONB_acceptConnectionsOnPort:)
			withObject:[NSNumber numberWithInt:port]];
}

- (void)connectToHost:(NSString *)host port:(UInt16)port
{
	[self setHost:host port:port];
	[self ONB_performSelectorOnOtherThread:@selector(ONB_connectToHost:port:)
								withObject:host
								withObject:[NSNumber numberWithUnsignedShort:port]];
}

- (void)setHost:(NSString *)host port:(UInt16)port
{
	[_host autorelease];
	_host = [host copy];
	_port = port;
}

- (double)transferSpeed
{
	return ONB_transferSpeed;
}

- (double)receiveSpeed
{
	return ONB_receiveSpeed;
}

- (NSString *)localHost
{
	return ONB_localHost;
}

- (BOOL)verifySSLCertificates
{
	return ONB_verifySSLCertificates;
}

- (void)setVerifySSLCertificates:(BOOL)verifySSLCertificates
{
	ONB_verifySSLCertificates = verifySSLCertificates;
}

- (ONBSSLIdentity *)sslIdentity
{
	return ONB_SSLIdentity;
}

- (void)setSSLIdentity:(ONBSSLIdentity *)sslIdentity
{
	[ONB_SSLIdentity autorelease];
	ONB_SSLIdentity = [sslIdentity retain];
}

- (BOOL)sslServerMode
{
	return ONB_SSLServerMode;
}

- (void)setSSLServerMode:(BOOL)sslServerMode
{
	ONB_SSLServerMode = sslServerMode;
}

// Set up a timer to time out the read if necessary, then construct a read request object and add it
// to the queue.
- (void)readDataOfLength:(unsigned int)length
					timeout:(NSTimeInterval)timeout
					userInfo:(NSDictionary *)userInfo
{
	[self ONB_performSelectorOnOtherThread:@selector(ONB_readDataOfLength:timeout:userInfo:)
								withObject:[NSNumber numberWithUnsignedInt:length]
								withObject:[NSNumber numberWithDouble:timeout]
								withObject:userInfo];
}

- (void)readUntilData:(NSData *)terminator
				timeout:(NSTimeInterval)timeout
				userInfo:(NSDictionary *)userInfo
{
	[self ONB_performSelectorOnOtherThread:@selector(ONB_readDataUntilData:timeout:userInfo:)
								withObject:[NSData dataWithData:terminator]
								withObject:[NSNumber numberWithDouble:timeout]
								withObject:userInfo];
}

- (void)readAllAvailableDataWithTimeout:(NSTimeInterval)timeout
								userInfo:(NSDictionary *)userInfo
{
	[self ONB_performSelectorOnOtherThread:@selector(ONB_readAllAvailableDataWithTimeout:userInfo:)
								withObject:[NSNumber numberWithDouble:timeout]
								withObject:userInfo];
}

// Set up a timer to time out the write if necessary, then construct a write request object and add it
// to the queue.
- (void)writeData:(NSData *)data
			timeout:(NSTimeInterval)timeout
			userInfo:(NSDictionary *)userInfo
{
	data = [NSData dataWithData:data];
	NSNumber *number = [NSNumber numberWithDouble:timeout];
	[self ONB_performSelectorOnOtherThread:@selector(ONB_writeData:timeout:userInfo:)
								withObject:data
								withObject:number
								withObject:userInfo];
}

- (void)enableSSL
{
	[self ONB_performSelectorOnOtherThread:@selector(ONB_enableSSL)];
}

@end









@implementation ONBSocket ( ONBSocketMainThreadPrivateMethods )

- (void)ONB_didConnect
{
	id delegate = [self delegate];
	if ([delegate respondsToSelector:@selector(socketDidConnect:)])
		[delegate socketDidConnect:self];
}

- (void)ONB_didReadData:(NSData *)data userInfo:(NSDictionary *)userInfo
{
	id delegate = [self delegate];
	if ([delegate respondsToSelector:@selector(socket:didReadData:userInfo:)])
		[delegate socket:self didReadData:data userInfo:userInfo];
}

- (void)ONB_didDisconnectWithError:(NSError *)error remainingData:(NSData *)remainingData
{
	id delegate = [self delegate];
	if ([delegate respondsToSelector:@selector(socket:didDisconnectWithError:remainingData:)])
		[delegate socket:self didDisconnectWithError:error remainingData:remainingData];
}

- (void)ONB_didTimeOutForReadWithUserInfo:(NSDictionary *)userInfo
{
	id delegate = [self delegate];
	if ([delegate respondsToSelector:@selector(socket:didTimeOutForReadWithUserInfo:)])
		[delegate socket:self didTimeOutForReadWithUserInfo:userInfo];
}

- (void)ONB_didTimeOutForWriteWithUserInfo:(NSDictionary *)userInfo
{
	id delegate = [self delegate];
	if ([delegate respondsToSelector:@selector(socket:didTimeOutForWriteWithUserInfo:)])
		[delegate socket:self didTimeOutForWriteWithUserInfo:userInfo];
}

- (void)ONB_sslHandshakeSucceeded
{
	id delegate = [self delegate];
	if ([delegate respondsToSelector:@selector(socketSSLHandshakeSucceeded:)])
		[delegate socketSSLHandshakeSucceeded:self];
}

- (void)ONB_sslHandshakeFailedWithError:(NSError *)error
{
	id delegate = [self delegate];
	if ([delegate respondsToSelector:@selector(socket:sslHandshakeFailedWithError:)])
		[delegate socket:self sslHandshakeFailedWithError:error];
}

- (void)ONB_acceptingOnPort:(NSNumber *)port
{
	id delegate = [self delegate];
	if ([delegate respondsToSelector:@selector(socket:acceptingConnectionsOnPort:)])
		[delegate socket:self acceptingConnectionsOnPort:[port unsignedIntValue]];
}

- (void)ONB_setLocalHost:(NSString *)host
{
	[self willChangeValueForKey:@"localHost"];
	[ONB_localHost autorelease];
	ONB_localHost = [host copy];
	[self didChangeValueForKey:@"localHost"];
}

- (void)ONB_didWriteDataWithUserInfo:(NSDictionary *)userInfo
{
	id delegate = [self delegate];
	if ([delegate respondsToSelector:@selector(socket:didWriteDataWithUserInfo:)])
		[delegate socket:self didWriteDataWithUserInfo:userInfo];	
}

- (void)ONB_setTransferSpeed:(NSNumber *)speed
{
	[self willChangeValueForKey:@"transferSpeed"];
	ONB_transferSpeed = [speed doubleValue];
	[self didChangeValueForKey:@"transferSpeed"];
}

- (void)ONB_setReceiveSpeed:(NSNumber *)speed
{
	[self willChangeValueForKey:@"receiveSpeed"];
	ONB_receiveSpeed = [speed doubleValue];
	[self didChangeValueForKey:@"receiveSpeed"];
}

- (void)ONB_createNewSocketWithInputStream:(NSInputStream *)inputStream
								outputStream:(NSOutputStream *)outputStream
{
	id delegate = [self delegate];
	ONBSocket *newSocket = [[[ONBSocket alloc] initWithDelegate:delegate] autorelease];

	// Give the new socket the same SSL configuration as us.
	[newSocket setVerifySSLCertificates:[self verifySSLCertificates]];
	[newSocket setSSLIdentity:[self sslIdentity]];
	[newSocket setSSLServerMode:[self sslServerMode]];
	
	if ([delegate respondsToSelector:@selector(socket:didAcceptNewSocket:)])
		[delegate socket:self didAcceptNewSocket:newSocket];
	
	[newSocket ONB_adoptInputStream:inputStream outputStream:outputStream];
}

- (void)ONB_adoptInputStream:(NSInputStream *)inputStream
				outputStream:(NSOutputStream *)outputStream
{
	[self ONB_performSelectorOnOtherThread:@selector(ONB_setUpInputStream:outputStream:)
								withObject:inputStream
								withObject:outputStream];
}

@end





@implementation ONBSocket ( ONBSocketSocketThreadPrivateMethods )

- (void)ONB_startSocketThread:(id)trash
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// Initialize all of the objects specific to this thread.
	ONB_mainThreadInvocations = [[NSMutableArray alloc] initWithCapacity:20];
	
	ONB_availableReadTag = 0;
	ONB_availableWriteTag = 0;

	ONB_rawReadData = [[NSMutableData alloc] initWithCapacity:10240];
	ONB_decryptedReadData = [[NSMutableData alloc] initWithCapacity:10240];
	ONB_encryptedWriteData = [[NSMutableData alloc] initWithCapacity:102400];
	ONB_readRequests = [[NSMutableArray alloc] initWithCapacity:5];
	ONB_writeRequests = [[NSMutableArray alloc] initWithCapacity:5];
	
	ONB_handshaking = NO;
	ONB_sslEnabled = NO;

	ONB_streamOpenCount = 0;
	
	ONB_sslContext = [[ONBSSLContext alloc] init];
	
	ONB_acceptSocket = NULL;
	ONB_runLoopSource = NULL;
	
	ONB_inputStream = nil;
	ONB_outputStream = nil;
	
	// Make sure that we recompute read and write speed right away and that the initial speed is close to zero.
	ONB_lastReadSpeedReport.tv_sec = 0;
	ONB_bytesReadSinceLastReadSpeedReport = 0;

	ONB_lastWriteSpeedReport.tv_sec = 0;
	ONB_bytesWrittenSinceLastWriteSpeedReport = 0;

	// Get ready to accept inter-thread messages and then indicate that we are set up.
	[NSThread prepareForConnectionInterThreadMessages];
	ONB_socketThread = [[NSThread currentThread] retain];
	
	// Run the run loop until we are told to shut down.
	ONB_stopRunLoop = NO;
	BOOL isRunning = NO;
	do
	{
		NSDate *endDate = [NSDate dateWithTimeIntervalSinceNow:1.0];
		isRunning = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:endDate];
	} while (isRunning && (! ONB_stopRunLoop));
	
	// Clean up all of the thread-specific stuff.
	[ONB_socketThread release];
	ONB_socketThread = nil;

	// TODO: Clean up main thread invocations
	[ONB_mainThreadInvocations release];
	
	[ONB_rawReadData release];
	[ONB_decryptedReadData release];
	[ONB_encryptedWriteData release];
	[ONB_readRequests release];
	[ONB_writeRequests release];
	
	[ONB_sslContext release];

	[pool release];
}

- (void)ONB_shutDownSocketThread
{
	[self ONB_cleanUpStreams];
	[self ONB_cleanUpSockets];
	
	ONB_stopRunLoop = YES;
}

- (void)ONB_acceptConnectionsOnPort:(NSNumber *)port
{
	struct sockaddr_in nativeAddr =
	{
		/*sin_len*/		sizeof(struct sockaddr_in),
		/*sin_family*/	AF_INET,
		/*sin_port*/	htons ([port intValue]),
		/*sin_addr*/	{ htonl (INADDR_ANY) },
		/*sin_zero*/	{ 0 }
	};
	
	NSData *address = [NSData dataWithBytes:&nativeAddr length:sizeof(nativeAddr)];
	
	CFSocketContext context;
	context.version = 0;
	context.info = self;
	context.retain = nil;
	context.release = nil;
	context.copyDescription = nil;
	
	ONB_acceptSocket = CFSocketCreate(kCFAllocatorDefault,
										AF_INET,
										SOCK_STREAM,
										0,
										kCFSocketAcceptCallBack,
										(CFSocketCallBack)&ONB_SocketCallback,
										&context);
	ONB_runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, ONB_acceptSocket, 0);
	CFRunLoopRef runLoop = CFRunLoopGetCurrent();
	CFRunLoopAddSource(runLoop, ONB_runLoopSource, kCFRunLoopDefaultMode);

	// Set the SO_REUSEADDR flag.
	int reuseOn = 1;
	setsockopt(CFSocketGetNative(ONB_acceptSocket), SOL_SOCKET, SO_REUSEADDR, &reuseOn, sizeof(int));
	
	CFSocketSetAddress(ONB_acceptSocket, (CFDataRef)address);

	// Find out on what port we are now listening.
	CFSocketNativeHandle native = CFSocketGetNative(ONB_acceptSocket);
	struct sockaddr_in addressStruct;
	socklen_t length = sizeof(struct sockaddr_in);
	if (getsockname(native, (struct sockaddr *)&addressStruct, &length) == -1)
		return;

	unsigned int actualPort = addressStruct.sin_port;
	[self ONB_performSelectorOnOtherThread:@selector(ONB_acceptingOnPort:)
								withObject:[NSNumber numberWithUnsignedInt:actualPort]];
}

- (void)ONB_connectToHost:(NSString *)host port:(NSNumber *)port
{
	CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
										(CFStringRef)host,
										[port unsignedShortValue],
										(CFReadStreamRef *)&ONB_inputStream,
										(CFWriteStreamRef *)&ONB_outputStream);		// "Ownership follows the Create Rule."

	// Make sure that the streams close the underlying socket when they are closed.
	CFReadStreamSetProperty((CFReadStreamRef) ONB_inputStream,
								kCFStreamPropertyShouldCloseNativeSocket,
								kCFBooleanTrue);

	CFWriteStreamSetProperty((CFWriteStreamRef) ONB_outputStream,
								kCFStreamPropertyShouldCloseNativeSocket,
								kCFBooleanTrue);
	
	[ONB_inputStream setDelegate:self];
	[ONB_outputStream setDelegate:self];
	
	NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
	[ONB_inputStream scheduleInRunLoop:currentRunLoop forMode:NSDefaultRunLoopMode];
	[ONB_outputStream scheduleInRunLoop:currentRunLoop forMode:NSDefaultRunLoopMode];
	
	[ONB_inputStream open];
	[ONB_outputStream open];
}

- (void)ONB_readDataOfLength:(NSNumber *)length timeout:(NSNumber *)timeout userInfo:(NSDictionary *)userInfo
{
	NSNumber *readTag = [NSNumber numberWithUnsignedInt:ONB_availableReadTag++];
	
	NSMutableDictionary *readRequest = [NSMutableDictionary dictionaryWithObjectsAndKeys:length,
																						@"terminator",
																						readTag,
																						@"readTag",
																						userInfo,
																						@"userInfo",
																						nil];
	
	if ([timeout doubleValue] > 0)
	{
		// Create a timeout timer for this read
		NSDictionary *timerUserInfo = [NSDictionary dictionaryWithObject:readTag forKey:@"readTag"];
		NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:[timeout doubleValue]
															target:self
															selector:@selector(ONB_readTimedOut:)
															userInfo:timerUserInfo
															repeats:NO];

		[readRequest setObject:timer forKey:@"timeoutTimer"];
	}
	
	[self ONB_addReadRequest:readRequest];
}

- (void)ONB_readDataUntilData:(NSData *)terminator timeout:(NSNumber *)timeout userInfo:(NSDictionary *)userInfo
{
	NSNumber *readTag = [NSNumber numberWithUnsignedInt:ONB_availableReadTag++];
	
	NSMutableDictionary *readRequest = [NSMutableDictionary dictionaryWithObjectsAndKeys:terminator,
																							@"terminator",
																							readTag,
																							@"readTag",
																							userInfo,
																							@"userInfo",
																							nil];

	if ([timeout doubleValue] > 0)
	{
		// Create a timeout timer for this read
		NSDictionary *timerUserInfo = [NSDictionary dictionaryWithObject:readTag forKey:@"readTag"];
		NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:[timeout doubleValue]
															target:self
															selector:@selector(ONB_readTimedOut:)
															userInfo:timerUserInfo
															repeats:NO];

		[readRequest setObject:timer forKey:@"timeoutTimer"];
	}
	
	[self ONB_addReadRequest:readRequest];
}

- (void)ONB_readAllAvailableDataWithTimeout:(NSNumber *)timeout userInfo:(NSDictionary *)userInfo
{
	NSNumber *readTag = [NSNumber numberWithUnsignedInt:ONB_availableReadTag++];
	
	NSMutableDictionary *readRequest = [NSMutableDictionary dictionaryWithObjectsAndKeys:readTag,
																							@"readTag",
																							userInfo,
																							@"userInfo",
																							nil];

	if ([timeout doubleValue] > 0)
	{
		// Create a timeout timer for this read
		NSDictionary *timerUserInfo = [NSDictionary dictionaryWithObject:readTag forKey:@"readTag"];
		NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:[timeout doubleValue]
															target:self
															selector:@selector(ONB_readTimedOut:)
															userInfo:timerUserInfo
															repeats:NO];

		[readRequest setObject:timer forKey:@"timeoutTimer"];
	}
	
	[self ONB_addReadRequest:readRequest];
}

- (void)ONB_writeData:(NSData *)data timeout:(NSNumber *)timeout userInfo:(NSDictionary *)userInfo
{
	NSNumber *writeTag = [NSNumber numberWithUnsignedInt:ONB_availableWriteTag++];

	NSMutableData *dataContainer = [NSMutableData dataWithData:data];
	NSDictionary *writeRequest = [NSDictionary dictionaryWithObjectsAndKeys:dataContainer,
																			@"remainingData",
																			@"writeRequest",
																			@"type",
																			writeTag,
																			@"writeTag",
																			userInfo,
																			@"userInfo",
																			nil];

	if ([timeout doubleValue] > 0)
	{
		// Create a timeout timer for this write
		NSDictionary *timerUserInfo = [NSDictionary dictionaryWithObject:writeTag forKey:@"writeTag"];
		NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:[timeout doubleValue]
															target:self
															selector:@selector(ONB_writeTimedOut:)
															userInfo:timerUserInfo
															repeats:NO];

		writeRequest = [NSMutableDictionary dictionaryWithDictionary:writeRequest];
		[(NSMutableDictionary *)writeRequest setObject:timer forKey:@"timeoutTimer"];
	}
	
	[self ONB_addWriteRequest:writeRequest];
}

- (void)ONB_enableSSL
{
	// Add an object to the write queue that indicates that we should perform an SSL handshake.
	// We don't try to do it immediately so that that any pending write requests can finish first.
	NSDictionary *writeRequest = [NSDictionary dictionaryWithObject:@"sslHandshake" forKey:@"type"];
	[self ONB_addWriteRequest:writeRequest];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)streamEvent
{
	switch (streamEvent)
	{
		case NSStreamEventHasSpaceAvailable:
			[self ONB_outputStreamIsWritable];
			return;
		
		case NSStreamEventHasBytesAvailable:
			[self ONB_inputStreamIsReadable];
			return;
		
		case NSStreamEventOpenCompleted:
			[self ONB_streamOpenCompleted];
			return;
		
		case NSStreamEventErrorOccurred:
			[self ONB_errorForStream:stream];
			return;
		
		case NSStreamEventEndEncountered:
			[self ONB_endOfStream:stream];
			return;
		
		case NSStreamEventNone:
			return;
		
		default:
		{
			NSNumber *eventCode = [NSNumber numberWithInt:streamEvent];
			NSDictionary *userInfo = [NSDictionary dictionaryWithObject:eventCode forKey:@"streamEvent"];
			
			[self ONB_disconnectWithError:[NSError errorWithDomain:ONBSocketErrorDomain
																code:ONBUnhandledStreamEvent
																userInfo:userInfo]];
			NSLog(@"Unhandled stream event: %u", streamEvent);
		}
		return;
	}
}

- (void)ONB_setUpInputStream:(NSInputStream *)inputStream
				outputStream:(NSOutputStream *)outputStream
{
	ONB_inputStream = [inputStream retain];
	ONB_outputStream = [outputStream retain];

	[ONB_inputStream setDelegate:self];
	[ONB_outputStream setDelegate:self];
	
	NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
	[ONB_inputStream scheduleInRunLoop:currentRunLoop forMode:NSDefaultRunLoopMode];
	[ONB_outputStream scheduleInRunLoop:currentRunLoop forMode:NSDefaultRunLoopMode];
	
	[ONB_inputStream open];
	[ONB_outputStream open];
}

- (void)ONB_addReadRequest:(NSMutableDictionary *)readRequest
{
	[ONB_readRequests addObject:readRequest];
	[self ONB_workOnReadRequests:nil];
}

- (void)ONB_addWriteRequest:(NSDictionary *)writeRequest
{
	[ONB_writeRequests addObject:writeRequest];
	[self ONB_provideEncryptedData];
}

- (void)ONB_performHandshake
{
	NSMutableData *outputData = [NSMutableData data];
	int ret = [ONB_sslContext handshakeWithInputData:ONB_rawReadData outputData:outputData];
	
	if ([outputData length])
		[self ONB_addDataToEncryptedWriteBuffer:outputData];
	
	if (ret < 0)
	{
		[self ONB_errorDuringHandshake:ret];
		return;
	}
	
	if (ret == 1)
	{
		ONB_handshaking = NO;
		ONB_sslEnabled = YES;
		
		[self ONB_performSelectorOnOtherThread:@selector(ONB_sslHandshakeSucceeded)];
		[self ONB_provideEncryptedData];
		return;
	}
	
	// Wait to be called again when more data is retreived.
}

- (void)ONB_provideEncryptedData
{
	// If there's already data on the buffer, don't do anything.
	if ([ONB_encryptedWriteData length])
		return;
	
	// If there's no write request to get data from, don't do anything.
	if (! [ONB_writeRequests count])
		return;
	
	// Don't do anything if we're currently handshaking.
	if (ONB_handshaking)
		return;
	
	// Keep going through the write requests trying to get data until we have
	// either provided some data or run out of write requests to process.
	while ((! [ONB_encryptedWriteData length]) && [ONB_writeRequests count])
	{
		NSDictionary *writeRequest = [ONB_writeRequests objectAtIndex:0];
		NSString *type = [writeRequest objectForKey:@"type"];
		
		if ([type isEqual:@"sslHandshake"])
		{
			ONB_handshaking = YES;
			
			// Remove the sslHandshake write request
			[ONB_writeRequests removeObjectAtIndex:0];
			
			// Give our SSL context the appropriate parameters.
			[ONB_sslContext setVerifySSLCertificates:[self verifySSLCertificates]];
			[ONB_sslContext setSSLIdentity:[self sslIdentity]];
			[ONB_sslContext setSSLServerMode:[self sslServerMode]];
			
			// Put any data we've read recently back onto the raw data buffer, since
			// it should be SSL handshake data.
			[ONB_rawReadData setData:ONB_decryptedReadData];
			[ONB_decryptedReadData setLength:0];

			[self ONB_performHandshake];
			return;
		}
		
		NSMutableData *remainingData = [writeRequest objectForKey:@"remainingData"];
		if (! [remainingData length])
		{
			[self ONB_finishedWriteRequest];
			continue;
		}
		
		NSData *immutableData = [NSData dataWithData:remainingData];
		[remainingData setLength:0];

		if (ONB_sslEnabled)
		{
			NSData *encryptedData = [ONB_sslContext encryptData:immutableData inputData:ONB_rawReadData];
			[self ONB_addDataToEncryptedWriteBuffer:encryptedData];
		}
		else
			[self ONB_addDataToEncryptedWriteBuffer:immutableData];
	}
}

- (void)ONB_finishedWriteRequest
{
	NSDictionary *writeRequest = [ONB_writeRequests objectAtIndex:0];
	[[writeRequest objectForKey:@"timeoutTimer"] invalidate];
	NSDictionary *userInfo = [[[writeRequest objectForKey:@"userInfo"] retain] autorelease];
	[ONB_writeRequests removeObjectAtIndex:0];
	
	[self ONB_performSelectorOnOtherThread:@selector(ONB_didWriteDataWithUserInfo:) withObject:userInfo];
}

- (void)ONB_finishedReadRequestWithData:(NSData *)data
{
	NSDictionary *readRequest = [ONB_readRequests objectAtIndex:0];
	[[readRequest objectForKey:@"timeoutTimer"] invalidate];
	NSDictionary *userInfo = [[[readRequest objectForKey:@"userInfo"] retain] autorelease];
	[ONB_readRequests removeObjectAtIndex:0];

	[self ONB_performSelectorOnOtherThread:@selector(ONB_didReadData:userInfo:)
								withObject:data
								withObject:userInfo];
}

- (void)ONB_workOnReadRequests:(NSTimer *)timer
{
	// If there's no decrypted data, then there's nothing to do.
	if (! [ONB_decryptedReadData length])
		return;
	
	// If there aren't any read requests, then there's also nothing to do.
	if (! [ONB_readRequests count])
		return;
	
	// Keep working as long as we have read requests to fill and we haven't run out
	// of usable data.
	while ([ONB_readRequests count] && [ONB_decryptedReadData length])
	{
		NSMutableDictionary *readRequest = [ONB_readRequests objectAtIndex:0];
		NSObject *terminator = [readRequest objectForKey:@"terminator"];
		
		if ([terminator isKindOfClass:[NSNumber class]])
		{
			unsigned int requestedLength = [(NSNumber *)terminator unsignedIntValue];

			// Are we able to fill the request?
			if (requestedLength <= [ONB_decryptedReadData length])
			{
				NSRange subdataRange = NSMakeRange(0, requestedLength);
				NSData *data = [ONB_decryptedReadData subdataWithRange:subdataRange];
				[ONB_decryptedReadData replaceBytesInRange:subdataRange withBytes:NULL length:0];

				[self ONB_finishedReadRequestWithData:data];
				continue;
			}
			
			// We didn't have enough data to fill the request.
			break;
		}
		
		else if ([terminator isKindOfClass:[NSData class]])
		{
			// We don't need to search the entire decrypted data buffer if we've already
			// searched part of it on a previous pass.
			NSNumber *previouslySearchedNumber = [readRequest objectForKey:@"previouslySearched"];
			unsigned int previouslySearched = (previouslySearchedNumber) ? [previouslySearchedNumber unsignedIntValue] : 0;
			NSRange searchRange = NSMakeRange(previouslySearched, [ONB_decryptedReadData length] - previouslySearched);
			NSRange terminatorRange = [ONB_decryptedReadData rangeOfData:(NSData *)terminator range:searchRange];
			
			unsigned int location = terminatorRange.location;
			unsigned int length = terminatorRange.length;
			
			// If we didn't find the terminator, then we'll have to wait until we get more data to try again.
			if (location == NSNotFound)
			{
				previouslySearched = MAX(0, [ONB_decryptedReadData length] - [(NSData *)terminator length] + 1);
				previouslySearchedNumber = [NSNumber numberWithUnsignedInt:previouslySearched];
				[readRequest setObject:previouslySearchedNumber forKey:@"previouslySearched"];
				break;
			}
			
			// We filled the read request.
			NSRange subdataRange = NSMakeRange(0, location+length);
			NSData *data = [ONB_decryptedReadData subdataWithRange:subdataRange];
			[ONB_decryptedReadData replaceBytesInRange:subdataRange withBytes:NULL length:0];
			
			[self ONB_finishedReadRequestWithData:data];
			continue;
		}

		else if (! terminator)
		{
			// The user wants all available data.
			NSData *availableData = [[ONB_decryptedReadData copy] autorelease];
			[ONB_decryptedReadData setLength:0];
			[self ONB_finishedReadRequestWithData:availableData];
			continue;
		}
	}
}

- (void)ONB_streamOpenCompleted
{
	ONB_streamOpenCount++;
	
	// We must wait for both streams to finish opening before continuing.
	if (ONB_streamOpenCount != 2)
		return;

	// Get the local address from which we are communicating.
	CFSocketNativeHandle native;
	CFDataRef nativeData = CFReadStreamCopyProperty((CFReadStreamRef) ONB_inputStream, kCFStreamPropertySocketNativeHandle);
	if (! nativeData)
		return;
	
	CFDataGetBytes(nativeData, CFRangeMake(0, CFDataGetLength(nativeData)), (UInt8 *)&native);
	CFRelease(nativeData);
	
	struct sockaddr_in tmpaddr;
	socklen_t len = sizeof(struct sockaddr_in);
	if (getsockname(native, (struct sockaddr *)&tmpaddr, &len) == -1)
		return;

	char *hostCString = (char *)inet_ntoa(ntohl(tmpaddr.sin_addr.s_addr));
	NSString *host = [NSString stringWithCString:hostCString];
	[self ONB_performSelectorOnOtherThread:@selector(ONB_setLocalHost:) withObject:host];
	[self ONB_performSelectorOnOtherThread:@selector(ONB_didConnect)];
}

- (void)ONB_inputStreamIsReadable
{
	NSMutableData *data = [NSMutableData dataWithLength:1024];
	uint8_t *buffer = (uint8_t *)[data mutableBytes];
	int ret = [ONB_inputStream read:buffer maxLength:1024];
	
	if (ret < 0)
	{
		[self ONB_errorWhileReading];
		return;
	}
	
	[data setLength:ret];
	[self ONB_addDataToRawDataBuffer:[NSData dataWithData:data]];

	// Record the amount of the read so that we can use it to calculate read speed.
	ONB_bytesReadSinceLastReadSpeedReport += ret;
	
	struct timeval currentTime;
	gettimeofday(&currentTime, NULL);

	double timeSpan = ((double) (currentTime.tv_usec - ONB_lastReadSpeedReport.tv_usec)) / 1000000.0;
	timeSpan += (double) (currentTime.tv_sec - ONB_lastReadSpeedReport.tv_sec);

	if (timeSpan > 1.0)
	{
		// Protect against divide by zero.
		if (! ONB_bytesReadSinceLastReadSpeedReport)
			ONB_bytesReadSinceLastReadSpeedReport = 1;
		
		double speed = ((double) ONB_bytesReadSinceLastReadSpeedReport) / timeSpan;
		[self ONB_performSelectorOnOtherThread:@selector(ONB_setReceiveSpeed:)
									withObject:[NSNumber numberWithDouble:speed]];
		
		gettimeofday(&ONB_lastReadSpeedReport, NULL);
		ONB_bytesReadSinceLastReadSpeedReport = 0;
	}
}

- (void)ONB_cleanUpSockets
{
	if (ONB_acceptSocket)
	{
		CFSocketInvalidate(ONB_acceptSocket);
		CFRelease(ONB_acceptSocket);
		ONB_acceptSocket = NULL;
	}
	if (ONB_runLoopSource)
	{
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), ONB_runLoopSource, kCFRunLoopDefaultMode);
		CFRelease(ONB_runLoopSource);
		ONB_runLoopSource = NULL;
	}	
}

- (void)ONB_addDataToDecryptedReadBuffer:(NSData *)data
{
	[ONB_decryptedReadData appendData:data];
	[self ONB_workOnReadRequests:nil];
}

- (void)ONB_addDataToRawDataBuffer:(NSData *)data
{
	if (ONB_sslEnabled)
	{
		[ONB_rawReadData appendData:data];
		
		NSMutableData *outputData = [NSMutableData data];
		NSData *decryptedData = [ONB_sslContext decryptData:ONB_rawReadData outputData:outputData];
		[self ONB_addDataToDecryptedReadBuffer:decryptedData];
		
		if ([outputData length])
			[self ONB_addDataToEncryptedWriteBuffer:outputData];
		
		return;
	}
	
	if (ONB_handshaking)
	{
		[ONB_rawReadData appendData:data];
		[self ONB_performHandshake];
		return;
	}
	
	// We're not doing anything with SSL, so this shouldn't be encrypted.
	[self ONB_addDataToDecryptedReadBuffer:data];
}

- (void)ONB_outputStreamIsWritable
{
	unsigned int bufferLength = [ONB_encryptedWriteData length];
	
	// If there's no encrypted data to give, try to put some more on the buffer for next time.
	if (! bufferLength)
	{
		[self ONB_provideEncryptedData];
		return;
	}
	
	const uint8_t *buffer = (const uint8_t *)[ONB_encryptedWriteData bytes];
	int ret = [ONB_outputStream write:buffer maxLength:bufferLength];
	
	if (ret < 1)
	{
		[self ONB_errorWhileWriting];
		return;
	}
	
	// Remove the data we wrote from the write buffer.
	[ONB_encryptedWriteData replaceBytesInRange:NSMakeRange(0, ret) withBytes:NULL length:0];
	
	// Record the amount of the write so that we can use it to calculate write speed.
	ONB_bytesWrittenSinceLastWriteSpeedReport += ret;

	struct timeval currentTime;
	gettimeofday(&currentTime, NULL);

	double timeSpan = ((double) (currentTime.tv_usec - ONB_lastWriteSpeedReport.tv_usec)) / 1000000.0;
	timeSpan += (double) (currentTime.tv_sec - ONB_lastWriteSpeedReport.tv_sec);

	if (timeSpan > 1.0)
	{
		// Protect against divide by zero.
		if (! ONB_bytesWrittenSinceLastWriteSpeedReport)
			ONB_bytesWrittenSinceLastWriteSpeedReport = 1;
		
		double speed = ((double) ONB_bytesWrittenSinceLastWriteSpeedReport) / timeSpan;
		[self ONB_performSelectorOnOtherThread:@selector(ONB_setTransferSpeed:)
									withObject:[NSNumber numberWithDouble:speed]];

		gettimeofday(&ONB_lastWriteSpeedReport, NULL);
		ONB_bytesWrittenSinceLastWriteSpeedReport = 0;
	}
}

- (void)ONB_addDataToEncryptedWriteBuffer:(NSData *)data
{
	[ONB_encryptedWriteData appendData:data];
	
	if ([ONB_encryptedWriteData length] && [ONB_outputStream hasSpaceAvailable])
		[self ONB_outputStreamIsWritable];
}

- (void)ONB_errorDuringHandshake:(int)error
{
	[self ONB_performSelectorOnOtherThread:@selector(ONB_sslHandshakeFailedWithError:)
								withObject:[NSError errorWithDomain:ONBSocketSSLErrorDomain
																code:error
																userInfo:nil]];
	NSLog(@"Error during handshake: %d", error);
}

- (void)ONB_handleCFSocketCallbackOfType:(CFSocketCallBackType)type
									socket:(CFSocketRef)socket
									address:(NSData *)address
									data:(const void *)data
{
	// A new connection has been accepted by our accepting socket.
	CFSocketNativeHandle nativeHandle = *((CFSocketNativeHandle *)data);
		
	// Create the streams for the new socket.
	NSInputStream *inputStream;
	NSOutputStream *outputStream;
	
	CFStreamCreatePairWithSocket(kCFAllocatorDefault,
									nativeHandle,
									(CFReadStreamRef *)&inputStream,
									(CFWriteStreamRef *)&outputStream);		// "Ownership follows the Create Rule."
	[inputStream autorelease];
	[outputStream autorelease];

	// Make sure that the streams close the underlying socket when they are closed.
	CFReadStreamSetProperty((CFReadStreamRef) inputStream,
								kCFStreamPropertyShouldCloseNativeSocket,
								kCFBooleanTrue);

	CFWriteStreamSetProperty((CFWriteStreamRef) outputStream,
								kCFStreamPropertyShouldCloseNativeSocket,
								kCFBooleanTrue);
	
	[self ONB_performSelectorOnOtherThread:@selector(ONB_createNewSocketWithInputStream:outputStream:)
								withObject:[inputStream autorelease]
								withObject:[outputStream autorelease]];
}

- (void)ONB_cleanUpStreams
{
	NSRunLoop *runLoop = [NSRunLoop currentRunLoop];

	if (ONB_inputStream)
	{
		[ONB_inputStream close];
		[ONB_inputStream removeFromRunLoop:runLoop forMode:NSDefaultRunLoopMode];
		[ONB_inputStream release];
		ONB_inputStream = nil;
	}
	
	if (ONB_outputStream)
	{
		[ONB_outputStream close];
		[ONB_outputStream removeFromRunLoop:runLoop forMode:NSDefaultRunLoopMode];
		[ONB_outputStream release];
		ONB_outputStream = nil;
	}
}

- (void)ONB_disconnectWithError:(NSError *)error
{
	// Get whatever data is left on the read stream.
	while ([ONB_inputStream hasBytesAvailable])
	{
		NSLog(@"Getting remaining bytes");
		[self ONB_inputStreamIsReadable];
	}

	[self ONB_cleanUpSockets];
	[self ONB_cleanUpStreams];
	
	NSData *remainingData = [[ONB_decryptedReadData copy] autorelease];
	[ONB_decryptedReadData setLength:0];
	
	[self ONB_performSelectorOnOtherThread:@selector(ONB_didDisconnectWithError:remainingData:)
								withObject:error
								withObject:remainingData];
}

- (void)ONB_endOfStream:(NSStream *)stream
{
	[self ONB_disconnectWithError:[NSError errorWithDomain:ONBSocketErrorDomain
														code:ONBConnectionClosed
														userInfo:nil]];
}

- (void)ONB_errorForStream:(NSStream *)stream
{
	[self ONB_disconnectWithError:[stream streamError]];
}

- (void)ONB_errorWhileWriting
{
	[self ONB_disconnectWithError:[ONB_outputStream streamError]];
}

- (void)ONB_errorWhileReading
{
	[self ONB_disconnectWithError:[ONB_inputStream streamError]];
}

- (void)ONB_writeTimedOut:(NSTimer *)timeoutTimer
{
	NSNumber *writeTag = [[timeoutTimer userInfo] objectForKey:@"writeTag"];
	NSEnumerator *writeRequestEnumerator = [ONB_writeRequests objectEnumerator];
	NSDictionary *currentWriteRequest;
	
	while (currentWriteRequest = [writeRequestEnumerator nextObject])
		if ([[currentWriteRequest objectForKey:@"writeTag"] isEqualToNumber:writeTag])
		{
			NSDictionary *userInfo = [[[currentWriteRequest objectForKey:@"userInfo"] retain] autorelease];
			[ONB_writeRequests removeObject:currentWriteRequest];

			[self ONB_performSelectorOnOtherThread:@selector(ONB_didTimeOutForWriteWithUserInfo:)
										withObject:userInfo];
			break;
		}
}

- (void)ONB_readTimedOut:(NSTimer *)timeoutTimer
{
	NSNumber *readTag = [[timeoutTimer userInfo] objectForKey:@"readTag"];
	NSEnumerator *readRequestEnumerator = [ONB_readRequests objectEnumerator];
	NSDictionary *currentReadRequest;
	
	while (currentReadRequest = [readRequestEnumerator nextObject])
		if ([[currentReadRequest objectForKey:@"readTag"] isEqualToNumber:readTag])
		{
			NSDictionary *userInfo = [[[currentReadRequest objectForKey:@"userInfo"] retain] autorelease];
			[ONB_readRequests removeObject:currentReadRequest];

			[self ONB_performSelectorOnOtherThread:@selector(ONB_didTimeOutForReadWithUserInfo:)
										withObject:userInfo];
			break;
		}
}

@end




@implementation ONBSocket ( ONBSocketPrivateMethods )

- (void)ONB_performSelectorOnOtherThread:(SEL)selector
{
	SEL interthreadSelector = @selector(performSelector:inThread:beforeDate:);
	NSMethodSignature *signature = [self methodSignatureForSelector:interthreadSelector];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
	
	BOOL onMainThread = [[NSThread currentThread] isEqual:ONB_mainThread];
	NSThread *thread = onMainThread ? ONB_socketThread : ONB_mainThread;
	NSMutableArray *array = onMainThread ? ONB_socketThreadInvocations : ONB_mainThreadInvocations;

	[invocation setTarget:self];
	[invocation setSelector:interthreadSelector];
	[invocation setArgument:&selector atIndex:2];
	[invocation setArgument:&thread atIndex:3];
	
	[array addObject:invocation];
	[self ONB_tryToSendMessagesToOtherThread:nil];
}

- (void)ONB_performSelectorOnOtherThread:(SEL)selector
								withObject:(id)object
{
	// Retain the argument(s) - they will be released when the invocation is invoked.
	object = [object retain];

	SEL interthreadSelector = @selector(performSelector:withObject:inThread:beforeDate:);
	NSMethodSignature *signature = [self methodSignatureForSelector:interthreadSelector];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
	
	BOOL onMainThread = [[NSThread currentThread] isEqual:ONB_mainThread];
	NSThread *thread = onMainThread ? ONB_socketThread : ONB_mainThread;
	NSMutableArray *array = onMainThread ? ONB_socketThreadInvocations : ONB_mainThreadInvocations;

	[invocation setTarget:self];
	[invocation setSelector:interthreadSelector];
	[invocation setArgument:&selector atIndex:2];
	[invocation setArgument:&object atIndex:3];
	[invocation setArgument:&thread atIndex:4];
	
	[array addObject:invocation];
	[self ONB_tryToSendMessagesToOtherThread:nil];
}

- (void)ONB_performSelectorOnOtherThread:(SEL)selector
								withObject:(id)object1
								withObject:(id)object2
{
	// Retain the argument(s) - they will be released when the invocation is invoked.
	object1 = [object1 retain];
	object2 = [object2 retain];

	SEL interthreadSelector = @selector(performSelector:withObject:withObject:inThread:beforeDate:);
	NSMethodSignature *signature = [self methodSignatureForSelector:interthreadSelector];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
	
	BOOL onMainThread = [[NSThread currentThread] isEqual:ONB_mainThread];
	NSThread *thread = onMainThread ? ONB_socketThread : ONB_mainThread;
	NSMutableArray *array = onMainThread ? ONB_socketThreadInvocations : ONB_mainThreadInvocations;

	[invocation setTarget:self];
	[invocation setSelector:interthreadSelector];
	[invocation setArgument:&selector atIndex:2];
	[invocation setArgument:&object1 atIndex:3];
	[invocation setArgument:&object2 atIndex:4];
	[invocation setArgument:&thread atIndex:5];
	
	[array addObject:invocation];
	[self ONB_tryToSendMessagesToOtherThread:nil];
}

- (void)ONB_performSelectorOnOtherThread:(SEL)selector
								withObject:(id)object1
								withObject:(id)object2
								withObject:(id)object3
{
	// Retain the argument(s) - they will be released when the invocation is invoked.
	object1 = [object1 retain];
	object2 = [object2 retain];
	object3 = [object3 retain];

	SEL interthreadSelector = @selector(performSelector:withObject:withObject:withObject:inThread:beforeDate:);
	NSMethodSignature *signature = [self methodSignatureForSelector:interthreadSelector];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
	
	BOOL onMainThread = [[NSThread currentThread] isEqual:ONB_mainThread];
	NSThread *thread = onMainThread ? ONB_socketThread : ONB_mainThread;
	NSMutableArray *array = onMainThread ? ONB_socketThreadInvocations : ONB_mainThreadInvocations;

	[invocation setTarget:self];
	[invocation setSelector:interthreadSelector];
	[invocation setArgument:&selector atIndex:2];
	[invocation setArgument:&object1 atIndex:3];
	[invocation setArgument:&object2 atIndex:4];
	[invocation setArgument:&object3 atIndex:5];
	[invocation setArgument:&thread atIndex:6];
	
	[array addObject:invocation];
	[self ONB_tryToSendMessagesToOtherThread:nil];
}

- (void)ONB_tryToSendMessagesToOtherThread:(id)trash
{
	BOOL onMainThread = [[NSThread currentThread] isEqual:ONB_mainThread];
	NSMutableArray *array = onMainThread ? ONB_socketThreadInvocations : ONB_mainThreadInvocations;
	if (! [array count])
		return;
	
	NSInvocation *invocation = [array objectAtIndex:0];
	NSMethodSignature *signature = [invocation methodSignature];
	unsigned int argumentCount = [signature numberOfArguments];

	NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:0.01];
	[invocation setArgument:&timeoutDate atIndex:argumentCount-1];
	BOOL messageSent = YES;
	
	@try
	{
		[invocation invoke];
	}
	@catch (NSException *exception)
	{
		messageSent = NO;
		SEL selector;
		[invocation getArgument:&selector atIndex:2];
		NSLog(@"Rescheduling %@", NSStringFromSelector(selector));
		if (! [[exception name] isEqualToString:NSPortTimeoutException])
			@throw exception;
	}
	
	if (messageSent)
	{
		unsigned int i;
		for (i=3; i<argumentCount-2; i++)
		{
			id argument;
			[invocation getArgument:&argument atIndex:i];
			[argument release];
		}

		[array removeObjectAtIndex:0];
	}
	else
		[self performSelector:@selector(ONB_tryToSendMessagesToOtherThread:)
					withObject:nil
					afterDelay:0.01];
}

#pragma mark -
#pragma mark Input/Output Stream Protocol Methods

- (void)open
{
	/*[self ONB_performSelectorOnOtherThread:@selector(ONB_connectToHost:port:)
								withObject:host
								withObject:[NSNumber numberWithUnsignedShort:port]];*/
}

- (void)close
{
	
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key
{
	
}

- (id)propertyForKey:(NSString *)key
{
	
}

- (NSError *)streamError
{
	
}

- (NSStreamStatus)streamStatus
{
	
}

- (int)read:(uint8_t *)buffer maxLength:(unsigned int)len
{
	
}

- (int)write:(const uint8_t *)buffer maxLength:(unsigned int)len
{
	
}

@end
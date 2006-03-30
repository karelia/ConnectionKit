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
#import "InterThreadMessaging.h"
#import "RunLoopForwarder.h"
#import <sys/types.h> 
#import <sys/socket.h> 
#import <netinet/in.h>

const unsigned int kStreamChunkSize = 2048;
NSString *StreamBasedErrorDomain = @"StreamBasedErrorDomain"
;
@interface StreamBasedConnection (Private)
- (void)checkQueue;
@end

@implementation StreamBasedConnection

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
{
	[super initWithHost:host port:port username:username password:password];
	
	_port = [[NSPort port] retain];
	_forwarder = [[RunLoopForwarder alloc] init];
	[_forwarder setReturnValueDelegate:self];
	_mainThread = [NSThread currentThread];
	_sendBufferLock = [[NSLock alloc] init];
	_sendBuffer = [[NSMutableData data] retain];
	_fileCheckingLock = [[NSConditionLock alloc] init];
	
	[_port setDelegate:self];
	[NSThread prepareForInterThreadMessages];
	[NSThread detachNewThreadSelector:@selector(runBackgroundThread:)
							 toTarget:self
						   withObject:nil];
	
	return self;
}

- (void)dealloc
{
	[self sendPortMessage:KILL_THREAD];
	[_port setDelegate:nil];
    [_port release];
	
	[self closeStreams];
	[_port setDelegate:nil];
	[_port release];
	[_forwarder release];
	[_sendStream release];
	[_receiveStream release];
	[_sendBufferLock release];
	[_sendBuffer release];
	[_fileCheckingConnection release];
	[_fileCheckingLock release];
	
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

- (unsigned)localPort
{
	CFSocketNativeHandle native;
	CFDataRef nativeProp = CFReadStreamCopyProperty ((CFReadStreamRef)_receiveStream, kCFStreamPropertySocketNativeHandle);
	if (nativeProp == NULL)
	{
		return -1;
	}
	CFDataGetBytes (nativeProp, CFRangeMake(0, CFDataGetLength(nativeProp)), (UInt8 *)&native);
	CFRelease (nativeProp);
	struct sockaddr sock;
	socklen_t len = sizeof(sock);
	
	if (getsockname(native, &sock, &len) >= 0) {
		return ntohs(((struct sockaddr_in *)&sock)->sin_port);
	}
	
	return native;
}

#pragma mark -
#pragma mark Threading Support

- (void)runloopForwarder:(RunLoopForwarder *)rlw returnedValue:(void *)value 
{
	//by default we do nothing, subclasses are implementation specific based on their current state
}

/*!	The main background thread loop.  It runs continuously whether connected or not.
*/
- (void)runBackgroundThread:(id)notUsed
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[NSThread prepareForInterThreadMessages];
// NOTE: this may be leaking ... there are two retains going on here.  Apple bug report #2885852, still open after TWO YEARS!
// But then again, we can't remove the thread, so it really doesn't mean much.
	[[NSRunLoop currentRunLoop] addPort:_port forMode:(NSString *)kCFRunLoopCommonModes];
	[[NSRunLoop currentRunLoop] run];
	
	[pool release];
}

- (void)sendPortMessage:(int)aMessage
{
	//NSAssert([NSThread currentThread] == _mainThread, @"must be called from the main thread");
	if (nil != _port)
	{
		NSPortMessage *message
		= [[NSPortMessage alloc] initWithSendPort:_port
									  receivePort:_port components:nil];
		[message setMsgid:aMessage];
		
		@try {
			BOOL sent = [message sendBeforeDate:[NSDate dateWithTimeIntervalSinceNow:15.0]];
			if (!sent)
			{
				if ([AbstractConnection debugEnabled])
					NSLog(@"StreamBasedConnection couldn't send message %d", aMessage);
			}
		} @catch (NSException *ex) {
			NSLog(@"%@", ex);
		} @finally {
			[message release];
		} 
	}
}

/*" NSPortDelegate method gets called in the background thread.
"*/
- (void)handlePortMessage:(NSPortMessage *)portMessage
{
    int message = [portMessage msgid];
	
	switch (message)
	{
		case CONNECT:
		{
			[_receiveStream setDelegate:self];
			[_sendStream setDelegate:self];
			
			[_receiveStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
			[_sendStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
			
			[_receiveStream open];
			[_sendStream open];
			break;
		}
		case COMMAND:
		{
			[self checkQueue];
			break;
		}
		case ABORT:
			break;
			
		case DISCONNECT:
			break;
			
		case FORCE_DISCONNECT:
			break;
		case KILL_THREAD:
		{
			[[NSRunLoop currentRunLoop] removePort:_port forMode:(NSString *)kCFRunLoopCommonModes];
			break;
		}
	}
}

#pragma mark -
#pragma mark Queue Support

- (void)endBulkCommands
{
	[super endBulkCommands];
	[self sendPortMessage:COMMAND];
}

- (void)queueCommand:(id)command
{
	[super queueCommand:command];
	
	if (!_flags.inBulk) {
		if ([NSThread currentThread] == _mainThread)
		{
			[self sendPortMessage:COMMAND];		// State has changed, check if we can handle message.
		}
		else
		{
			[self checkQueue];	// in background thread, just check the queue now for anything to do
		}
	}
}


- (void)sendCommand:(id)command
{
	// Subclasses handle this
}

- (void)setState:(int)aState		// Safe "setter" -- do NOT just change raw variable.  Called by EITHER thread.
{
	if ([AbstractConnection logStateChanges]) 
		NSLog(@"Changing State from %@ to %@", [self stateName:_state], [self stateName:aState]);
	
    [super setState:aState];
	
	if ([NSThread currentThread] == _mainThread)
	{
		[self sendPortMessage:COMMAND];		// State has changed, check if we can handle message.
	}
	else
	{
		[self checkQueue];	// in background thread, just check the queue now for anything to do
	}
}

- (void)checkQueue
{
	if ([AbstractConnection logStateChanges])
		NSLog(@"Checking Queue");
	BOOL nextTry = 0 != [self numberOfCommands];
	while (nextTry)
	{
		ConnectionCommand *command = [self currentCommand];
		if (GET_STATE == [command awaitState])
		{
			[self sendCommand:[command command]];
			
			_state = [command sentState];	// don't use setter; we don't want to recurse
			[_commandHistory insertObject:command atIndex:0];
			[self dequeueCommand];
			nextTry = (0 != [_commandQueue count]);		// go to next one, there's something else to do
		}
		else
		{
			if ([AbstractConnection logStateChanges])
				NSLog(@"State %@ not ready for command at top of queue: %@, needs %@", [self stateName:GET_STATE], [command command], [self stateName:[command awaitState]]);
			nextTry = NO;		// don't try.  
		}
	}
	if ([self numberOfFileChecks] > 0) {
		NSString *fileToCheck = [self currentFileCheck];
		[_fileCheckingConnection contentsOfDirectory:[fileToCheck stringByDeletingLastPathComponent]];
	}
}	

#pragma mark -
#pragma mark AbstractConnection Overrides

- (void)setDelegate:(id)delegate
{
	[super setDelegate:delegate];
	// Also tell the forwarder to use this delegate.
	[_forwarder setDelegate:delegate];	// note that its delegate it not retained.
}

- (void)connect
{
	[self emptyCommandQueue];
	
	NSHost *host = [NSHost hostWithName:_connectionHost];
	if(!host){
		if ([AbstractConnection debugEnabled])
			NSLog(@"Cannot find the host: %@", _connectionHost);
		
        if (_flags.error) {
			NSError *error = [NSError errorWithDomain:ConnectionErrorDomain 
												 code:EHOSTUNREACH
											 userInfo:
				[NSDictionary dictionaryWithObjectsAndKeys: @"Host Unavailable", NSLocalizedDescriptionKey,
					_connectionHost, @"host", nil]];
            [_forwarder connection:self didReceiveError:error];
		}
		
		
		return;
	}
	/* If the host has multiple names it can screw up the order in the list of name */
	if ([[host names] count] > 1) {
#warning Applying KVC hack
		[host setValue:[NSArray arrayWithObject:_connectionHost] forKey:@"names"];
	}
	
	int connectionPort = [_connectionPort intValue];
	if (0 == connectionPort)
	{
		connectionPort = 21;	// standard FTP control port
	}
	[self closeStreams];		// make sure streams are closed before opening/allocating new ones
	
	[NSStream getStreamsToHost:host
						  port:connectionPort
				   inputStream:&_receiveStream
				  outputStream:&_sendStream];
	
	[_receiveStream retain];	// the above objects are created autorelease; we have to retain them
	[_sendStream retain];
	
	if(!_receiveStream && _sendStream){
		if ([AbstractConnection debugEnabled])
			NSLog(@"Cannot create a stream for the host: %@", _connectionHost);
		
		if (_flags.error) {
			NSError *error = [NSError errorWithDomain:ConnectionErrorDomain 
												 code:EHOSTUNREACH
											 userInfo:[NSDictionary dictionaryWithObject:@"FTP Stream Unavailable"
																				  forKey:NSLocalizedDescriptionKey]];
			[_forwarder connection:self didReceiveError:error];
		}
		return;
	}
	[self sendPortMessage:CONNECT];	// finish the job -- scheduling in the runloop -- in the background thread
}

/*!	Disconnect from host.  Called by foreground thread.
*/
- (void)disconnect
{
	[self sendPortMessage:DISCONNECT];
	[_fileCheckingConnection disconnect];
}

- (void)forceDisconnect
{
	[self sendPortMessage:FORCE_DISCONNECT];
	[_fileCheckingConnection forceDisconnect];
}

#pragma mark -
#pragma mark Stream Delegate Methods

- (void)closeStreams
{
	[_receiveStream close];
	[_sendStream close];
	[_receiveStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_sendStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_receiveStream release];
	[_sendStream release];
	_receiveStream = nil;
	_sendStream = nil;
}

- (void)processReceivedData:(NSData *)data
{
	// we do nothing. subclass has to do the work.
}

- (NSData *)availableData
{
	uint8_t *buf = (uint8_t *)malloc(sizeof(uint8_t) * kStreamChunkSize);
	int len = [_receiveStream read:buf maxLength:kStreamChunkSize];
	NSData *data = [NSData dataWithBytesNoCopy:buf length:len freeWhenDone:YES];
	return data;
}

- (void)sendData:(NSData *)data
{
	[_sendBufferLock lock];
	BOOL bufferEmpty = [_sendBuffer length] == 0;
	[_sendBuffer appendData:data];
	
	//NSLog(@"SBC << %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
	
	if (bufferEmpty) {
		// prime the sending
		unsigned chunkLength = MIN(kStreamChunkSize, [_sendBuffer length]);
		uint8_t *bytes = (uint8_t *)[_sendBuffer bytes];
		[_sendStream write:bytes maxLength:chunkLength];
		[_sendBuffer replaceBytesInRange:NSMakeRange(0,chunkLength)
							   withBytes:NULL
								  length:0];
	}
	[_sendBufferLock unlock];
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
				//NSLog(@"SBC >> %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
				[self processReceivedData:data];
			}
			free(buf);
			break;
		}
		case NSStreamEventOpenCompleted:
		{
			//NSLog(@"opened");
			break;
		}
		case NSStreamEventErrorOccurred:
		{
			if (_flags.error) {
				NSError *error = nil;
				
				if (GET_STATE == ConnectionNotConnectedState) {
					error = [NSError errorWithDomain:ConnectionErrorDomain
												code:ConnectionStreamError
											userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Is the FTP service running on %@?", [self host]]
																				 forKey:NSLocalizedDescriptionKey]];
				}
				else {
					[NSError errorWithDomain:ConnectionErrorDomain
										code:ConnectionStreamError
									userInfo:[NSDictionary dictionaryWithObject:@"Receive Stream Error" forKey:NSLocalizedDescriptionKey]];
				}
				
				[_forwarder connection:self didReceiveError:error];
			}
			break;
		}
		case NSStreamEventEndEncountered:
		{
			[self closeStreams];
			[self setState:ConnectionNotConnectedState];
			if (_flags.didDisconnect) {
				[_forwarder connection:self didDisconnectFromHost:_connectionHost];
			}
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
			uint8_t *buf = (uint8_t *)malloc(sizeof(uint8_t) * kStreamChunkSize);
			int len = [_receiveStream read:buf maxLength:kStreamChunkSize];
			if (len >= 0)
			{
				NSData *data = [NSData dataWithBytesNoCopy:buf length:len freeWhenDone:NO];
				[self processReceivedData:data];
			}
			free(buf);
			break;
		}
		case NSStreamEventOpenCompleted:
		{
		//	if ([(NSInputStream *)_receiveStream hasBytesAvailable]) {
		//		[self stream:_receiveStream handleEvent:NSStreamEventHasBytesAvailable];
		//	}
			break;
		}
		case NSStreamEventErrorOccurred:
		{
			if (_flags.error)
			{
				NSError *error = nil;
				
				if (GET_STATE == ConnectionNotConnectedState) {
					error = [NSError errorWithDomain:ConnectionErrorDomain
												code:ConnectionStreamError
											userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Is the FTP service running on %@?", [self host]]
																				 forKey:NSLocalizedDescriptionKey]];
				}
				else {
					error = [NSError errorWithDomain:ConnectionErrorDomain
												code:ConnectionStreamError
											userInfo:[NSDictionary dictionaryWithObject:@"Receive Stream Error" forKey:NSLocalizedDescriptionKey]];
				}
				
				[_forwarder connection:self didReceiveError:error];
			}
			
			break;
		}
		case NSStreamEventEndEncountered:
		{
			[self closeStreams];
			[self setState:ConnectionNotConnectedState];
			if (_flags.didDisconnect) {
				[_forwarder connection:self didDisconnectFromHost:_connectionHost];
			}
			break;
		}
		case NSStreamEventNone:
		{
			break;
		}
		case NSStreamEventHasSpaceAvailable:
		{
			[_sendBufferLock lock];
			
			unsigned chunkLength = MIN(kStreamChunkSize, [_sendBuffer length]);
			if (chunkLength > 0) {
				uint8_t *bytes = (uint8_t *)[_sendBuffer bytes];
				[(NSOutputStream *)_sendStream write:bytes maxLength:chunkLength];
				[_sendBuffer replaceBytesInRange:NSMakeRange(0,chunkLength)
									   withBytes:NULL
										  length:0];
				
			}
			
			[_sendBufferLock unlock];
			break;
		}
		default:
		{
			if ([AbstractConnection debugEnabled])
				NSLog(@"Composite Event Code!  Need to deal with this!");
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
		NSLog(@"StreamBasedConnection: unknown stream (%@)", stream);
	}
}

#pragma mark -
#pragma mark File Checking

- (void)checkExistenceOfPath:(NSString *)path
{
	if (!_fileCheckingConnection) {
		_fileCheckingConnection = [[[self class] alloc] initWithHost:[self host]
																port:[self port]
															username:[self username]
															password:[self password]];
		[_fileCheckingConnection setDelegate:self];
		[_fileCheckingConnection connect];
	}
	[self queueFileCheck:path];
	[self sendPortMessage:COMMAND];
}

- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath;
{
	if (_flags.fileCheck) {
		NSString *fileToCheck = [self currentFileCheck];
		NSString *name = [fileToCheck lastPathComponent];
		BOOL isDir = [fileToCheck pathExtension] == nil;
		NSEnumerator *e = [contents objectEnumerator];
		NSDictionary *cur;
		
		while (cur = [e nextObject]) {
			if ([[cur objectForKey:cxFilenameKey] isEqualToString:name]) {
				if (isDir) {
					if ([[cur objectForKey:NSFileType] isEqualToString:NSDirectoryFileType]) {
						[_forwarder connection:self
						checkedExistenceOfPath:fileToCheck
									pathExists:YES];
						[self dequeueFileCheck];
						return;
					}
				} else {
					if (![[cur objectForKey:NSFileType] isEqualToString:NSDirectoryFileType]) {
						[_forwarder connection:self
						checkedExistenceOfPath:fileToCheck
									pathExists:YES];
						[self dequeueFileCheck];
						return;
					}
				}
			}
		}
		[_forwarder connection:self checkedExistenceOfPath:fileToCheck pathExists:NO];
	}
}
@end

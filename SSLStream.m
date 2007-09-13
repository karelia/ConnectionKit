/*
 Copyright (c) 2005-2006, Greg Hulands <ghulands@mac.com>
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

#import "SSLStream.h"
#import "AbstractConnection.h"
#import "RunLoopForwarder.h"
#import "InterThreadMessaging.h"

// This file heavily based on ONBSocket, ONBSSLContext and ONBSSLIdentity
// These classes were re-licensed from GPL to BSD for use in the Connection Framework project

enum { START, STOP, TURN_ON_SSL };

@interface SSLStream (Private)

- (int)performHandshakeWithData:(NSMutableData *)input unused:(NSMutableData *)output;
- (OSStatus)handleSSLReadToData:(void *)data size:(size_t *)size;
- (OSStatus)handleSSLWriteFromData:(const void *)data size:(size_t *)size;
- (NSData *)encryptData:(NSData *)data inputData:(NSMutableData *)input;
- (NSData *)decryptData:(NSMutableData *)data outputData:(NSMutableData *)output;

- (void)sendPortMessage:(int)aMessage;

@end

OSStatus SSLReadFunction(SSLConnectionRef connection, void *data, size_t *dataLength);
OSStatus SSLWriteFunction(SSLConnectionRef connection, const void *data, size_t *dataLength);

void  readStreamEventOccurred(CFReadStreamRef stream, CFStreamEventType eventType, void *info);
void  writeStreamEventOccurred(CFWriteStreamRef stream, CFStreamEventType eventType, void *info);

@implementation SSLStream

- (id)init
{
	if (self = [super init])
	{
		// do the ssl identity
		SecKeychainRef kc = nil;
		SecKeychainCopyDefault(&kc);
		if (!kc)
		{
			KTLog(TransportDomain, KTLogFatal, @"Failed to get the default keychain");
			[self release];
			return nil;
		}
		SecIdentitySearchRef search = nil;
		SecIdentitySearchCreate(kc, CSSM_KEYUSE_SIGN, &search);
		CFRelease(kc);
		if (!search)
		{
			KTLog(TransportDomain, KTLogFatal, @"Failed to create SSL identity search");
			[self release];
			return nil;
		}
		SecIdentitySearchCopyNext(search, &_sslIdentity);
		CFRelease(search);
		if (!_sslIdentity)
		{
			KTLog(TransportDomain, KTLogFatal, @"Failed to create SSL identity");
			[self release];
			return nil;
		}
		
		_receiveBuffer = [[NSMutableData data] retain];
		_sendBuffer = [[NSMutableData data] retain];
		_receiveBufferEncrypted = [[NSMutableData data] retain];
		_sendBufferEncrypted = [[NSMutableData data] retain];
		_inputData = [[NSMutableData data] retain];
		_outputData = [[NSMutableData data] retain];
		
		_props = [[NSMutableDictionary dictionary] retain];
		_status = NSStreamStatusNotOpen;
		
		_creationThread = [NSThread currentThread];
		_forwarder = [[RunLoopForwarder alloc] init];
		_bufferLock = [[NSLock alloc] init];
		
		[NSThread prepareForConnectionInterThreadMessages];
	}
	return self;
}

- (id)initWithHost:(NSHost *)host port:(UInt16)port sslVersion:(SSLVersion)ssl
{
	if (self = [self init]) {
		_requestedSSL = ssl;
		_flags.sslServerMode = NO;

		CFStreamCreatePairWithSocketToCFHost(kCFAllocatorDefault,
											 (CFHostRef)host,
											 port,
											 &_receiveStream,
											 &_sendStream);		// "Ownership follows the Create Rule."
		CFOptionFlags allStreamFlags = kCFStreamEventNone & kCFStreamEventOpenCompleted & kCFStreamEventHasBytesAvailable & kCFStreamEventCanAcceptBytes & kCFStreamEventErrorOccurred & kCFStreamEventEndEncountered;
		CFStreamClientContext ctx;
		ctx.info = self;
		CFReadStreamSetClient(_receiveStream,allStreamFlags,readStreamEventOccurred,&ctx);
		CFWriteStreamSetClient(_sendStream,allStreamFlags,writeStreamEventOccurred,&ctx);
	}
	return self;
}

- (id)initListeningOnPort:(UInt16)port sslVersion:(SSLVersion)ssl
{
	if (self = [self init])
	{
		_requestedSSL = ssl;
		_flags.sslServerMode = NO;
		
	}
	
	return nil;
}

- (void)dealloc
{
	[_port setDelegate:nil];
	[_port release];
	[_bufferLock release];
	[_forwarder release];
	
	[_sendBuffer release];
	[_receiveBuffer release];
	[_sendBufferEncrypted release];
	[_receiveBufferEncrypted release];
	[_inputData release];
	[_outputData release];
	
	if (_sslIdentity) CFRelease(_sslIdentity);
	if (_sslContext) SSLDisposeContext(_sslContext);
	
	[super dealloc];
}

#pragma mark -
#pragma mark Threading

- (void)runSSLStreamBackgroundThread:(id)unused
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// NOTE: this may be leaking ... there are two retains going on here.  Apple bug report #2885852, still open after TWO YEARS!
	// But then again, we can't remove the thread, so it really doesn't mean much.
	[NSThread prepareForConnectionInterThreadMessages];
	[[NSRunLoop currentRunLoop] addPort:_port forMode:NSDefaultRunLoopMode];
	
	[[NSRunLoop currentRunLoop] run];
	
	[pool release];
}

/*!	Send a message from the main thread to the port, to communicate with the background thread.
*/
- (void)sendPortMessage:(int)aMessage
{
	if (nil != _port)
	{
		NSPortMessage *message
		= [[NSPortMessage alloc] initWithSendPort:_port
									  receivePort:_port components:nil];
		[message setMsgid:aMessage];
		BOOL sent = [message sendBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.0]];
		if (!sent)
		{
			KTLog(ThreadingDomain, KTLogFatal, @"SSLStream failed to send port message: %d", aMessage);
		}
		[message release];
	}
}

/*" NSPortDelegate method gets called in the background thread.
"*/
- (void)handlePortMessage:(NSPortMessage *)portMessage
{
	switch ([portMessage msgid]) {
		case START:
			
			break;
		case STOP:
			[[NSRunLoop currentRunLoop] removePort:_port forMode:NSDefaultRunLoopMode];
			break;
		case TURN_ON_SSL:
		{
			if (_flags.isHandshaking) 
			{
				KTLog(StreamDomain, KTLogDebug, @"SSL Tried to activate while handshake in progress");
				return;
			}
			
			_flags.isHandshaking = YES;
			NSMutableData *output = [NSMutableData data];
			[_receiveBufferEncrypted setData:_receiveBuffer];
			int ret = [self performHandshakeWithData:_receiveBufferEncrypted unused:output];
			if ([output length] > 0)
			{
				[_sendBufferEncrypted appendData:output];
			}
			if (ret < 0)
			{
				KTLog(StreamDomain, KTLogFatal, @"Failed to complete SSL Handshake");
				return;
			}
			
			_flags.sslEnabled = YES;
			_flags.isHandshaking = NO;
		}
		break;
	}
}

#pragma mark -
#pragma mark Accessors

- (void)setRequestedSSLVersion:(SSLVersion)ssl
{
	_requestedSSL = ssl;
}

- (SSLVersion)requestedSSLVersion
{
	return _requestedSSL;
}

- (SSLVersion)negotiatedSSLVersion
{
	return _negotiatedSSL;
}

- (void)enableSSL
{
	[self sendPortMessage:TURN_ON_SSL];
}

#pragma mark -
#pragma mark NSStream Methods

- (void)open
{
	[self sendPortMessage:START];
}

- (void)close
{
	_status = NSStreamStatusNotOpen;
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	
	if (_status != NSStreamStatusNotOpen)
		return;
	
	_status = NSStreamStatusOpening;
	_port = [[NSPort port] retain];
	[_port setDelegate:self];
	[NSThread detachNewThreadSelector:@selector(runSSLStreamBackgroundThread:)
							 toTarget:self
						   withObject:nil];
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	[self sendPortMessage:STOP];
}

- (void)setDelegate:(id)delegate
{
	_delegate = delegate;
}

- (id)delegate
{
	return _delegate;
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key
{
	[_props setObject:property forKey:key];
	return YES;
}

- (id)propertyForKey:(NSString *)key
{
	return [_props objectForKey:key];
}

- (NSError *)streamError
{
	return nil;
}

- (NSStreamStatus)streamStatus
{
	return _status;
}

- (int)read:(uint8_t *)buffer maxLength:(unsigned int)len
{
	int read = 0;
	if (_flags.sslEnabled)
	{
		
	}
	else
	{
		
	}
	return read;
}

- (int)write:(const uint8_t *)buffer maxLength:(unsigned int)len
{
	int wrote = 0;
	if (_flags.sslEnabled)
	{
		
	}
	else
	{
		
	}	
	return wrote;
}

- (void)readStream:(CFReadStreamRef)stream handleEvent:(CFStreamEventType)event
{
	
}

- (void)writeStream:(CFWriteStreamRef)stream handleEvent:(CFStreamEventType)event
{
	
}

#pragma mark SSLContext stuff

- (int)performHandshakeWithData:(NSMutableData *)input unused:(NSMutableData *)output
{
	int ret = 0;
	if (!_sslContext)
	{
		if (ret = SSLNewContext((Boolean)_flags.sslServerMode, &_sslContext))
		{
			KTLog(StreamDomain, KTLogFatal, @"Failed to create SSL Context");
		}
		
		if (ret = SSLSetConnection(_sslContext, self))
		{
			KTLog(StreamDomain, KTLogFatal, @"Failed to set SSL connection reference");
			return ret;
		}
		
		if (ret = SSLSetIOFuncs(_sslContext, SSLReadFunction, SSLWriteFunction))
		{
			KTLog(StreamDomain, KTLogFatal, @"Failed to set SSL IO Functions");
			return ret;
		}
		
		if (ret = SSLSetEnableCertVerify(_sslContext, true))
		{
			KTLog(StreamDomain, KTLogFatal, @"Failed to set verify certificates");
			return ret;
		}
		
		CFArrayRef certs = CFArrayCreate(kCFAllocatorDefault, (const void **)&_sslIdentity, 1, NULL);
		if (certs)
		{
			ret = SSLSetCertificate(_sslContext, certs);
			CFRelease(certs);
		}
		
		if (ret)
		{
			KTLog(StreamDomain, KTLogDebug, @"Failed to set SSL Certificate");
		}
		
		_inputData = input;
		_outputData = output;		
		ret = SSLHandshake(_sslContext);
		
		if (ret == errSSLWouldBlock)
		{
			KTLog(StreamDomain, KTLogDebug, @"SSL Handshake would block");
			return 0;
		}
		
		if (ret != 0)
		{
			return 1;
		}
	}
	return ret;
}

- (NSData *)encryptData:(NSData *)data inputData:(NSMutableData *)input
{
	if (!data || [data length] == 0)
	{
		return [NSData data];
	}
		
	_inputData = input;
	_outputData = [NSMutableData dataWithCapacity:2*[data length]];
	unsigned int inputLength = [data length];
	unsigned int processed = 0;
	const void *buffer = [data bytes];
	
	while (processed < inputLength)
	{
		size_t written = 0;
		
		int ret;
		if (ret = SSLWrite(_sslContext, buffer + processed, inputLength - processed, &written))
		{
			KTLog(StreamDomain, KTLogFatal, @"Failed SSLWrite with data (%d bytes)", inputLength);
			return nil;
		}
		processed += written;
	}
	
	return [NSData dataWithData:_outputData];	
}

- (NSData *)decryptData:(NSMutableData *)data outputData:(NSMutableData *)output
{
	if (!data || [data length] == 0)
	{
		return [NSData data];
	}
	
	_inputData = data;
	_outputData = output;
	NSMutableData *decryptedData = [NSMutableData dataWithCapacity:[data length]];
	int ret = 0;
	
	while (! ret)
	{
		size_t read = 0;
		char buf[1024];
		
		ret = SSLRead(_sslContext, buf, 1024, &read);
		if (ret && (ret != errSSLWouldBlock) && (ret != errSSLClosedGraceful))
		{
			KTLog(StreamDomain, KTLogFatal, @"Error in SSLRead: %d", ret);
			return nil;
		}
		
		[decryptedData appendBytes:buf length:read];
	}
	
	return [NSData dataWithData:decryptedData];
}

- (OSStatus)handleSSLReadToData:(void *)data size:(size_t *)size
{
	size_t sizeWanted = *size;
	*size = MIN(sizeWanted, [_inputData length]);
	if (*size == 0)
	{
		return errSSLWouldBlock;
	}
	
	NSRange byteRange = NSMakeRange(0, *size);
	[_inputData getBytes:data range:byteRange];
	[_inputData replaceBytesInRange:byteRange withBytes:NULL length:0];
	
	if (sizeWanted > *size)
		return errSSLWouldBlock;
	
	return noErr;
}

- (OSStatus)handleSSLWriteFromData:(const void *)data size:(size_t *)size
{
	[_outputData appendBytes:data length:*size];
	return noErr;
}

@end

void  readStreamEventOccurred(CFReadStreamRef stream, CFStreamEventType eventType, void *info)
{
	SSLStream *ssl = (SSLStream *)info;
	[ssl readStream:stream handleEvent:eventType];
}

void  writeStreamEventOccurred(CFWriteStreamRef stream, CFStreamEventType eventType, void *info)
{
	SSLStream *ssl = (SSLStream *)info;
	[ssl writeStream:stream handleEvent:eventType];
}

OSStatus SSLReadFunction(SSLConnectionRef connection, void *data, size_t *dataLength)
{
	return [(SSLStream *)connection handleSSLReadToData:data size:dataLength];
}

OSStatus SSLWriteFunction(SSLConnectionRef connection, const void *data, size_t *dataLength)
{
	return [(SSLStream *)connection handleSSLWriteFromData:data size:dataLength];
}

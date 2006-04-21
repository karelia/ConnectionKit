/*
 Copyright (c) 2005-2006, Greg Hulands <ghulands@framedphotographics.com>
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

enum { KILL_THREAD };

@interface SSLStream (Private)

- (int)performHandshakeWithData:(NSData *)input unused:(NSData **)output;
- (OSStatus)handleSSLReadToData:(void *)data size:(size_t *)size;
- (OSStatus)handleSSLWriteFromData:(const void *)data size:(size_t *)size;

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
		if (!search)
		{
			KTLog(TransportDomain, KTLogFatal, @"Failed to create SSL identity search");
			[self release];
			return nil;
		}
		SecIdentitySearchCopyNext(search, &_sslIdentity);
		if (!_sslIdentity)
		{
			KTLog(TransportDomain, KTLogFatal, @"Failed to create SSL identity");
			[self release];
			return nil;
		}
		
		_receiveBuffer = [[NSMutableData data] retain];
		_receiveBufferEncrypted = [[NSMutableData data] retain];
		_sendBuffer = [[NSMutableData data] retain];
		_sendBufferEncrypted = [[NSMutableData data] retain];
		
		_props = [[NSMutableDictionary dictionary] retain];
		_status = NSStreamStatusNotOpen;
		
		_creationThread = [NSThread currentThread];
		_forwarder = [[RunLoopForwarder alloc] init];
		_port = [[NSPort port] retain];
		[_port setDelegate:self];
		
		[NSThread prepareForInterThreadMessages];
		[NSThread detachNewThreadSelector:@selector(runSSLStreamBackgroundThread:)
								 toTarget:self
							   withObject:nil];
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
											 &_sendStream);
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
	
	[_sendBuffer release];
	[_sendBufferEncrypted release];
	[_receiveBuffer release];
	[_receiveBufferEncrypted release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Threading

- (void)runSSLStreamBackgroundThread:(id)unused
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// NOTE: this may be leaking ... there are two retains going on here.  Apple bug report #2885852, still open after TWO YEARS!
	// But then again, we can't remove the thread, so it really doesn't mean much.
	[NSThread prepareForInterThreadMessages];
	[[NSRunLoop currentRunLoop] addPort:_port forMode:(NSString *)kCFRunLoopCommonModes];
	
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
		case KILL_THREAD:
			[[NSRunLoop currentRunLoop] removePort:_port forMode:(NSString *)kCFRunLoopCommonModes];
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
	
}

#pragma mark -
#pragma mark NSStream Methods

- (void)open
{
	CFReadStreamOpen(_receiveStream);
	CFWriteStreamOpen(_sendStream);
}

- (void)close
{
	CFReadStreamClose(_receiveStream);
	CFWriteStreamClose(_sendStream);
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	CFRunLoopRef rl = (CFRunLoopRef)aRunLoop;
	CFStringRef m = (CFStringRef)mode;
	
	CFReadStreamScheduleWithRunLoop(_receiveStream,rl,m);
	CFWriteStreamScheduleWithRunLoop(_sendStream,rl,m);
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	CFRunLoopRef rl = (CFRunLoopRef)aRunLoop;
	CFStringRef m = (CFStringRef)mode;
	
	CFReadStreamUnscheduleFromRunLoop(_receiveStream,rl,m);
	CFWriteStreamUnscheduleFromRunLoop(_sendStream,rl,m);
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
	//read the data, decrypt it and copy to the buffer.
	UInt8 *encrypted = (UInt8 *)malloc(sizeof(UInt8) * len);
	CFIndex bytesRead;
	encrypted = (UInt8 *)CFReadStreamGetBuffer(_receiveStream,(CFIndex)len,&bytesRead);
	
	UInt8 *decrypted;
	memcpy(buffer,decrypted,bytesRead);
	
}

- (int)write:(const uint8_t *)buffer maxLength:(unsigned int)len
{
	//encrypt the data, write it to the stream
	
}

- (void)readStream:(CFReadStreamRef)stream handleEvent:(CFStreamEventType)event
{
	NSStreamEvent evt;
	switch (event) {
		case kCFStreamEventNone: evt = NSStreamEventNone; break;
		case kCFStreamEventOpenCompleted: evt = NSStreamEventOpenCompleted; break;
		case kCFStreamEventHasBytesAvailable: evt = NSStreamEventHasBytesAvailable; break;
		case kCFStreamEventCanAcceptBytes: evt = NSStreamEventHasSpaceAvailable; break;
		case kCFStreamEventErrorOccurred: evt = NSStreamEventErrorOccurred; break;
		case kCFStreamEventEndEncountered: evt = NSStreamEventEndEncountered; break;
	}
	[_delegate stream:self handleEvent:evt];
}

- (void)writeStream:(CFWriteStreamRef)stream handleEvent:(CFStreamEventType)event
{
	NSStreamEvent evt;
	switch (event) {
		case kCFStreamEventNone: evt = NSStreamEventNone; break;
		case kCFStreamEventOpenCompleted: evt = NSStreamEventOpenCompleted; break;
		case kCFStreamEventHasBytesAvailable: evt = NSStreamEventHasBytesAvailable; break;
		case kCFStreamEventCanAcceptBytes: evt = NSStreamEventHasSpaceAvailable; break;
		case kCFStreamEventErrorOccurred: evt = NSStreamEventErrorOccurred; break;
		case kCFStreamEventEndEncountered: evt = NSStreamEventEndEncountered; break;
	}
	[_delegate stream:self handleEvent:evt];
}

#pragma mark SSLContext stuff

- (int)performHandshakeWithData:(NSData *)input unused:(NSData **)output
{
	int ret = 0;
	if (!_sslContext)
	{
		if (ret = SSLNewContext((Boolean)_flags.sslServerMode, &_sslContext))
		{
			KTLog(TransportDomain, KTLogFatal, @"Failed to create SSL Context");
		}
		
		if (ret = SSLSetConnection(_sslContext, self))
		{
			KTLog(TransportDomain, KTLogFatal, @"Failed to set SSL connection reference");
			return ret;
		}
		
		if (ret = SSLSetIOFuncs(_sslContext, SSLReadFunction, SSLWriteFunction))
		{
			KTLog(TransportDomain, KTLogFatal, @"Failed to set SSL IO Functions");
			return ret;
		}
		
		if (ret = SSLSetEnableCertVerify(_sslContext, true))
		{
			KTLog(TransportDomain, KTLogFatal, @"Failed to set verify certificates");
			return ret;
		}
		
		CFArrayRef certs = CFArrayCreate(kCFAllocatorDefault, (const void **)&_sslIdentity, 1, NULL);
		ret = SSLSetCertificate(_sslContext, certs);
		CFRelease(certs);
		
		if (ret)
		{
			KTLog(TransportDomain, KTLogDebug, @"Failed to set SSL Certificate");
		}
		
		ret = SSLHandshake(_sslContext);
		
		if (ret == errSSLWouldBlock)
		{
			KTLog(TransportDomain, KTLogDebug, @"SSL Handshake would block");
			return 0;
		}
		
		if (ret != 0)
		{
			return 1;
		}
	}
	return ret;
}

- (OSStatus)handleSSLReadToData:(void *)data size:(size_t *)size
{
	
}

- (OSStatus)handleSSLWriteFromData:(const void *)data size:(size_t *)size
{
	
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

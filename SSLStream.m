//
//  SSLStream.m
//  FTPConnection
//
//  Created by Greg Hulands on 7/12/05.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "SSLStream.h"

void  readStreamEventOccurred(CFReadStreamRef stream, CFStreamEventType eventType, void *info);
void  writeStreamEventOccurred(CFWriteStreamRef stream, CFStreamEventType eventType, void *info);

@implementation SSLStream

- (id)initWithHost:(NSHost *)host port:(UInt32)port sslVersion:(SSLVersion)ssl
{
	if (self = [super init]) {
		_requestedSSL = ssl;
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

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

#import <Foundation/Foundation.h>
#import <Security/SecureTransport.h>

@class RunLoopForwarder;
@protocol InputStream, OutputStream;

typedef enum {
	SSLVersion2 = 0,
	SSLVersion3,
	SSLVersionTLS,
	SSLVersionNegotiated
} SSLVersion;

@interface SSLStream : NSStream <InputStream, OutputStream> 
{
	SSLContextRef		_sslContext;
	SSLVersion			_requestedSSL;
	SSLVersion			_negotiatedSSL;
	
	CFReadStreamRef		_receiveStream;
	CFWriteStreamRef	_sendStream;
	
	NSMutableData		*_receiveBuffer;
	NSMutableData		*_sendBuffer;
	
	NSMutableDictionary *_props;
	id					_delegate;
	NSStreamStatus		_status;
}

- (id)initWithHost:(NSHost *)host port:(UInt32)port sslVersion:(SSLVersion)ssl;

- (void)setRequestedSSLVersion:(SSLVersion)ssl;
- (SSLVersion)requestedSSLVersion;
- (SSLVersion)negotiatedSSLVersion;

- (void)open;
- (void)close;
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)setDelegate:(id)delegate;
- (id)delegate;
- (BOOL)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (NSError *)streamError;
- (NSStreamStatus)streamStatus;

- (int)read:(uint8_t *)buffer maxLength:(unsigned int)len;
- (int)write:(const uint8_t *)buffer maxLength:(unsigned int)len;

@end

@interface NSObject (SSLStreamDelegate)

- (BOOL)streamFailedSSLNegotiation:(SSLStream *)stream message:(NSString *)msg forceConnectionToHost:(NSString *)host;

@end

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


#import "CKHTTPConnection.h"
#import "CKHTTPResponse.h"
#import "CKHTTPRequest.h"

NSString *CKHTTPConnectionErrorDomain = @"CKHTTPConnectionErrorDomain";

@interface CKHTTPConnection (Private)
- (void)handleReadStreamEvent:(CFStreamEventType)type;
- (void)handleWriteStreamEvent:(CFStreamEventType)type;
@end

static void ReadStreamClientCallBack(CFReadStreamRef stream, CFStreamEventType type, void *clientCallBackInfo) {
    [((CKHTTPConnection *)clientCallBackInfo) handleReadStreamEvent: type];
}

static void WriteStreamClientCallBack(CFWriteStreamRef stream, CFStreamEventType type, void *clientCallBackInfo) {
    [((CKHTTPConnection *)clientCallBackInfo) handleWriteStreamEvent: type];
}

@implementation CKHTTPConnection

- (id)initWithDelegate:(id)delegate
{
	[super init];
	_delegate = delegate;
	
	_flags.didFailWithError = [delegate respondsToSelector:@selector(connection:didFailWithError:)];
	_flags.didFinishLoading = [delegate respondsToSelector:@selector(connectionDidFinishLoading:)];
	_flags.didReceiveData = [delegate respondsToSelector:@selector(connection:didReceiveData:)];
	_flags.didReceiveResponse = [delegate respondsToSelector:@selector(connection:didReceiveResponse:)];
	_flags.didSendDataOfLength = [delegate respondsToSelector:@selector(connection:didSendDataOfLength:)];

	return self;
}

- (void)closeStreams
{
	[_response autorelease];
	_response = nil;
	
	if (_readStream != NULL)
	{
		CFReadStreamSetClient(_readStream,0,NULL,NULL);
		CFReadStreamUnscheduleFromRunLoop(_readStream,CFRunLoopGetCurrent(),kCFRunLoopCommonModes);
		CFReadStreamClose(_readStream);
		CFRelease(_readStream);
		_readStream = NULL;
	}
	if (_writeStream != NULL)
	{
		CFWriteStreamSetClient(_writeStream,0,NULL,NULL);
		CFWriteStreamUnscheduleFromRunLoop(_writeStream,CFRunLoopGetCurrent(),kCFRunLoopCommonModes);
		CFWriteStreamClose(_writeStream);
		CFRelease(_writeStream);
		_writeStream = NULL;
	}
}

- (void)sendError:(NSString *)error code:(int)code
{
	NSError *err = [NSError errorWithDomain:CKHTTPConnectionErrorDomain 
									   code:code 
								   userInfo:[NSDictionary dictionaryWithObject:error forKey:NSLocalizedDescriptionKey]];
	if (_flags.didFailWithError)
		[_delegate connection:self didFailWithError:err];
}

- (void)cancel
{
	[self closeStreams];
}

- (void)sendRequest:(CKHTTPRequest *)request
{
	if (_readStream || _writeStream)
		[self closeStreams];
	
	[_request autorelease];
	_request = [request retain];
		
	if ([[[[request url] scheme] lowercaseString] isEqualToString:@"https"])
	{
		CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,(CFStringRef)[[request url] host],443,&_readStream,&_writeStream);
		//turn on ssl
		CFWriteStreamSetProperty(_writeStream,kCFStreamPropertySocketSecurityLevel,kCFStreamSocketSecurityLevelNegotiatedSSL);
		CFReadStreamSetProperty(_readStream,kCFStreamPropertySocketSecurityLevel,kCFStreamSocketSecurityLevelNegotiatedSSL);
	}
	else
	{
		CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,(CFStringRef)[[request url] host],80,&_readStream,&_writeStream);
	}
	
	//set callbacks
	CFStreamClientContext ctxt = {0, self, NULL, NULL, NULL};
	BOOL val;
	
	val = CFWriteStreamSetClient(_writeStream,
						   kCFStreamEventOpenCompleted | kCFStreamEventCanAcceptBytes | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered,
						   WriteStreamClientCallBack,
						   &ctxt);
	if (!val)
	{
		[self closeStreams];
		[self sendError:@"Failed to create stream client" code:0];
		return;
	}
	val = CFReadStreamSetClient(_readStream,
						  kCFStreamEventOpenCompleted | kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered,
						  ReadStreamClientCallBack,
						  &ctxt);
	if (!val)
	{
		[self closeStreams];
		[self sendError:@"Failed to create stream client" code:0];
		return;
	}	
	CFWriteStreamScheduleWithRunLoop(_writeStream,CFRunLoopGetCurrent(),kCFRunLoopCommonModes);
	CFReadStreamScheduleWithRunLoop(_readStream,CFRunLoopGetCurrent(),kCFRunLoopCommonModes);
		
	//open the read stream before the write stream
	if (!CFReadStreamOpen(_readStream))
	{
		[self closeStreams];
		[self sendError:@"Failed to open read stream" code:0];
		return;
	}
	
	if (!CFWriteStreamOpen(_writeStream))
	{
		[self closeStreams];
		[self sendError:@"Failed to open write stream" code:0];
		return;
	}
}

- (CKHTTPRequest *)request
{
	return _request;
}

- (void)handleReadStreamEvent:(CFStreamEventType)type
{
	switch (type)
	{
		case kCFStreamEventOpenCompleted:
		{
			[_response autorelease];
			_response = [[CKHTTPResponse alloc] init];
		}break;
		case kCFStreamEventHasBytesAvailable:
		{
			UInt8 buffer[4096];
			CFIndex bytesRead = CFReadStreamRead(_readStream,buffer,sizeof(buffer));
			
			NSData *data = [NSData dataWithBytes:buffer length:bytesRead];
			[_response appendData:data];
			if (_flags.didReceiveData)
				[_delegate connection:self didReceiveDataOfLength:bytesRead];
		} break;
		case kCFStreamEventEndEncountered:
		{
			CFReadStreamSetClient(_readStream,0,NULL,NULL);
			CFReadStreamUnscheduleFromRunLoop(_readStream,CFRunLoopGetCurrent(),kCFRunLoopCommonModes);
			CFReadStreamClose(_readStream);
			CFRelease(_readStream);
			_readStream = NULL;
			if (_flags.didReceiveResponse)
				[_delegate connection:self didReceiveResponse:_response];
			if (_flags.didFinishLoading)
				[_delegate connectionDidFinishLoading:self];
		}break;
		case kCFStreamEventErrorOccurred:
		{
			[self sendError:@"Read stream error occured" code:CFReadStreamGetStatus(_readStream)];
		}break;
		default:break;
	}
}

- (void)handleWriteStreamEvent:(CFStreamEventType)type
{
	switch (type)
	{
		case kCFStreamEventOpenCompleted:
		{
			[_sendData autorelease];
			_sendData = [[_request serializedRequest] retain];
			_sendRange = NSMakeRange(0, 0);
		}break;
		case kCFStreamEventCanAcceptBytes:
		{
			_sendRange = NSMakeRange(_sendRange.location + _sendRange.length, 4096);
			if (_sendRange.location + _sendRange.length > [_sendData length])
				_sendRange.length = [_sendData length] - _sendRange.location;
			
			NSData *toSend = [_sendData subdataWithRange:_sendRange];
			CFWriteStreamWrite(_writeStream,(UInt8 *)[toSend bytes],[toSend length]);
			
			if (_flags.didSendDataOfLength)
				[_delegate connection:self didSendDataOfLength:[toSend length]];
			
		}break;
		case kCFStreamEventErrorOccurred:
		{
			CFStreamError err = CFWriteStreamGetError(_writeStream);
			
			[self sendError:@"Write stream error occured" code:err.error];
		}break;
		case kCFStreamEventEndEncountered:
		{
			CFWriteStreamSetClient(_writeStream,0,NULL,NULL);
			CFWriteStreamUnscheduleFromRunLoop(_writeStream,CFRunLoopGetCurrent(),kCFRunLoopCommonModes);
			CFWriteStreamClose(_writeStream);
			CFRelease(_writeStream);
			_writeStream = NULL;
			
		}break;
		default: break;
	}
}

@end




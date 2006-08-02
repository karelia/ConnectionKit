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

#import <Cocoa/Cocoa.h>

@class CKHTTPRequest, CKHTTPResponse;

@interface CKHTTPConnection : NSObject 
{
	CFReadStreamRef _readStream;
	CFWriteStreamRef _writeStream;
	
	CKHTTPRequest *_request;
	CKHTTPResponse *_response;
	
	NSData *_sendData;
	NSRange _sendRange;
	
	id _delegate;
	
	struct __httpconflags {
		unsigned didFailWithError:1;
		unsigned didReceiveData:1;
		unsigned didReceiveResponse:1;
		unsigned didFinishLoading:1;
		unsigned didSendDataOfLength:1;
	} _flags;
}

- (id)initWithDelegate:(id)delegate;

- (void)sendRequest:(CKHTTPRequest *)request;
- (CKHTTPRequest *)request;

- (void)cancel;

@end

@interface NSObject (CKHTTPConnectionDelegate)

- (void)connection:(CKHTTPConnection *)connection didFailWithError:(NSError *)error;
- (void)connection:(CKHTTPConnection *)connection didReceiveDataOfLength:(int)length;
- (void)connection:(CKHTTPConnection *)connection didReceiveResponse:(CKHTTPResponse *)response;
- (void)connectionDidFinishLoading:(CKHTTPConnection *)connection;
- (void)connection:(CKHTTPConnection *)connection didSendDataOfLength:(int)length;

@end
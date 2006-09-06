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

#import "CKHTTPRequest.h"


@implementation CKHTTPRequest

- (id)initWithURL:(NSURL *)url method:(NSString *)method httpVersion:(CFStringRef)version
{
	[super init];
	
	_request = CFHTTPMessageCreateRequest(kCFAllocatorDefault,(CFStringRef)method,(CFURLRef)url,version);
	CFHTTPMessageSetHeaderFieldValue(_request,CFSTR("Host"),(CFStringRef)[url host]);
	CFHTTPMessageSetHeaderFieldValue(_request,CFSTR("From"),CFSTR("application crash reporter"));
		
	_post = [[NSMutableDictionary dictionary] retain];
	_uploads = [[NSMutableDictionary dictionary] retain];
	
	return self;
}

- (void)dealloc
{
	[_post release];
	[_uploads release];
	CFRelease(_request);
	[super dealloc];
}

- (void)setHeaderField:(NSString *)header value:(NSString *)value
{
	CFHTTPMessageSetHeaderFieldValue(_request,(CFStringRef)header,(CFStringRef)value);
}

- (NSString *)valueForHeaderField:(NSString *)header
{
	return [(NSString *)CFHTTPMessageCopyHeaderFieldValue(_request,(CFStringRef)header) autorelease];
}

- (void)setPostValue:(id)value forKey:(NSString *)key
{
	[_post setObject:value forKey:key];
}

- (void)uploadFile:(NSString *)path forKey:(NSString *)key
{
	NSData *data = [NSData dataWithContentsOfFile:path];
	[self uploadData:data withFilename:[path lastPathComponent] forKey:key];
}

- (void)uploadData:(NSData *)data withFilename:(NSString *)name forKey:(NSString *)key
{
	[_uploads setObject:[NSDictionary dictionaryWithObjectsAndKeys:data, @"data", name, @"filename", nil]
				 forKey:key];
}

- (void)setBody:(NSData *)body
{
	CFHTTPMessageSetBody(_request,(CFDataRef)body);
	[self setHeaderField:@"Content-Length" value:[NSString stringWithFormat:@"%u", [body length]]];
}

- (NSData *)body
{
	return [(NSData *)CFHTTPMessageCopyBody(_request) autorelease];
}

- (BOOL)headersComplete
{
	return CFHTTPMessageIsHeaderComplete(_request);
}

- (NSString *)method
{
	return [(NSString *)CFHTTPMessageCopyRequestMethod(_request) autorelease];
}

- (NSString *)version
{
	return [(NSString *)CFHTTPMessageCopyVersion(_request) autorelease];
}

- (NSURL *)url
{
	return [(NSURL *)CFHTTPMessageCopyRequestURL(_request) autorelease];
}

- (CFHTTPMessageRef)message
{
	return _request;
}

- (NSData *)serializedRequest
{
	if ([_post count] > 0 || [_uploads count] > 0)
	{
		NSMutableData *body = [NSMutableData data];
		NSString *stringBoundary = [NSString stringWithString:@"0xKhTmLbOuNdArY"];
		NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@",stringBoundary];
		[self setHeaderField:@"Content-Type" value:contentType];
		
		NSEnumerator *e = [_post keyEnumerator];
		NSString *key;
		id value;
		
		while (key = [e nextObject])
		{
			[body appendData:[[NSString stringWithFormat:@"--%@\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
			[body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key] dataUsingEncoding:NSUTF8StringEncoding]];
			value = [_post objectForKey:key];
			if (![value isKindOfClass:[NSData class]])
			{
				value = [[value description] dataUsingEncoding:NSUTF8StringEncoding];
			}
			[body appendData:value];
			[body appendData:[[NSString stringWithFormat:@"\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
		}
		
		// do uploads
		e = [_uploads keyEnumerator];
		
		while (key = [e nextObject])
		{
			NSDictionary *rec = [_uploads objectForKey:key];
			NSString *filename = [rec objectForKey:@"filename"];
			NSData *data = [rec objectForKey:@"data"];
			NSString *UTI = (NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
																			  (CFStringRef)[filename pathExtension],
																			  NULL);
			NSString *mime = (NSString *)UTTypeCopyPreferredTagWithClass((CFStringRef)UTI, kUTTagClassMIMEType);	
			if (!mime || [mime length] == 0)
			{
				mime = @"application/octet-stream";
			}
			[body appendData:[[NSString stringWithFormat:@"--%@\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
			[body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\nContent-Type: \"%@\"\r\n\r\n", key, filename, mime] dataUsingEncoding:NSUTF8StringEncoding]];
			[body appendData:data];
			[body appendData:[[NSString stringWithFormat:@"\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
		}
		[body appendData:[[NSString stringWithFormat:@"\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
		[self setBody:body];
	}
	return [(NSData *)CFHTTPMessageCopySerializedMessage(_request) autorelease];
}

@end

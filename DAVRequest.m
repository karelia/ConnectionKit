/*
 Copyright (c) 2004-2006, Greg Hulands <ghulands@framedphotographics.com>
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

#import "DAVRequest.h"
#import "DAVResponse.h"
#import "NSData+Connection.h"

@implementation DAVRequest

+ (id)requestWithMethod:(NSString *)method uri:(NSString *)uri
{
	return [[[DAVRequest alloc] initWithMethod:method uri:uri] autorelease];
}

- (id)init
{
	if (self = [super init])
	{
		myHeaders = [[NSMutableDictionary dictionary] retain];
		myContent = [[NSMutableData data] retain];
		
		//[self setHeader:@"Connection Framework http://www.dlsxtreme.com/ConnectionFramework" forKey:@"User-Agent"];
		[self setHeader:@"text/xml; charset=\"utf-8\"" forKey:@"Content-Type"];
		[self setHeader:@"gzip" forKey:@"Accept-Encoding"];
		[self setHeader:@"chunked" forKey:@"Transfer-Encoding"];
		//[self setHeader:@"gzip" forKey:@"Content-Coding"];
	}
	return self;
}

- (id)initWithMethod:(NSString *)method uri:(NSString *)uri
{
	if (self = [self init])
	{
		myMethod = [method copy];
		myURI = [uri copy];
	}
	return self;
}

- (void)dealloc
{
	[myUserInfo release];
	[myMethod release];
	[myURI release];
	[myHeaders release];
	[myContent release];
	[super dealloc];
}

- (NSString *)description
{
	NSMutableString *str = [NSMutableString stringWithFormat:@"%@ %@ HTTP/1.1\n", myMethod, myURI];
	NSEnumerator *e = [myHeaders keyEnumerator];
	NSString *key;
	
	while (key = [e nextObject])
	{
		[str appendFormat:@"%@: %@\n", key, [myHeaders objectForKey:key]];
	}
	return str;
}

- (NSString *)method
{
	return myMethod;
}

- (NSString *)uri
{
	return myURI;
}

- (void)setHeader:(NSString *)val forKey:(NSString *)key
{
	[myHeaders setObject:val forKey:key];
}

- (void)addHeader:(NSString *)val forKey:(NSString *)key
{
	id header = [myHeaders objectForKey:key];
	if (header)
	{
		if ([header isKindOfClass:[NSMutableArray class]])
		{
			[header addObject:val];
		}
		else
		{
			NSMutableArray *headers = [NSMutableArray arrayWithObject:header];
			[headers addObject:val];
			[myHeaders setObject:headers forKey:key];
		}
	}
	else
	{
		[myHeaders setObject:val forKey:key];
	}
}

- (id)headerForKey:(NSString *)key
{
	return [myHeaders objectForKey:key];
}

- (void)setUserInfo:(id)ui
{
	[myUserInfo autorelease];
	myUserInfo = [ui retain];
}

- (id)userInfo
{
	return myUserInfo;
}

- (void)appendContent:(NSData *)data
{
	[myContent appendData:data];
}

- (void)appendContentString:(NSString *)str
{
	[myContent appendData:[str dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)setContent:(NSData *)data
{
	[myContent setLength:0];
	[myContent appendData:data];
}

- (void)setContentString:(NSString *)str
{
	[self setContent:[str dataUsingEncoding:NSUTF8StringEncoding]];
}

- (NSData *)content
{
	return [NSData dataWithData:myContent];
}

- (NSString *)contentString
{
	return [[[NSString alloc] initWithData:myContent encoding:NSUTF8StringEncoding] autorelease];
}

- (unsigned)contentLength
{
	return [myContent length];
}

- (NSData *)serialized
{
	NSMutableData *packet = [NSMutableData data];
	
	NSString *request = [NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\n", myMethod, myURI];
	[packet appendData:[request dataUsingEncoding:NSUTF8StringEncoding]];
	
	//do the headers
	NSEnumerator *e = [myHeaders keyEnumerator];
	NSString *key;
	
	while (key = [e nextObject])
	{
		NSString *header = nil;
		id val = [myHeaders objectForKey:key];
		if ([val isKindOfClass:[NSMutableArray class]])
		{
			header = [val componentsJoinedByString:@"; "];
		}
		else
		{
			header = (NSString *)val;
		}
		header = [NSString stringWithFormat:@"%@: %@\r\n", key, header];
		[packet appendData:[header dataUsingEncoding:NSUTF8StringEncoding]];
	}
	
	//NSData *gzip = [myContent deflate];
	//NSLog(@"%@", [gzip descriptionAsString]);
	NSString *spacer = [NSString stringWithString:@"\r\n"];
	
	if ([myContent length] == 0)
	{
		NSString *contentLength = [NSString stringWithFormat:@"Content-Length: %u\r\n", [myContent length]];
		[packet appendData:[contentLength dataUsingEncoding:NSUTF8StringEncoding]];
	}
	else
	{
		[packet appendData:[spacer dataUsingEncoding:NSUTF8StringEncoding]];
		//append the content
#define DAVChunkSize 1024
		NSRange chunkRange = NSMakeRange(0,MIN(DAVChunkSize,[myContent length]));
		NSData *chunk;
		
		while (chunkRange.length > 0)
		{
			chunk = [myContent subdataWithRange:chunkRange];
			NSString *hexSize = [NSString stringWithFormat:@"%x\r\n", chunkRange.length];
			[packet appendData:[hexSize dataUsingEncoding:NSUTF8StringEncoding]];
			[packet appendData:chunk];
			[packet appendData:[spacer dataUsingEncoding:NSUTF8StringEncoding]];
			chunkRange.location = chunkRange.location + chunkRange.length;
			chunkRange.length = MIN(DAVChunkSize, [myContent length] - chunkRange.location);
		}
		[packet appendData:[@"0\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	}
	
	//[packet appendData:myContent];
	
	[packet appendData:[spacer dataUsingEncoding:NSUTF8StringEncoding]];
	[packet appendData:[spacer dataUsingEncoding:NSUTF8StringEncoding]];
	
	return packet;
}

- (DAVResponse *)responseWithData:(NSData *)data
{
	NSRange r = [DAVResponse canConstructResponseWithData:data];
	if (r.location != NSNotFound)
	{
		return [DAVResponse responseWithRequest:self data:data];
	}
	return nil;
}

@end

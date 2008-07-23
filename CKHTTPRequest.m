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
#import "CKHTTPResponse.h"
#import "NSString+Connection.h"
#import "NSData+Connection.h"

@implementation CKHTTPRequest

+ (id)requestWithMethod:(NSString *)method uri:(NSString *)uri
{
	return [[[CKHTTPRequest alloc] initWithMethod:method uri:uri] autorelease];
}

- (id)init
{
	if (self = [super init])
	{
		myHeaders = [[NSMutableDictionary dictionary] retain];
		myContent = [[NSMutableData data] retain];
		myPost = [[NSMutableDictionary dictionary] retain];
		myUploads = [[NSMutableDictionary dictionary] retain];
		
		NSString *userAgent = [[NSUserDefaults standardUserDefaults] objectForKey:@"CKUserAgent"];
		if (!userAgent)
			userAgent = @"Mac OS X Connection Kit http://opensource.utr-software.com/connection";
		[self setHeader:userAgent forKey:@"User-Agent"];
		
		// add date header
		NSCalendarDate *now = [NSCalendarDate date];
		[now setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		[self setHeader:[now descriptionWithCalendarFormat:@"%a, %d %b %Y %H:%M:%S %z"] forKey:@"Date"];
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
	[myPost release];
	[myUploads release];
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

- (NSDictionary *)headers
{
	return myHeaders;
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

- (void)setPostValue:(id)value forKey:(NSString *)key
{
	[myPost setObject:value forKey:key];
}

- (void)uploadFile:(NSString *)path forKey:(NSString *)key
{
	NSData *data = [NSData dataWithContentsOfFile:path];
	[self uploadData:data withFilename:[path lastPathComponent] forKey:key];
}

- (void)uploadData:(NSData *)data withFilename:(NSString *)name forKey:(NSString *)key
{
	[myUploads setObject:[NSDictionary dictionaryWithObjectsAndKeys:data, @"data", name, @"filename", nil]
				 forKey:key];
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

#define HTTPChunkSize 1024

- (void)serializeContentWithPacket:(NSMutableData *)packet
{
	NSString *stringBoundary = [NSString stringWithString:@"0xKhTmLbOuNdArY"];
	if ([myContent length] == 0)
	{
		if ([myPost count] > 0 || [myUploads count] > 0)
		{
			NSEnumerator *e = [myPost keyEnumerator];
			NSString *key;
			id value;
			
			while (key = [e nextObject])
			{
				[myContent appendData:[[NSString stringWithFormat:@"--%@\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
				[myContent appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key] dataUsingEncoding:NSUTF8StringEncoding]];
				value = [myPost objectForKey:key];
				if (![value isKindOfClass:[NSData class]])
				{
					value = [[value description] dataUsingEncoding:NSUTF8StringEncoding];
				}
				[myContent appendData:value];
				[myContent appendData:[[NSString stringWithFormat:@"\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
			}
			
			// do uploads
			e = [myUploads keyEnumerator];
			
			while (key = [e nextObject])
			{
				NSDictionary *rec = [myUploads objectForKey:key];
				NSString *filename = [rec objectForKey:@"filename"];
				NSData *data = [rec objectForKey:@"data"];
				NSString *UTI = [(NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
																				  (CFStringRef)[filename pathExtension],
																				  NULL) autorelease];
				NSString *mime = [(NSString *)UTTypeCopyPreferredTagWithClass((CFStringRef)UTI, kUTTagClassMIMEType) autorelease];	
				if (!mime || [mime length] == 0)
				{
					mime = @"application/octet-stream";
				}
				[myContent appendData:[[NSString stringWithFormat:@"--%@\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
				[myContent appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\nContent-Type: \"%@\"\r\n\r\n", key, filename, mime] dataUsingEncoding:NSUTF8StringEncoding]];
				[myContent appendData:data];
				[myContent appendData:[[NSString stringWithFormat:@"\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
			}
			[myContent appendData:[[NSString stringWithFormat:@"--%@\r\n\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
		}
	}
}

- (NSData *)serialized
{
	NSMutableData *packet = [NSMutableData data];
	NSString *request = [NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\n", myMethod, [myURI encodeLegally]];
	[packet appendData:[request dataUsingEncoding:NSUTF8StringEncoding]];
	//NSData *gzip = [myContent deflate];
	
//	if ([gzip length] < HTTPChunkSize)
//	{
//		[myHeaders removeObjectForKey:@"Transfer-Encoding"];
//		[myHeaders removeObjectForKey:@"Content-Coding"];
//	}
	
	//do the headers
	if ([myPost count] > 0 || [myUploads count] > 0)
	{
		[myHeaders removeObjectForKey:@"Content-Type"];
	}
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
	
	//NSLog(@"%@", [gzip descriptionAsUTF8String]);
	NSString *stringBoundary = [NSString stringWithString:@"0xKhTmLbOuNdArY"];
	NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@",stringBoundary];
	
	if ([myPost count] > 0 || [myUploads count] > 0)
	{
		[packet appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n", contentType] dataUsingEncoding:NSUTF8StringEncoding]];
	}
	
	[self serializeContentWithPacket:packet];
	
//	// add an md5 hash header
//	if ([myContent length] > 0)
//	{
//		NSString *md5 = [NSString stringWithFormat:@"Content-MD5: %%@\r\n", [[myContent md5Digest] base64Encoding]];
//		[packet appendData:[md5 dataUsingEncoding:NSUTF8StringEncoding]];
//	}
	
	//if ([gzip length] < HTTPChunkSize)
	{
		NSString *contentLength = [NSString stringWithFormat:@"Content-Length: %u\r\n\r\n", [myContent length]];
		[packet appendData:[contentLength dataUsingEncoding:NSUTF8StringEncoding]];
		
		myHeaderLength = [packet length];
		
		[packet appendData:myContent];
	}
	
	/*	else
	{
		[packet appendData:[spacer dataUsingEncoding:NSUTF8StringEncoding]];
		//append the content
		NSRange chunkRange = NSMakeRange(0,MIN(DAVChunkSize,[myContent length]));
		NSData *chunk;
		
		while (chunkRange.length > 0)
		{
			chunk = [gzip subdataWithRange:chunkRange];
			NSString *hexSize = [NSString stringWithFormat:@"%x\r\n", chunkRange.length];
			//NSLog(@"%@", hexSize);
			[packet appendData:[hexSize dataUsingEncoding:NSUTF8StringEncoding]];
			[packet appendData:chunk];
			[packet appendData:[spacer dataUsingEncoding:NSUTF8StringEncoding]];
			chunkRange.location = chunkRange.location + chunkRange.length;
			chunkRange.length = MIN(DAVChunkSize, [gzip length] - chunkRange.location);
		}
		[packet appendData:[@"0\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	}*/
	
	return packet;
}

- (unsigned)headerLength
{
	return myHeaderLength;
}

- (CKHTTPResponse *)responseWithData:(NSData *)data
{
	NSRange r = [CKHTTPResponse canConstructResponseWithData:data];
	if (r.location != NSNotFound)
	{
		return [CKHTTPResponse responseWithRequest:self data:data];
	}
	return nil;
}

@end

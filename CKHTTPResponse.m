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


#import "CKHTTPResponse.h"
#import "NSData+Connection.h"
#import "NSString+Connection.h"

static NSMutableDictionary *responseMap = nil;

@implementation CKHTTPResponse

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	responseMap = [[NSMutableDictionary dictionary] retain];
	[pool release];
}

+ (void)registerCustomResponseClass:(NSString *)response forRequestClass:(NSString *)request
{
	[responseMap setObject:response forKey:request];
}

+ (NSDictionary *)headersWithData:(NSData *)data
{
	NSMutableDictionary *headers = [NSMutableDictionary dictionary];
	
	NSRange headerRange = [data rangeOfData:[[NSString stringWithString:@"\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
	if (headerRange.location == NSNotFound)
		return headers;
	
	NSString *packet = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0,headerRange.location)] encoding:NSUTF8StringEncoding] autorelease];
	NSArray *lines = [packet componentsSeparatedByString:@"\r\n"];
	// we put in a try/catch to handle any unexpected/missing data
	@try {
		if ([lines count] > 1) // need the response line and at least a couple of blank lines
		{
			NSArray *response = [[lines objectAtIndex:0] componentsSeparatedByString:@" "];
			// HTTP/1.1 CODE NAME
			if ([[[response objectAtIndex:0] uppercaseString] isEqualToString:@"HTTP/1.1"])
			{
				[headers setObject:response forKey:@"Server-Response"];
				
				// now enumerate over the headers which will be if the line is empty
				int i, lineCount = [lines count];
				for (i = 1; i < lineCount; i++)
				{
					NSString *line = [lines objectAtIndex:i];
					if ([line isEqualToString:@""])
					{
						//we hit the end of the headers
						i++;
						break;
					}
					NSRange colon = [line rangeOfString:@":"];
					if (colon.location != NSNotFound)
					{
						NSString *key = [line substringToIndex:colon.location];
						NSString *val = [line substringFromIndex:colon.location + colon.length + 1];
						BOOL hasMultiValues = [val rangeOfString:@";"].location != NSNotFound;
						
						if (hasMultiValues)
						{
							NSArray *vals = [val componentsSeparatedByString:@";"];
							NSMutableArray *mutableVals = [NSMutableArray array];
							NSEnumerator *e = [vals objectEnumerator];
							NSString *cur;
							
							while (cur = [e nextObject])
							{
								[mutableVals addObject:[cur stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
							}
							[headers setObject:mutableVals forKey:key];
						}
						else
						{
							[headers setObject:val forKey:key];
						}
					}
				}
			}
		}
	}
	@catch (NSException *e) 
	{
		
	}
	return headers;
}

+ (NSRange)canConstructResponseWithData:(NSData *)data
{
	NSRange packetRange = NSMakeRange(NSNotFound, 0);
	NSRange headerRange = [data rangeOfData:[[NSString stringWithString:@"\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
	
	if (headerRange.location == NSNotFound)
	{
		return packetRange;
	}
	
	NSString *headerString = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0,headerRange.location)] encoding:NSUTF8StringEncoding] autorelease];
	NSArray *headerLines = [headerString componentsSeparatedByString:@"\r\n"];
	NSMutableDictionary *headers = [NSMutableDictionary dictionary];
	
	// we put in a try/catch to handle any unexpected/missing data
	@try {
		NSArray *response = [[headerLines objectAtIndex:0] componentsSeparatedByString:@" "];
		// HTTP/1.1 CODE NAME
		if ([[[response objectAtIndex:0] uppercaseString] isEqualToString:@"HTTP/1.1"])
		{
			//int responseCode = [[response objectAtIndex:1] intValue];
			
			if ([response count] >= 3)
			{
				//NSString *msg = [[response subarrayWithRange:NSMakeRange(2, [response count] - 2)] componentsJoinedByString:@" "];
			}
			
			// now enumerate over the headers which will be if the line is empty
			int i, lineCount = [headerLines count];
			for (i = 1; i < lineCount; i++)
			{
				NSString *line = [headerLines objectAtIndex:i];
				if ([line isEqualToString:@""])
				{
					//we hit the end of the headers
					i++;
					break;
				}
				NSRange colon = [line rangeOfString:@":"];
				if (colon.location != NSNotFound)
				{
					NSString *key = [line substringToIndex:colon.location];
					NSString *val = [line substringFromIndex:colon.location + colon.length + 1];
					BOOL hasMultiValues = [val rangeOfString:@";"].location != NSNotFound;
					
					if (hasMultiValues)
					{
						NSArray *vals = [val componentsSeparatedByString:@";"];
						NSMutableArray *mutableVals = [NSMutableArray array];
						NSEnumerator *e = [vals objectEnumerator];
						NSString *cur;
						
						while (cur = [e nextObject])
						{
							[mutableVals addObject:[cur stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
						}
						[headers setObject:mutableVals forKey:key];
					}
					else
					{
						[headers setObject:val forKey:key];
					}
				}
			}
		}
		BOOL isChunkedTransfer = NO;
		if ([headers objectForKey:@"Transfer-Encoding"])
		{
			if ([[[headers objectForKey:@"Transfer-Encoding"] lowercaseString] isEqualToString:@"chunked"])
			{
				isChunkedTransfer = YES;
			}
		}
		// now get the data range for the content
		unsigned start = NSMaxRange(headerRange);
		if (!isChunkedTransfer)
		{
			unsigned contentLength = [[headers objectForKey:@"Content-Length"] intValue];
			//S3 sends responses which are valid and complete but have Content-Length = 0. Confirmations of upload, delete, etc.
			BOOL isAmazonS3 = ([headers objectForKey:@"Server"] && [[headers objectForKey:@"Server"] isEqualToString:@"AmazonS3"]);
			if (contentLength > 0 || isAmazonS3) 
			{
				unsigned end = start + contentLength;
				
				if (end <= [data length]) //only update the packet range if it is all there
				{
					packetRange.location = 0;
					packetRange.length = end;
				}
			}
			else
			{
				return packetRange;
			}
		}
		else
		{
			NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
			NSData *newLineData = [[NSString stringWithFormat:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding];
			NSRange lengthRange = [data rangeOfData:newLineData range:NSMakeRange(start, [data length] - start)];
			NSString *lengthString = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(lengthRange.location - 4, 4)] encoding:NSUTF8StringEncoding] autorelease];
			NSScanner *scanner = [NSScanner scannerWithString:lengthString];
			unsigned chunkLength = 0;
			[scanner scanUpToCharactersFromSet:hexSet intoString:nil];
			[scanner scanHexInt:&chunkLength];
			
			while (chunkLength > 0)
			{
				//[self appendContent:[data subdataWithRange:NSMakeRange(NSMaxRange(lengthRange), chunkLength)]];
				
				lengthRange = [data rangeOfData:newLineData range:NSMakeRange(NSMaxRange(lengthRange) + chunkLength + 2, [data length] - NSMaxRange(lengthRange) - chunkLength - 2)];
				if (lengthRange.location == NSNotFound)
				{
					return packetRange;
				}
				lengthString = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(lengthRange.location - 4, 4)] encoding:NSUTF8StringEncoding] autorelease];
				scanner = [NSScanner scannerWithString:lengthString];
				[scanner scanUpToCharactersFromSet:hexSet intoString:nil];
				[scanner scanHexInt:&chunkLength];
			}
			
			// the end of range will be 0\r\n\r\n
			//NSRange end = [packet rangeOfString:@"0\r\n\r\n"];
			packetRange.location = 0;
			packetRange.length = NSMaxRange(lengthRange);
		}
	} 
	@catch (NSException *e) {
		// do nothing - we cannot parse properly
	}
	@finally {
		
	}
	return packetRange;
}

+ (id)responseWithRequest:(CKHTTPRequest *)request data:(NSData *)data
{
	//see if we map a certain request to a specific response
	NSString *clsStr = [responseMap objectForKey:NSStringFromClass([request class])];
	
	if (clsStr)
	{
		//	NSLog(@"Matched Request: %@ to %@", [request className], clsStr);
		return [[[NSClassFromString(clsStr) alloc] initWithRequest:request data:data] autorelease];
	}
	return [[[CKHTTPResponse alloc] initWithRequest:request data:data] autorelease];
}

- (id)initWithRequest:(CKHTTPRequest *)request data:(NSData *)data
{
	if (self = [super init])
	{
		myRequest = [request retain];
		if (!data || [data length] == 0)
		{
			return self;
		}
		NSRange headerRange = [data rangeOfData:[[NSString stringWithString:@"\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
		NSString *headerString = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0,headerRange.location)] encoding:NSUTF8StringEncoding] autorelease];
		NSArray *headerLines = [headerString componentsSeparatedByString:@"\r\n"];
		
		NSArray *response = [[headerLines objectAtIndex:0] componentsSeparatedByString:@" "]; // HTTP/1.1 CODE NAME
		myResponseCode = [[response objectAtIndex:1] intValue];
		if ([response count] >= 3)
		{
			NSString *msg = [[response subarrayWithRange:NSMakeRange(2, [response count] - 2)] componentsJoinedByString:@" "];
			myResponse = [msg copy];
		}
		
		// now enumerate over the headers which will be if the line is empty
		int i, lineCount = [headerLines count];
		for (i = 1; i < lineCount; i++)
		{
			NSString *line = [headerLines objectAtIndex:i];
			if ([line isEqualToString:@""])
			{
				//we hit the end of the headers
				break;
			}
			NSRange colon = [line rangeOfString:@":"];
			if (colon.location != NSNotFound)
			{
				NSString *key = [line substringToIndex:colon.location];
				NSString *val = [line substringFromIndex:colon.location + colon.length + 1];
				BOOL hasMultiValues = [val rangeOfString:@";"].location != NSNotFound;
				
				if (hasMultiValues)
				{
					NSArray *vals = [val componentsSeparatedByString:@";"];
					NSMutableArray *mutableVals = [NSMutableArray array];
					NSEnumerator *e = [vals objectEnumerator];
					NSString *cur;
					
					while (cur = [e nextObject])
					{
						[mutableVals addObject:[cur stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
					}
					[myHeaders setObject:mutableVals forKey:key];
				}
				else
				{
					[myHeaders setObject:val forKey:key];
				}
			}
		}
		BOOL isChunkedTransfer = NO;
		if ([myHeaders objectForKey:@"Transfer-Encoding"])
		{
			if ([[[myHeaders objectForKey:@"Transfer-Encoding"] lowercaseString] isEqualToString:@"chunked"])
			{
				isChunkedTransfer = YES;
			}
		}
		// now get the data range for the content
		unsigned start = NSMaxRange(headerRange);
		
		if (!isChunkedTransfer)
		{
			unsigned contentLength = [[myHeaders objectForKey:@"Content-Length"] intValue];
			if (contentLength > 0)
			{
				[self setContent:[data subdataWithRange:NSMakeRange(start, contentLength)]];
			}
			else
			{
				[self setContent:[data subdataWithRange:NSMakeRange(start, [data length] - start)]];
			}
		}
		else
		{
			NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
			NSRange lengthRange = [data rangeOfData:[[NSString stringWithString:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]
											  range:NSMakeRange(start, [data length] - start)];
			NSString *lengthString = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(lengthRange.location - 4, 4)] encoding:NSUTF8StringEncoding] autorelease];
			NSScanner *scanner = [NSScanner scannerWithString:lengthString];
			unsigned chunkLength = 0;
			[scanner scanUpToCharactersFromSet:hexSet intoString:nil];
			[scanner scanHexInt:&chunkLength];
			
			while (chunkLength > 0)
			{
				[self appendContent:[data subdataWithRange:NSMakeRange(NSMaxRange(lengthRange), chunkLength)]];
				
				lengthRange = [data rangeOfData:[[NSString stringWithString:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]
										  range:NSMakeRange(NSMaxRange(lengthRange) + chunkLength + 2, [data length] - NSMaxRange(lengthRange) - chunkLength - 2)];
				lengthString = [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(lengthRange.location - 4, 4)] encoding:NSUTF8StringEncoding] autorelease];
				scanner = [NSScanner scannerWithString:lengthString];
				[scanner scanUpToCharactersFromSet:hexSet intoString:nil];
				[scanner scanHexInt:&chunkLength];
			}
		}	
	}
	return self;
}

- (void)dealloc
{
	[myRequest release];
	[myResponse release];
	[super dealloc];
}

- (NSString *)description
{
	NSMutableString *str = [NSMutableString stringWithFormat:@"HTTP/1.1 %d %@\n", myResponseCode, myResponse];
	NSEnumerator *e = [myHeaders keyEnumerator];
	NSString *key;
	
	while (key = [e nextObject])
	{
		[str appendFormat:@"%@: %@\n", key, [[myHeaders objectForKey:key] description]];
	}
	//[str appendFormat:@"\n%@\n", [[self xmlDocument] XMLStringWithOptions:NSXMLNodePrettyPrint]];
	return str;
}

- (NSString *)formattedResponse
{
	return [self description];
}

- (NSString *)response
{
	return myResponse;
}

- (CKHTTPRequest *)request
{
	return myRequest;
}

- (int)code
{
	return myResponseCode;
}

@end


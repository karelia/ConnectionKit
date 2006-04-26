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

#import "DAVResponse.h"
#import "DAVDirectoryContentsRequest.h"
#import "DAVCreateDirectoryRequest.h"
#import "DAVUploadFileRequest.h"

#import "DAVDirectoryContentsResponse.h"
#import "DAVCreateDirectoryResponse.h"
#import "DAVUploadFileResponse.h"
#import "NSData+Connection.h"

#import "AbstractConnectionProtocol.h"


static NSMutableDictionary *responseMap = nil;

@implementation DAVResponse

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	responseMap = [[NSMutableDictionary dictionary] retain];
	[responseMap setObject:@"DAVDirectoryContentsResponse" forKey:@"DAVDirectoryContentsRequest"];
	[responseMap setObject:@"DAVCreateDirectoryResponse" forKey:@"DAVCreateDirectoryRequest"];
	[responseMap setObject:@"DAVUploadFileResponse" forKey:@"DAVUploadFileRequest"];
	[responseMap setObject:@"DAVDeleteResponse" forKey:@"DAVDeleteRequest"];
	[responseMap setObject:@"DAVFileDownloadResponse" forKey:@"DAVFileDownloadRequest"];
	
	[pool release];
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
	NSString *packet = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	NSArray *lines = [packet componentsSeparatedByString:@"\r\n"];
	// we put in a try/catch to handle any unexpected/missing data
	@try {
		if ([lines count] > 1) // need the response line and at least a couple of blank lines
		{
			NSArray *response = [[lines objectAtIndex:0] componentsSeparatedByString:@" "];
			// HTTP/1.1 CODE NAME
			if ([[[response objectAtIndex:0] uppercaseString] isEqualToString:@"HTTP/1.1"])
			{
				//int responseCode = [[response objectAtIndex:1] intValue];
				NSMutableDictionary *headers = [NSMutableDictionary dictionary];
				
				if ([response count] >= 3)
				{
					//NSString *msg = [[response subarrayWithRange:NSMakeRange(2, [response count] - 2)] componentsJoinedByString:@" "];
				}
				
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
				BOOL isChunkedTransfer = NO;
				if ([headers objectForKey:@"Transfer-Encoding"])
				{
					if ([[[headers objectForKey:@"Transfer-Encoding"] lowercaseString] isEqualToString:@"chunked"])
					{
						isChunkedTransfer = YES;
					}
				}
				// now get the data range for the content
				// if we append the previous line to the blank line it will pick up the search for the range
				NSRange contentStart = [packet rangeOfString:[NSString stringWithFormat:@"%@%@", [lines objectAtIndex:i-2], [lines objectAtIndex:i-1]]];
				
				if (contentStart.location != NSNotFound)
				{
					unsigned start = contentStart.location + contentStart.length;
					if (!isChunkedTransfer)
					{
						// The end will be the next two line feeds past the start of the content provided there is a content length
						if ([[headers objectForKey:@"Content-Length"] intValue] > 0)
						{
							NSRange contentEnd = [packet rangeOfString:@"\r\n\r\n" 
															   options:NSLiteralSearch 
																 range:NSMakeRange(start, [packet length] - start)];
							unsigned end = contentEnd.location != NSNotFound ? contentEnd.location + contentEnd.length : [packet length] - start;
							//NSString *content = [packet substringWithRange:NSMakeRange(start, end)];
							//NSData *cd = [content dataUsingEncoding:NSUTF8StringEncoding];
							
							packetRange.location = 0;
							packetRange.length = end;
						}
						else
						{
							// it must be just a response with just headers
							packetRange.location = 0;
							packetRange.length = start + 4; //2 extra for the \r\n 
						}
					}
					else
					{
						NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
						NSScanner *scanner = [NSScanner scannerWithString:[packet substringWithRange:NSMakeRange(start, [packet length] - start)]];
						unsigned chunkLength = 0;
						[scanner scanHexInt:&chunkLength];
						[scanner scanCharactersFromSet:ws intoString:nil];
						NSMutableString *content = [NSMutableString string];
						
						while (chunkLength > 0)
						{
							
							NSString *chunk = nil;
							[scanner scanUpToString:@"\r\n" intoString:&chunk];
							[content appendString:chunk];
							[scanner scanString:@"\r\n" intoString:nil];
							[scanner scanHexInt:&chunkLength];
						}
						
						// the end of range will be 0\r\n\r\n
						NSRange end = [packet rangeOfString:@"0\r\n\r\n"];
						packetRange.location = 0;
						packetRange.length = end.location + end.length;
					}
				}
			}
		}
	} 
	@catch (NSException *e) {
		// do nothing - we cannot parse properly
	}
	@finally {
		
	}
	return packetRange;
}

+ (id)responseWithRequest:(DAVRequest *)request data:(NSData *)data
{
	//see if we map a certain request to a specific response
	NSString *clsStr = [responseMap objectForKey:NSStringFromClass([request class])];
	
	if (clsStr)
	{
	//	NSLog(@"Matched Request: %@ to %@", [request className], clsStr);
		return [[[NSClassFromString(clsStr) alloc] initWithRequest:request data:data] autorelease];
	}
	return [[[DAVResponse alloc] initWithRequest:request data:data] autorelease];
}

- (id)initWithRequest:(DAVRequest *)request data:(NSData *)data
{
	if (self = [super init])
	{
		myRequest = [request retain];
		NSString *packet = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSArray *lines = [packet componentsSeparatedByString:@"\r\n"];
		if ([lines count] > 1) // need the response line and at least a couple of blank lines
		{
			NSArray *response = [[lines objectAtIndex:0] componentsSeparatedByString:@" "];
			// HTTP/1.1 CODE NAME
			if ([[[response objectAtIndex:0] uppercaseString] isEqualToString:@"HTTP/1.1"])
			{
				myResponseCode = [[response objectAtIndex:1] intValue];
				if ([response count] >= 3)
				{
					NSString *msg = [[response subarrayWithRange:NSMakeRange(2, [response count] - 2)] componentsJoinedByString:@" "];
					myResponse = [msg copy];
				}
				
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
				// if we append the previous line to the blank line it will pick up the search for the range
				NSString *myTemp = [NSString stringWithFormat:@"%@%@", [lines objectAtIndex:i-2], [lines objectAtIndex:i-1]];
				NSRange contentStart = [packet rangeOfString:myTemp];
				
				if (contentStart.location != NSNotFound)
				{
					unsigned start = contentStart.location + contentStart.length;
					if (!isChunkedTransfer)
					{
						if ([[myHeaders objectForKey:@"Content-Length"] intValue] > 0)
						{
							// The end will be the next two line feeds past the start of the content
							NSRange contentEnd = [packet rangeOfString:@"\r\n\r\n" 
															   options:NSLiteralSearch 
																 range:NSMakeRange(start, [packet length] - start)];
							unsigned end = contentEnd.location != NSNotFound ? contentEnd.location + contentEnd.length : [packet length] - start;
							NSString *content = [packet substringWithRange:NSMakeRange(start, end)];
							NSData *cd = [content dataUsingEncoding:NSUTF8StringEncoding];
							
							[self setContent:cd];
						}
					}
					else
					{
						NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
						NSScanner *scanner = [NSScanner scannerWithString:[packet substringWithRange:NSMakeRange(start, [packet length] - start)]];
						unsigned chunkLength = 0;
						[scanner scanHexInt:&chunkLength];
						[scanner scanCharactersFromSet:ws intoString:nil];
						NSMutableString *content = [NSMutableString string];
						
						while (chunkLength > 0)
						{
							NSString *chunk = nil;
							[scanner scanUpToString:@"\r\n" intoString:&chunk];
							[content appendString:chunk];
							[scanner scanString:@"\r\n" intoString:nil];
							[scanner scanHexInt:&chunkLength];
						}
						[self setContentString:content];
					}
				}
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

- (NSXMLDocument *)xmlDocument
{
	//do we want to use NSXMLDocumentValidate? 
	NSError *err = nil;
	NSXMLDocument *xml = [[NSXMLDocument alloc] initWithData:myContent
													 options:NSXMLDocumentValidate
													   error:&err];
	if (err)
	{
		NSLog(@"Failed to create NSXMLDocument: %@", err);
	}
	return [xml autorelease];
}

- (DAVRequest *)request
{
	return myRequest;
}

- (int)code
{
	return myResponseCode;
}

@end

@implementation NSCalendarDate (Connection)
/*
 We will try and guess the date by trying these formats
 -----------------
 Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
 Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
 Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format
 2006-02-05T23:22:39Z			; ISO 8601 date format
 */
+ (id)calendarDateWithString:(NSString *)string
{
	NSCalendarDate *date = nil;
	// Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
	date = [NSCalendarDate dateWithString:string calendarFormat:@"%a, %d %b %Y %H:%M:%S %Z"];
	if (date)
	{
		return date;
	}
	// Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
	date = [NSCalendarDate dateWithString:string calendarFormat:@"%A, %d-%b-%y %H:%M:%S %Z"];
	if (date)
	{
		return date;
	}
	// Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format
	date = [NSCalendarDate dateWithString:string calendarFormat:@"%a %b %e %H:%M:%S %Y"];
	if (date)
	{
		return date;
	}
	// 2006-02-05T23:22:39Z			; ISO 8601 date format
	if ([string hasSuffix:@"Z"])
	{
		date = [NSCalendarDate dateWithString:string calendarFormat:@"%Y-%m-%dT%H:%M:%SZ"];
		if (date)
		{
			return date;
		}
	}
	else
	{
		date = [NSCalendarDate dateWithString:string calendarFormat:@"%Y-%m-%dT%H:%M:%S%z"];
		if (date)
		{
			return date;
		}
	}
	return date;
}

@end

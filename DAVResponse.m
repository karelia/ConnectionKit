/*
 Copyright (c) 2004, Greg Hulands <ghulands@framedphotographics.com>
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
#import "AbstractConnectionProtocol.h"

static NSMutableDictionary *responseMap = nil;

@implementation DAVResponse

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	responseMap = [[NSMutableDictionary dictionary] retain];
	[responseMap setObject:NSStringFromClass([DAVDirectoryContentsResponse class]) forKey:NSStringFromClass([DAVDirectoryContentsRequest class])];
	
	[pool release];
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
				int responseCode = [[response objectAtIndex:1] intValue];
				NSMutableDictionary *headers = [NSMutableDictionary dictionary];
				
				if ([response count] >= 3)
				{
					NSString *msg = [[response subarrayWithRange:NSMakeRange(2, [response count] - 2)] componentsJoinedByString:@" "];
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
						// The end will be the next two line feeds past the start of the content
						NSRange contentEnd = [packet rangeOfString:@"\r\n\r\n" 
														   options:NSLiteralSearch 
															 range:NSMakeRange(start, [packet length] - start)];
						unsigned end = contentEnd.location != NSNotFound ? [packet length] - (contentEnd.location + contentEnd.length) : [packet length] - start;
						NSString *content = [packet substringWithRange:NSMakeRange(start, end)];
						NSData *cd = [content dataUsingEncoding:NSUTF8StringEncoding];
						
						packetRange.location = 0;
						packetRange.length = end;
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
						// The end will be the next two line feeds past the start of the content
						NSRange contentEnd = [packet rangeOfString:@"\r\n\r\n" 
														   options:NSLiteralSearch 
															 range:NSMakeRange(start, [packet length] - start)];
						unsigned end = contentEnd.location != NSNotFound ? [packet length] - (contentEnd.location + contentEnd.length) : [packet length] - start;
						NSString *content = [packet substringWithRange:NSMakeRange(start, end)];
						NSData *cd = [content dataUsingEncoding:NSUTF8StringEncoding];
						[self appendContent:cd];
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
		NSLog(@"%@", err);
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

@implementation DAVDirectoryContentsResponse : DAVResponse

- (NSString *)path
{
	if ([[self request] isKindOfClass:[DAVDirectoryContentsRequest class]])
	{
		return [(DAVDirectoryContentsRequest *)[self request] path];
	}
}

- (NSArray *)directoryContents
{
	NSMutableArray *contents = [NSMutableArray array];
	NSXMLDocument *doc = [self xmlDocument];
	NSXMLElement *xml = [doc rootElement];
	
	NSArray *responses = [xml elementsForLocalName:@"response" URI:@"DAV:"];
	NSEnumerator *e = [responses objectEnumerator];
	NSXMLElement *response;
	
	while (response = [e nextObject])
	{
		NSMutableDictionary *attribs = [NSMutableDictionary dictionary];
		NSLog(@"\n%@", [response XMLStringWithOptions:NSXMLNodePrettyPrint]);
		
		NSString *href = [[[response elementsForLocalName:@"href" URI:@"DAV:"] objectAtIndex:0] stringValue];
			
		if ([href isEqualToString:[self path]])
		{
			continue;
		}
		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@%@", [self headerForKey:@"Host"], href]];
		NSString *path = [url path];

		[attribs setObject:href forKey:@"DAVURI"];
		[attribs setObject:[path lastPathComponent] forKey:cxFilenameKey];
		
		[contents addObject:attribs];
	}
	
	
	return contents;
}

- (NSString *)formattedResponse
{
	NSMutableString *s = [NSMutableString stringWithFormat:@"Directory Listing for %@:\n", [self path]];
	NSEnumerator *e = [[self directoryContents] objectEnumerator];
	NSDictionary *cur;
	
	while (cur = [e nextObject])
	{
		[s appendFormat:@"%@\n", [cur objectForKey:cxFilenameKey]];
	}
	
	return s;
}

@end

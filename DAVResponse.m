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


@implementation DAVResponse

+ (BOOL)canConstructResponseWithData:(NSData *)data
{
	return NO;
}

+ (id)responseWithRequest:(DAVRequest *)request data:(NSData *)data
{
	
}

- (id)initWithRequest:(DAVRequest *)request data:(NSData *)data
{
	if (self = [super init])
	{
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
					if ([line isEqualToString:@"\r\n"])
					{
						//we hit the end of the headers
						break;
					}
					NSRange colon = [line rangeOfString:@":"];
					if (colon.location != NSNotFound)
					{
						NSString *key = [line substringToIndex:colon.location - 1];
						NSString *val = [line substringFromIndex:colon.location + 1];
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
				// now get the data range for the content
				
				
			}
		}
	}
	return self;
}

- (NSXMLDocument *)xmlDocument
{
	//do we want to use NSXMLDocumentValidate? 
	return [[[NSXMLDocument alloc] initWithData:myContent
										options:NSXMLDocumentTidyXML
										  error:nil] autorelease];
}


@end

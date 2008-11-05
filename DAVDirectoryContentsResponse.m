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


#import "DAVDirectoryContentsResponse.h"
#import "DAVDirectoryContentsRequest.h"
#import "AbstractConnectionProtocol.h"
#import "NSCalendarDate+Connection.h"
#import "NSString+Connection.h"

@implementation DAVDirectoryContentsResponse : DAVResponse

- (NSString *)path
{
	if ([[self request] isKindOfClass:[DAVDirectoryContentsRequest class]])
	{
		return [(DAVDirectoryContentsRequest *)[self request] path];
	}
	return nil;
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
		
		// filename
		NSArray *hrefElements = [response elementsForLocalName:@"href" URI:@"DAV:"];
		if ([hrefElements count] <= 0)
			continue;
		NSString *href = [[hrefElements objectAtIndex:0] stringValue];
		
		NSURL *url = nil;
		//If we have the http prefix already, we already have a full URL.
		if ([href hasPrefix:@"http://"])
			url = [NSURL URLWithString:href];
		else
			url = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@%@", [self headerForKey:@"Host"], href]];
		NSString *path = [url path];
		
		NSString *standardizedPathForComparison = [path stringByStandardizingHTTPPath];
		NSString *standardizedCurrentPathForComparison = [[self path] stringByStandardizingHTTPPath];		
		if ([path isEqualToString:@"/"] || [standardizedPathForComparison isEqualToString:standardizedCurrentPathForComparison])
			continue;
		
		[attribs setObject:href forKey:@"DAVURI"];
		[attribs setObject:[path lastPathComponent] forKey:cxFilenameKey];
		
		NSArray *propstatElements = [response elementsForLocalName:@"propstat" URI:@"DAV:"];
		//We do not always have property elements.
		if ([propstatElements count] > 0)
		{
			NSXMLElement *props = [[[propstatElements objectAtIndex:0] elementsForLocalName:@"prop" URI:@"DAV:"] objectAtIndex:0];
			
			@try {
				NSString *createdDateString = [[[props elementsForLocalName:@"creationdate" URI:@"DAV:"] objectAtIndex:0] stringValue];
				NSCalendarDate *created = [NSCalendarDate calendarDateWithString:createdDateString];
				[attribs setObject:created forKey:NSFileCreationDate];
			} 
			@catch (NSException *e) {
				
			}
			
			@try {
				NSString *modifiedDateString = [[[props elementsForLocalName:@"getlastmodified" URI:@"DAV:"] objectAtIndex:0] stringValue];
				NSCalendarDate *modified = [NSCalendarDate calendarDateWithString:modifiedDateString];
				[attribs setObject:modified forKey:NSFileModificationDate];
			}
			@catch (NSException *e) {
				
			}
			
			@try {
				// we could be a directory
				if ([[props elementsForLocalName:@"getcontentlength" URI:@"DAV:"] count] > 0)
				{
					NSString *sizeString = [[[props elementsForLocalName:@"getcontentlength" URI:@"DAV:"] objectAtIndex:0] stringValue];
					NSScanner *sizeScanner = [NSScanner scannerWithString:sizeString];
					
					long long size;
					[sizeScanner scanLongLong:&size];
					[attribs setObject:[NSNumber numberWithLongLong:size] forKey:NSFileSize];
				}
			}
			@catch (NSException *e) {
				
			}

			//see if we are a directory or file
			NSXMLElement *resourceType = [[props elementsForLocalName:@"resourcetype" URI:@"DAV:"] objectAtIndex:0];
			if ([resourceType childCount] == 0)
			{
				[attribs setObject:NSFileTypeRegular forKey:NSFileType];
			}
			else
			{
				// WebDAV does not support the notion of Symbolic Links so currently we can take it to be a directory if the node has any children
				[attribs setObject:NSFileTypeDirectory forKey:NSFileType];
			}
		}
		else
		{
			if ([path hasSuffix:@"/"])
				[attribs setObject:NSFileTypeDirectory forKey:NSFileType];
			else
				[attribs setObject:NSFileTypeRegular forKey:NSFileType];
		}
		
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
		[s appendFormat:@"%@\t\t\t%@\n", [cur objectForKey:NSFileModificationDate], [cur objectForKey:cxFilenameKey]];
	}
	
	return s;
}

@end


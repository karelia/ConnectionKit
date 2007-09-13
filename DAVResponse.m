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

#import "DAVResponse.h"
#import "DAVDirectoryContentsRequest.h"
#import "DAVCreateDirectoryRequest.h"
#import "DAVUploadFileRequest.h"

#import "DAVDirectoryContentsResponse.h"
#import "DAVCreateDirectoryResponse.h"
#import "DAVUploadFileResponse.h"
#import "NSData+Connection.h"

#import "AbstractConnectionProtocol.h"

@implementation DAVResponse

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
	[CKHTTPResponse registerCustomResponseClass:@"DAVDirectoryContentsResponse" forRequestClass:@"DAVDirectoryContentsRequest"];
	[CKHTTPResponse registerCustomResponseClass:@"DAVCreateDirectoryResponse" forRequestClass:@"DAVCreateDirectoryRequest"];
	[CKHTTPResponse registerCustomResponseClass:@"DAVUploadFileResponse" forRequestClass:@"DAVUploadFileRequest"];
	[CKHTTPResponse registerCustomResponseClass:@"DAVDeleteResponse" forRequestClass:@"DAVDeleteRequest"];
	[CKHTTPResponse registerCustomResponseClass:@"DAVFileDownloadResponse" forRequestClass:@"DAVFileDownloadRequest"];
		
	[pool release];
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

@end

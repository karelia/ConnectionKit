//
//  CKHTTPPutRequest.m
//  Connection
//
//  Created by Greg Hulands on 21/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKHTTPPutRequest.h"


@implementation CKHTTPPutRequest

- (id)initWithMethod:(NSString *)method uri:(NSString *)uri data:(NSData *)data filename:(NSString *)filename
{
	if ((self = [super initWithMethod:method uri:uri]))
	{
		[myContent appendData:data];
		myFilename = [filename copy];
		
		if (!data)
		{
			NSFileManager *fm = [NSFileManager defaultManager];
			if ([fm fileExistsAtPath:myFilename])
			{
				[myContent appendData:[NSData dataWithContentsOfFile:myFilename]];
			}
		}
		
		NSString *UTI = (NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
																		  (CFStringRef)[myFilename pathExtension],
																		  NULL);
		NSString *mime = (NSString *)UTTypeCopyPreferredTagWithClass((CFStringRef)UTI, kUTTagClassMIMEType);	
		if (!mime || [mime length] == 0)
		{
			mime = @"application/octet-stream";
		}
		
		[self setHeader:mime forKey:@"Content-Type"];
	}
	return self;
}

+ (id)putRequestWithData:(NSData *)data filename:(NSString *)filename uri:(NSString *)uri
{
	return [[[CKHTTPPutRequest alloc] initWithMethod:@"PUT" uri:uri data:data filename:filename] autorelease];
}

+ (id)putRequestWithContentsOfFile:(NSString *)path uri:(NSString *)uri
{
	return [[[CKHTTPPutRequest alloc] initWithMethod:@"PUT" uri:uri data:nil filename:path] autorelease];
}

- (void)dealloc
{
	[myFilename release];
	[super dealloc];
}

- (void)serializeContentWithPacket:(NSMutableData *)packet
{
	
}

@end

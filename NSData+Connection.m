//
//  NSData+Connection.m
//  FTPConnection
//
//  Created by Greg Hulands on 3/04/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "NSData+Connection.h"


@implementation NSData (Connection)

- (NSString *)base64Encoding
{
	const char *buffer = (const char *)[self bytes];
	size_t size = [self length];
	char *dest = nil;
	
	size_t new_size = Curl_base64_encode(buffer, size, &dest);
	NSString *result = [[[NSString alloc] initWithBytesNoCopy:dest length:new_size encoding:NSASCIIStringEncoding freeWhenDone:YES] autorelease];
	return result;
}

@end

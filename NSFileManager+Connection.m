//
//  NSFileManager+Connection.m
//  Connection
//
//  Created by Greg Hulands on 16/03/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "NSFileManager+Connection.h"


@implementation NSFileManager (Connection)

- (void)recursivelyCreateDirectory:(NSString *)path attributes:(NSDictionary *)attributes
{
	BOOL isDir;
	
	if (![self fileExistsAtPath:path isDirectory:&isDir] && isDir)
	{
		NSRange r = [path rangeOfString:@"/"];
		while (r.location != NSNotFound)
		{
			NSString *subpath = [path substringWithRange:NSMakeRange(0,NSMaxRange(r))];
			if (![self fileExistsAtPath:subpath isDirectory:&isDir] && isDir)
			{
				[self createDirectoryAtPath:subpath attributes:attributes];
			}
			r = [path rangeOfString:@"/" options:NSLiteralSearch range:NSMakeRange(NSMaxRange(r), [path length] - NSMaxRange(r))];
		}
		[self createDirectoryAtPath:path attributes:attributes];
	}
}

- (unsigned long long)sizeOfPath:(NSString *)path
{
	NSDictionary *attribs = [self fileAttributesAtPath:path traverseLink:NO];
	if (attribs)
	{
		return [[attribs objectForKey:NSFileSize] unsignedLongLongValue];
	}
	return 0;
}

@end

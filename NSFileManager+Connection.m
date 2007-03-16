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
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir;
	
	if (![fm fileExistsAtPath:path isDirectory:&isDir] && isDir)
	{
		NSRange r = [path rangeOfString:@"/"];
		while (r.location != NSNotFound)
		{
			NSString *subpath = [path substringWithRange:NSMakeRange(0,NSMaxRange(r))];
			if (![fm fileExistsAtPath:subpath isDirectory:&isDir] && isDir)
			{
				[fm createDirectoryAtPath:subpath attributes:attributes];
			}
			r = [path rangeOfString:@"/" options:NSLiteralSearch range:NSMakeRange(NSMaxRange(r), [path length] - NSMaxRange(r))];
		}
		[fm createDirectoryAtPath:path attributes:attributes];
	}
}

@end

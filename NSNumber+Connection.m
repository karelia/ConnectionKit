//
//  NSNumber+Connection.m
//  Connection
//
//  Created by Greg Hulands on 7/09/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "NSNumber+Connection.h"


@implementation NSNumber (Connection)

- (BOOL)isExecutable
{
	unsigned long perms = [self unsignedLongValue];
	
	if (perms & 0100) return YES;
	if (perms & 010) return YES;
	if (perms & 01) return YES;
	
	return NO;
}

- (NSString *)permissionsStringValue
{
	NSMutableString *str = [NSMutableString string];
	unsigned long perm = [self unsignedLongValue];
	
	//owner
	if (perm & 0400)
	{
		[str appendString:@"r"];
	}
	else
	{
		[str appendString:@"-"];
	}
	if (perm & 0200)
	{
		[str appendString:@"w"];
	}
	else
	{
		[str appendString:@"-"];
	}
	if (perm & 0100)
	{
		[str appendString:@"x"];
	}
	else
	{
		[str appendString:@"-"];
	}

	//group
	if (perm & 040)
	{
		[str appendString:@"r"];
	}
	else
	{
		[str appendString:@"-"];
	}
	if (perm & 020)
	{
		[str appendString:@"w"];
	}
	else
	{
		[str appendString:@"-"];
	}
	if (perm & 010)
	{
		[str appendString:@"x"];
	}
	else
	{
		[str appendString:@"-"];
	}
	
	//world
	if (perm & 04)
	{
		[str appendString:@"r"];
	}
	else
	{
		[str appendString:@"-"];
	}
	if (perm & 02)
	{
		[str appendString:@"w"];
	}
	else
	{
		[str appendString:@"-"];
	}
	if (perm & 01)
	{
		[str appendString:@"x"];
	}
	else
	{
		[str appendString:@"-"];
	}
	return str;
}

@end

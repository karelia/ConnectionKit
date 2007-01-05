//
//  NSDictionary+Connection.m
//  Connection
//
//  Created by Greg Hulands on 31/12/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "NSDictionary+Connection.h"
#import "NSObject+Connection.h"

@implementation NSDictionary (Connection)

- (NSString *)shortDescription
{
	NSMutableString *str = [NSMutableString stringWithFormat:@"%@ [%d keys]\n(\n", [self className], [[self allKeys] count]];
	NSEnumerator *e = [self keyEnumerator];
	id key;
	
	while ((key = [e nextObject]))
	{
		[str appendFormat:@"\t%@ = %@,\n", key, [[self objectForKey:key] shortDescription]];
	}
	[str deleteCharactersInRange:NSMakeRange([str length] - 2,2)];
	[str appendFormat:@"\n);"];
	
	return str;
}

@end

//
//  NSArray+Connection.m
//  Connection
//
//  Created by Greg Hulands on 31/12/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "NSArray+Connection.h"
#import "NSObject+Connection.h"

@implementation NSArray (Connection)

#define NSARRAY_MAXIMUM_DESCRIBED 20

- (NSString *)shortDescription
{
	NSMutableString *str = [NSMutableString stringWithFormat:@"%@ [%d items]\n(\n", [self className], [self count]];
	
	unsigned i, c = MIN([self count], NSARRAY_MAXIMUM_DESCRIBED);
	
	for (i = 0; i < c; i++)
	{
		[str appendFormat:@"\t%@,\n", [[self objectAtIndex:i] shortDescription]];
	}
	[str deleteCharactersInRange:NSMakeRange([str length] - 2,2)];
	[str appendFormat:@"\n);"];
	
	return str;
}

@end

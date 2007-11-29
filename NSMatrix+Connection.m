//
//  NSMatrix+Connection.m
//  Connection
//
//  Created by Greg Hulands on 29/11/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "NSMatrix+Connection.h"


@implementation NSMatrix (Connection)

- (NSBrowser *)browser
{
	NSView *superView = [self superview];
	
	while (superView)
	{
		if ([superView isKindOfClass:[NSBrowser class]])
		{
			return (NSBrowser *)superView;
		}
		superView = [superView superview];
	}
	return nil;
}

@end

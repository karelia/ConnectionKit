//
//  NSTabView+Connection.m
//  Connection
//
//  Created by Greg Hulands on 29/08/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "NSTabView+Connection.h"


@implementation NSTabView (Connection)

- (unsigned)indexOfSelectedTabViewItem
{
	NSTabViewItem *item = [self selectedTabViewItem];
	return [[self tabViewItems] indexOfObject:item];
}

@end

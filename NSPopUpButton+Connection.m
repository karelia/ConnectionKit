//
//  NSPopUpButton+Connection.m
//  Connection
//
//  Created by Greg Hulands on 29/08/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "NSPopUpButton+Connection.h"


@implementation NSPopUpButton (Connection)

- (void)selectItemWithRepresentedObject:(id)representedObject
{
	NSArray *items = [self itemArray];
	NSEnumerator *e = [items objectEnumerator];
	NSMenuItem *cur;
	int i = 0;
	
	while ((cur = [e nextObject]))
	{
		if ([[cur representedObject] isEqual:representedObject]) {
			i++;
			break;
		}
		
	}
	if (cur)
		[self selectItem:cur];
}

- (id)representedObjectOfSelectedItem
{
	return [[self selectedItem] representedObject];
}

@end

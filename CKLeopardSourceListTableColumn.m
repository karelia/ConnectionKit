//
//  LeopardSourceListTableColumn.m
//
//  Created by Brian Amerige on 1/26/08.
//  Copyright 2008 Extendmac, LLC. All rights reserved.
//

#import "CKBookmarkStorage.h"
#import "CKLeopardSourceListTableColumn.h"

@implementation CKLeopardSourceListTableColumn

- (id)dataCellForRow:(int)row
{
	if (row >= 0)
	{
		id item = [(NSOutlineView *)[self tableView] itemAtRow:row];
		if ([[CKBookmarkStorage sharedBookmarkStorage] itemIsLeopardSourceGroupHeader:item])
		{
			NSTextFieldCell *groupCell = [[[NSTextFieldCell alloc] init] autorelease];
			[groupCell setFont:[[NSFontManager sharedFontManager] convertFont:[[self dataCell] font] toSize:11.0]];
			[groupCell setLineBreakMode:[[self dataCell] lineBreakMode]];
			
			return groupCell;
		}
	}
	return [self dataCell];
}

@end
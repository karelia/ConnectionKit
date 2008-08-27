//
//  CKCollectionBasedBookmarkController.m
//  Connection
//
//  Created by Greg Hulands on 20/09/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "CKCollectionBasedBookmarkController.h"


@implementation CKCollectionBasedBookmarkController

- (id)init
{
	if ((self != [super init]))
	{
		
	}
	return self;
}

- (void)setCollectionView:(NSTableView *)collectionView bookmarkView:(NSOutlineView *)bookmarkView
{
	[oCollections setDataSource:nil];
	[oBookmarks setDataSource:nil];
	
	oCollections = collectionView;
	oBookmarks = bookmarkView;
	
	[oCollections setDataSource:self];
	[oBookmarks setDataSource:self];
}

- (void)selectItem:(id)item
{
}

- (id)selectedItem
{
	return nil;
}

#pragma mark -
#pragma mark Data Source Helper Methods


#pragma mark -
#pragma mark NSTableView Data Source

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return 0;
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	return nil;
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	
}

#pragma mark -
#pragma mark NSOutlineView Data Source

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	return 0;
}



@end

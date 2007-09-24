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
	
}

#pragma mark -
#pragma mark Data Source Helper Methods


#pragma mark -
#pragma mark NSTableView Data Source

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	
}

#pragma mark -
#pragma mark NSOutlineView Data Source

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	
}



@end

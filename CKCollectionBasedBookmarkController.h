//
//  CKCollectionBasedBookmarkController.h
//  Connection
//
//  Created by Greg Hulands on 20/09/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

/* Similar to how safari, transmit and other applications that have bookmarks with the collections 
   table on the left and the bookmarks on the right. It uses the ConnectionRegistry class to populate
   the views
*/
@interface CKCollectionBasedBookmarkController : NSObject 
{
	NSTableView *oCollections;
	NSOutlineView *oBookmarks;
	
	id myDelegate;
}

- (id)init;

- (void)setCollectionView:(NSTableView *)collectionView bookmarkView:(NSOutlineView *)bookmarkView;

- (void)selectItem:(id)item;
- (id)selectedItem;

@end

@interface NSObject (CKCollectionBasedBookmarkControllerDelegate)

- (void)collectionBookmarks:(CKCollectionBasedBookmarkController *)controller selectedItem:(id)item;

@end

//
//  CKDirectoryBrowserCell.h
//  UberUpload
//
//  Created by Bryan Hansen on 11/28/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "CKDirectoryNode.h"
#import <Cocoa/Cocoa.h>

// these cells are passed an NSDictionary with keys name and icon to the objectValue of the cell
@interface CKDirectoryBrowserCell : NSBrowserCell {
	BOOL myMakingDragImage;
}

- (void)setMakeDragImage:(BOOL)flag;

@end

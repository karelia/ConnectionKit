/*
 Copyright (c) 2007, Ubermind, Inc
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Ubermind, Inc nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 Authored by Greg Hulands <ghulands@mac.com>
 */

#import "CKDirectoryTreeController.h"
#import "CKDirectoryBrowserCell.h"
#import "CKDirectoryNode.h"
#import "NSTabView+Connection.h"
#import "NSPopUpButton+Connection.h"
#import "AbstractConnectionProtocol.h"
#import "NSString+Connection.h"
#import "NSNumber+Connection.h"
#import "CKTableBasedBrowser.h"

#define PADDING 5
#define ICON_INSET_VERT		2.0	/* The size of empty space between the icon end the top/bottom of the cell */ 
#define ICON_SIZE			16.0/* Our Icons are ICON_SIZE x ICON_SIZE */
#define ICON_INSET_HORIZ	4.0	/* Distance to inset the icon from the left edge. */
#define ICON_TEXT_SPACING	2.0	/* Distance between the end of the icon and the text part */

#define FILE_NAVIGATION_DELAY 0.2

enum {
	CKBackButton = 0,
	CKForwardButton
};

NSString *cxRemoteFilenamesPBoardType = @"cxRemoteFilenamesPBoardType";
NSString *cxLocalFilenamesPBoardType = @"cxLocalFilenamesPBoardType";

@interface CKDirectoryTreeController (Private)
- (void)_changeRelativeRootToPath:(NSString *)path;
- (NSString *)_browserPathForPath:(NSString *)path;
- (void)_setupInspectorView:(CKDirectoryNode *)node;
- (BOOL)_isFiltering;
- (void)_updatePopUpToPath:(NSString *)path;
- (void)_pruneHistoryWithPath:(NSString *)path;
- (void)_navigateToPath:(NSString *)path pushToHistoryStack:(BOOL)flag;
- (NSArray *)_selectedItems;
- (void)_updateHistoryButtons;
- (NSString *)_cellDisplayNameWithNode:(CKDirectoryNode *)node;
- (void)_reloadViewsAutoExpandingNodes:(BOOL)flag;
- (void)_reloadViews;
- (void)_resetSearch;
@end

@interface CKTableBasedBrowser (Private)
- (void)setDefaultColumnWidth:(float)width;
- (void)refreshColumn:(unsigned)col;
- (void)setPath:(NSString *)path checkPath:(BOOL)flag;
@end

@interface NSOutlineView (CKScrollToTop)
- (void)scrollItemToTop:(id)item;
@end

@interface CKDirectoryNode (Private)
- (void)setName:(NSString *)name;
@end

@implementation CKDirectoryTreeController (Private)

- (void)_changeRelativeRootToPath:(NSString *)path
{
	[myRelativeRootPath autorelease];
	myRelativeRootPath = [path copy];
	
	[self _updatePopUpToPath:myRelativeRootPath];
	
	// reset the outline view scroller to the top
	[oOutlineView scrollRectToVisible:NSMakeRect(0, 0, 1, 1)];
}

// this method is expected to be called only on paths that exist for the current browser, otherwise it will return nil
- (NSString *)_browserPathForPath:(NSString *)path
{
	if ([path isEqualToString:myRelativeRootPath])
	{
		return @"/";
	}
	else if ([path hasPrefix:myRelativeRootPath])
	{
		NSString *browserPath = @"/";
		// we start with / and add on whatever directories exist past myRelativeRootPath in path
		browserPath = [browserPath stringByAppendingPathComponent:[path substringFromIndex:[myRelativeRootPath length]]];
		return browserPath;
	}
	// this will cause problems if returned and used to setPath on NSBrowser
	return @"";
}

- (void)_setupInspectorView:(CKDirectoryNode *)node
{
	// reset everything
	[oIcon setImage:nil];
	[oName setStringValue:@"-"];
	[oSize setStringValue:@"-"];
	[oKind setStringValue:@"-"];
	[oModified setStringValue:@"-"];
	[oPermissions setStringValue:@"-"];
	
	// try to update the inspector preview if it is an image
	if (![mySelectedNode cachedContents])
	{
		if ([[mySelectedNode propertyForKey:NSFileSize] unsignedLongLongValue] <= myCachedContentsThresholdSize)
		{
			if ([myDelegate respondsToSelector:@selector(directoryTree:needsContentsOfFile:)])
			{
				[myDelegate directoryTree:self needsContentsOfFile:[mySelectedNode path]];
			}
		}
	}
	
	NSImage *img = [[[NSImage alloc] initWithData:[node cachedContents]] autorelease];
	if (!img)
	{
		img = [node iconWithSize:NSMakeSize(128,128)];
	}
	
	if (img)
	{
		[oIcon setImage:img];
	}
	
	[oName setStringValue:[node name]];
	[oSize setStringValue:[NSString formattedFileSize:[node size]]];
	[oKind setStringValue:[node kind]];
	[oModified setObjectValue:[node propertyForKey:NSFileModificationDate]];
	[oPermissions setStringValue:[[node propertyForKey:NSFilePosixPermissions] permissionsStringValue]];
}

- (BOOL)_isFiltering
{
	return (mySearchString && ![mySearchString isEqualToString:@""]);
}

- (void)_updatePopUpToPath:(NSString *)path
{
	CKDirectoryNode *selected = [CKDirectoryNode nodeForPath:path withRoot:myRootNode];
	CKDirectoryNode *walk = selected;
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"dir structure"];
	NSMenuItem *item;
	
	while (walk)
	{
		item = [[NSMenuItem alloc] initWithTitle:[self _cellDisplayNameWithNode:walk] 
										  action:nil
								   keyEquivalent:@""];
		[item setRepresentedObject:walk];
		[item setImage:[walk iconWithSize:NSMakeSize(16,16)]];
		[menu addItem:item];
		[item release];
		walk = [walk parent];
	}
	
	if (![selected isDirectory] && [menu numberOfItems] > 0)
	{
		// don't put a leaf node in the popup, only directories
		[menu removeItemAtIndex:0];
	}
	[oPopup setMenu:menu];
	[menu release];
	
	[oPopup selectItemWithRepresentedObject:selected];
}

- (void)_pruneHistoryWithPath:(NSString *)path
{
	// we need to prune the history as well so the user doesn't go back to a path that doesn't exist
	// we need to keep the myHistoryIndex correct
	NSMutableArray *invalidHistory = [NSMutableArray array];
	NSDictionary *cur;
	unsigned i;
	
	for (i = 0; i < [myHistory count]; i++)
	{
		cur = [myHistory objectAtIndex:i];
		if ([[cur objectForKey:@"fp"] hasPrefix:path])
		{
			[invalidHistory addObject:cur];
			if (i < myHistoryIndex)
			{
				myHistoryIndex--;
			}
		}
	}
	
	[myHistory removeObjectsInArray:invalidHistory];
	
	// after pruning there could be 2 selections that have been moved together so we need to delete them out
	if ([myHistory count] >= 2)
	{
		NSMutableArray *duplicates = [NSMutableArray array];
		NSDictionary *previous = [myHistory objectAtIndex:0];
		
		for (i = 1; i < [myHistory count]; i++)
		{
			cur = [myHistory objectAtIndex:i];
			
			if ([[cur objectForKey:@"fp"] isEqualToString:[previous objectForKey:@"fp"]])
			{
				[duplicates addObject:cur];
			}
			
			previous = cur;
		}
		
		NSEnumerator *e = [duplicates objectEnumerator];
		
		while ((cur = [e nextObject]))
		{
			[myHistory removeObjectIdenticalTo:cur];
		}
	}
		
	[self _updateHistoryButtons];	
}

- (void)_navigateToPath:(NSString *)path pushToHistoryStack:(BOOL)flag
{
	// stop being re-entrant from the outlineview's shouldExpandItem: delegate method
	if(myFlags.isNavigatingToPath) return;
	if (myFlags.isReloading) return;
	myFlags.isNavigatingToPath = YES;
	
	// we only want to put directory selection on the history stack
	mySelectedNode = [CKDirectoryNode nodeForPath:path withRoot:myRootNode];
	
	if ([mySelectedNode isDirectory])
	{
		[mySelectedDirectory autorelease];
		mySelectedDirectory = [path copy];
		
		// fetch the contents from the delegate
		myDirectoriesLoading++;
		[myDelegate directoryTreeStartedLoadingContents:self];
		[myDelegate directoryTree:self needsContentsForPath:path];
	}
	
	if (flag)
	{
		// handle the history
		if ([myHistory count] > 0 && myHistoryIndex < ([myHistory count] - 1))
		{
			// we have used the history buttons and are now taking a new path so we need to remove history from this point forward
			NSRange oldPathRange = NSMakeRange(myHistoryIndex + 1, [myHistory count] - 1 - myHistoryIndex);
			[myHistory removeObjectsInRange:oldPathRange];
		}
		
		// push the new navigation item on the stack if the last item is not the same as this one
		if (![[[myHistory lastObject] objectForKey:@"fp"] isEqualToString:path] || 
			![[[myHistory lastObject] objectForKey:@"rp"] isEqualToString:myRelativeRootPath])
		{
			[myHistory addObject:[NSDictionary dictionaryWithObjectsAndKeys:path, @"fp", myRelativeRootPath, @"rp", nil]];
			myHistoryIndex++;
		}
		
		[self _updateHistoryButtons];
	}
	
	if (myFlags.wasHistoryOperation)
	{
		myFlags.wasHistoryOperation = NO;
		[self _reloadViewsAutoExpandingNodes:YES];
	}
	else
	{
		[self _reloadViewsAutoExpandingNodes:NO];
	}
	
	myFlags.isNavigatingToPath = NO;
	
	if ([self target] && [self action])
	{
		[[self target] performSelector:[self action] withObject:self];
	}
}

- (NSArray *)_selectedItems
{
	return [mySelection allObjects];
}

- (void)_updateHistoryButtons
{
	[oHistory setEnabled:(myHistoryIndex > 0) forSegment:CKBackButton];
	[oHistory setEnabled:(myHistoryIndex < (int)[myHistory count] - 1) forSegment:CKForwardButton];
}

- (NSString *)_cellDisplayNameWithNode:(CKDirectoryNode *)node
{
	NSString *name = [node name];
	if (![self showsFilePackageExtensions] && [node isFilePackage])
	{
		name = [name stringByDeletingPathExtension];
	}
	return name;
}

- (void)_reloadViewsAutoExpandingNodes:(BOOL)flag
{
	// reload the data
	myFlags.isReloading = YES;
	
	if ([[self _selectedItems] count] == 0)
	{
		// we have nothing selected so make sure all views are unselected
		[oOutlineView deselectAll:self];
		[oStandardBrowser loadColumnZero];
		[oBrowser setPath:nil];
	}
	
	// tiger will scroll us back to the top in the outline view so we need to save the current rect
	NSRect outlineViewVisibleRect = [[oOutlineView enclosingScrollView] documentVisibleRect];
	
	myFlags.outlineViewFullReload = YES;
	[oOutlineView reloadData];
	myFlags.outlineViewFullReload = NO;
	
	// loop over and select everything
	NSEnumerator *e = [[self _selectedItems] objectEnumerator];
	CKDirectoryNode *cur;
	BOOL didScroll = NO, didSetBrowserPath = NO;
	
	while ((cur = [e nextObject]))
	{
		// do the outline view 
		if ([oStyles indexOfSelectedTabViewItem] != CKOutlineViewStyle || flag)
		{
			NSMutableArray *nodesToExpand = [NSMutableArray array];
			if ([self outlineView:oOutlineView isItemExpandable:cur])
			{
				[nodesToExpand addObject:cur];
			}
			CKDirectoryNode *parent = [cur parent];
			
			while ((parent))
			{
				[nodesToExpand addObject:parent];
				parent = [parent parent];
			}
			
			NSEnumerator *g = [nodesToExpand reverseObjectEnumerator];
			
			[myExpandedOutlineItems removeAllObjects];
			
			while ((parent = [g nextObject]))
			{
				myFlags.outlineViewDoubleCallback = YES;
				[myExpandedOutlineItems addObject:[parent path]];
				[oOutlineView expandItem:parent];
			}
		}
		[oOutlineView selectRow:[oOutlineView rowForItem:cur] byExtendingSelection:NO]; //TODO: need to change for multi selection support
		
		if (!didScroll)
		{
			// only scroll if we aren't the active view
			[oOutlineView scrollItemToTop:cur];
			didScroll = YES;
		}
		
		// do the NSBrowser
		if (!didSetBrowserPath)
		{
			NSString *browserPath = [self _browserPathForPath:[cur path]];
			[oStandardBrowser setPath:browserPath];
			[oStandardBrowser reloadColumn:[oStandardBrowser lastVisibleColumn]];
			
			// make sure the last column is the first responder so that it is blue
			if ([oStyles indexOfSelectedTabViewItem] == CKBrowserStyle)
			{
				[[oView window] makeFirstResponder:[oStandardBrowser matrixInColumn:[oStandardBrowser selectedColumn]]];
			}
			didSetBrowserPath = YES;
		}
		
		// TODO: This does not work with multi selection
		//int browserRow = [[[cur parent] contents] indexOfObject:cur];
		//[oStandardBrowser selectRow:browserRow inColumn:[oStandardBrowser lastColumn]];
	}
	
	// restore outline view position
	// TODO: BH this might be ruining scrolling to selection when selecting outline view because we negate [oOutlineView scrollItemToTop:cur];
	[oOutlineView scrollRectToVisible:outlineViewVisibleRect];
	
	// do the table browser
	[oBrowser selectItems:[self _selectedItems]];
	
	myFlags.isReloading = NO;
}

- (void)_reloadViews
{
	[self _reloadViewsAutoExpandingNodes:NO];
}

- (void)_resetSearch
{
	[oSearch setStringValue:@""];
	[mySearchString autorelease];
	mySearchString = nil;
}

@end

@implementation CKDirectoryTreeController

- (id)init
{
	if ((self != [super init]))
	{
		[self release];
		return nil;
	}
	
	[NSBundle loadNibNamed:@"CKDirectoryTree" owner:self];
	myRootNode = [[CKDirectoryNode nodeWithName:@"/"] retain];
	myHistory = [[NSMutableArray alloc] initWithCapacity:32];
	myHistoryIndex = -1;
	mySelection = [[NSMutableSet alloc] initWithCapacity:8];
	myExpandedOutlineItems = [[NSMutableSet alloc] init];
	
	myFlags.allowsDrags = YES;
	myFlags.allowsDrops = NO;
	myFlags.isNavigatingToPath = NO;
	myFlags.outlineViewDoubleCallback = NO;
	myFlags.filePackages = YES;
	myFlags.showsFilePackageExtensions = YES;
	myFlags.canCreateFolders = NO;
	myCachedContentsThresholdSize = 65536; // 64k threshold
	myFlags.firstTimeWithOutlineView = YES;
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(nodesRemovedInModel:)
												 name:CKDirectoryNodeDidRemoveNodesNotification
											   object:nil];
	
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[myRootNode release];
	[myRootDirectory release];
	[mySelectedDirectory release];
	[myHistory release];
	[mySelection release];
	[myExpandedOutlineItems release];
	[mySearchString release];
	
	[super dealloc];
}

- (void)awakeFromNib
{
	[oPopup removeAllItems];
	[oStyle selectSegmentWithTag:CKBrowserStyle];
	[oStyle setLabel:nil forSegment:0];
	[oStyle setLabel:nil forSegment:1];
	[self viewStyleChanged:oStyle];
	[oHistory setEnabled:NO forSegment:CKBackButton];
	[oHistory setEnabled:NO forSegment:CKForwardButton];
	
	[oHistory setLabel:nil forSegment:CKBackButton];
	[oHistory setLabel:nil forSegment:CKForwardButton];
	
	// create all the outline view columns
	myOutlineViewColumns = [[NSMutableDictionary alloc] initWithCapacity:8];
	NSTableColumn *col;
	
	[oOutlineView setAllowsColumnReordering:NO];
	[oOutlineView setAllowsColumnSelection:NO];
	
	col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	[col setEditable:NO];
	[[col headerCell] setTitle:LocalizedStringInConnectionKitBundle(@"Name", @"outline view column header name")];
	[col setDataCell:[[[CKDirectoryCell alloc] initTextCell:@""] autorelease]];
	[col setSortDescriptorPrototype:nil];
	[myOutlineViewColumns setObject:col forKey:@"name"];
	[col release];
	
	col = [[NSTableColumn alloc] initWithIdentifier:@"modified"];
	[col setEditable:NO];
	[[col headerCell] setTitle:LocalizedStringInConnectionKitBundle(@"Date Modified", @"outline view column header name")];
	CKDynamicDateFormattingCell *modifiedCell = [[[CKDynamicDateFormattingCell alloc] initTextCell:@""] autorelease];
    [modifiedCell setFont:[NSFont systemFontOfSize:11]];
	[col setDataCell:modifiedCell];
	[col setMinWidth:150];
	[col setSortDescriptorPrototype:nil];
	[myOutlineViewColumns setObject:col forKey:@"modified"];
	[col release];
	
	col = [[NSTableColumn alloc] initWithIdentifier:@"size"];
	[col setEditable:NO];
	[[col headerCell] setTitle:LocalizedStringInConnectionKitBundle(@"Size", @"outline view column header name")];
	NSTextFieldCell *sizeCell = [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
    [sizeCell setFont:[NSFont systemFontOfSize:11]];
	[sizeCell setAlignment:NSRightTextAlignment];
	[sizeCell setFormatter:[[[CKFileSizeFormatter alloc] init] autorelease]];
	[col setDataCell:sizeCell];
	[col setMinWidth:80];
	[col setSortDescriptorPrototype:nil];
	[myOutlineViewColumns setObject:col forKey:@"size"];
	[col release];
	
	col = [[NSTableColumn alloc] initWithIdentifier:@"kind"];
	[col setEditable:NO];
	[[col headerCell] setTitle:LocalizedStringInConnectionKitBundle(@"Kind", @"outline view column header name")];
	NSTextFieldCell *kindCell = [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
    [kindCell setFont:[NSFont systemFontOfSize:11]];
	[col setDataCell:kindCell];
	[col setMinWidth:150];
	[col setSortDescriptorPrototype:nil];
	[myOutlineViewColumns setObject:col forKey:@"kind"];
	[col release];
	
	// set the header view for the table
	CKTableHeaderView *header = [[CKTableHeaderView alloc] initWithFrame:[[oOutlineView headerView] frame]];
	[oOutlineView setHeaderView:header];
	[header release];
	
	[oOutlineView addTableColumn:[myOutlineViewColumns objectForKey:@"name"]];
    [oOutlineView setOutlineTableColumn:[myOutlineViewColumns objectForKey:@"name"]];
    [oOutlineView removeTableColumn:[oOutlineView tableColumnWithIdentifier:@"placeholder"]];
    [oOutlineView addTableColumn:[myOutlineViewColumns objectForKey:@"size"]];
    [oOutlineView addTableColumn:[myOutlineViewColumns objectForKey:@"modified"]];
    [oOutlineView addTableColumn:[myOutlineViewColumns objectForKey:@"kind"]];
    [oOutlineView sizeToFit];
    [oOutlineView setDoubleAction:@selector(outlineDoubleClicked:)];
	
#define MAX_VISIBLE_COLUMNS 3
	// set up NSBrowser
	[oStandardBrowser setCellClass:[CKDirectoryBrowserCell class]];
	[oStandardBrowser setDelegate:self];
    [oStandardBrowser setTarget:self];
    [oStandardBrowser setAction: @selector(standardBrowserSelectedWithDelay:)];
	[oStandardBrowser setAllowsEmptySelection:YES];

	// set up the browser
	CKDirectoryTableBrowserCell *tableCell = [[CKDirectoryTableBrowserCell alloc] initTextCell:@""];
	CKDirectoryNodeFormatter *formatter = [[CKDirectoryNodeFormatter alloc] init];
	[formatter setDelegate:self];
	[tableCell setFormatter:formatter];
	[formatter release];
	[oBrowser setCellPrototype:tableCell];
	[tableCell release];
	[oBrowser setTarget:self];
	[oBrowser setAction:@selector(browserSelected:)];
	[oBrowser setDelegate:self];
	[oBrowser setDataSource:self];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(gearActionMenuWillDisplay:)
												 name:NSPopUpButtonWillPopUpNotification
											   object:oActionGear];
	
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"gear"];
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"gear" ofType:@"tiff"];
	NSImage *icon = [[NSImage alloc] initWithContentsOfFile:path];
	[item setImage:icon];
	[icon release];
	[menu insertItem:item atIndex:0];
	[item release];
	[oActionGear setMenu:menu];
	[menu release];
		
	[oOutlineView setDataSource:self];
	[oOutlineView setDelegate:self];
}

- (void)setupBrowserDefaultColumnWidth
{
	[oBrowser setDefaultColumnWidth:(NSWidth([oBrowser bounds])/(float)MAX_VISIBLE_COLUMNS) - 1];
}

- (void)setDelegate:(id)delegate
{
	if (![delegate respondsToSelector:@selector(directoryTreeStartedLoadingContents:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"delegate does not implement directoryTreeStartedLoadingContents:" userInfo:nil];
	}
	if (![delegate respondsToSelector:@selector(directoryTreeFinishedLoadingContents:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"delegate does not implement directoryTreeFinishedLoadingContents:" userInfo:nil];
	}
	if (![delegate respondsToSelector:@selector(directoryTree:needsContentsForPath:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"delegate does not implement directoryTree:needsContentsForPath:" userInfo:nil];
	}
	
	myDelegate = delegate;
}

- (id)delegate
{
	return myDelegate;
}

- (void)setTarget:(id)target
{
	myTarget = target;
}

- (id)target
{
	return myTarget;
}

- (void)setAction:(SEL)action
{
	myAction = action;
}

- (SEL)action
{
	return myAction;
}

- (void)setContentIsRemote:(BOOL)flag
{
	myFlags.isRemote = flag;
}

- (BOOL)contentIsRemote
{
	return myFlags.isRemote;
}

- (void)setAllowsDrags:(BOOL)flag
{
	myFlags.allowsDrags = flag;
}

- (BOOL)allowsDrags
{
	return myFlags.allowsDrags;
}

- (void)setAllowsDrops:(BOOL)flag
{
	myFlags.allowsDrops = flag;
	
	if (myFlags.allowsDrops)
	{
		
	}
	else
	{
		
	}
}

- (BOOL)allowsDrops
{
	return myFlags.allowsDrops;
}

- (void)setEnabled:(BOOL)flag
{
	myFlags.isEnabled = flag;
	
	if (myFlags.isEnabled)
	{
		[oHistory setEnabled:YES];
		[oStyle setEnabled:YES];
		[oPopup setEnabled:YES];
		[oSearch setEnabled:YES];
		[oBrowser setEnabled:YES];
		[oStandardBrowser setEnabled:YES];
		[oOutlineView setEnabled:YES];
	}
	else
	{
		[oHistory setEnabled:NO];
		[oStyle setEnabled:NO];
		[oPopup setEnabled:NO];
		[oSearch setEnabled:NO];
		[oBrowser setEnabled:NO];
		[oStandardBrowser setEnabled:NO];
		[oOutlineView setEnabled:NO];
	}
}

- (BOOL)isEnabled
{
	return myFlags.isEnabled;
}

- (void)setShowHiddenFiles:(BOOL)flag
{
	myFlags.showsHiddenFiles = flag;
	
	[self _reloadViews];
}

- (BOOL)showsHiddenFiles
{
	return myFlags.showsHiddenFiles;
}

- (void)setTreatsFilePackagesAsDirectories:(BOOL)flag
{
	myFlags.filePackages = flag;
	
	[self _reloadViews];
}

- (BOOL)treatsFilePackagesAsDirectories
{
	return myFlags.filePackages;
}

- (void)setShowsFilePackageExtensions:(BOOL)flag
{
	myFlags.showsFilePackageExtensions = flag;
	
	[self _reloadViews];
}

- (BOOL)showsFilePackageExtensions
{
	return myFlags.showsFilePackageExtensions;
}

- (void)setBaseViewDirectory:(NSString *)dir
{
	if (dir == nil)
	{
		if (myDirectoriesLoading > 0)
        {
            myDirectoriesLoading = 0;
            [myDelegate directoryTreeFinishedLoadingContents:self];
        }
		// reset everything
		[myRootNode autorelease];
		myRootNode = [[CKDirectoryNode nodeWithName:@"/"] retain];
		[self _updatePopUpToPath:@"/"];
		[myHistory removeAllObjects];
		myHistoryIndex = -1;
		[self _updateHistoryButtons];
		[self _resetSearch];
		[oStandardBrowser loadColumnZero];
		[oBrowser setPath:nil];
		[oOutlineView reloadData];
		[mySelection removeAllObjects];
		[myExpandedOutlineItems removeAllObjects];
		
		[self _reloadViews];
	}
	
	if (dir != myRootDirectory)
	{
		[myRootDirectory autorelease];
		myRootDirectory = [dir copy];
		[self _changeRelativeRootToPath:dir];	
		[mySelection removeAllObjects];

		[self _reloadViews]; // not sure if we should be doing more than just this to reset the data for the browser
		
		if (dir)
		{
			// fake the history selection
			NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:dir, @"fp", dir, @"rp", nil];
			[myHistory addObject:d];
			myHistoryIndex = 0;
			
			[myDelegate directoryTreeStartedLoadingContents:self];
			myDirectoriesLoading++;
			[myDelegate directoryTree:self needsContentsForPath:dir];
		}
	}
	if (dir)
	{
        CKDirectoryNode *node = [CKDirectoryNode nodeForPath:dir withRoot:myRootNode];
		if (!node)
		{
			[CKDirectoryNode addContents:[NSArray array] withPath:dir withRoot:myRootNode];
		}
		[self _updatePopUpToPath:dir];
	}
}

- (NSString *)baseViewDirectory
{
	return myRootDirectory;
}

- (void)setCachedContentsThresholdSize:(unsigned long long)bytes
{
	myCachedContentsThresholdSize = bytes;
}

- (unsigned long long)cachedContentsThresholdSize
{
	return myCachedContentsThresholdSize;
}

- (void)setCanCreateDirectories:(BOOL)flag
{
	myFlags.canCreateFolders = flag;
}

- (BOOL)canCreateDirectories
{
	return myFlags.canCreateFolders;
}

- (void)setContents:(NSArray *)contents forPath:(NSString *)path
{
    if (myDirectoriesLoading > 0)
    {
        myDirectoriesLoading--;
    }
	if (myDirectoriesLoading == 0)
	{
		[myDelegate directoryTreeFinishedLoadingContents:self];
	}
	
	// convert contents to CKDirectoryNodes
    if (contents)
    {
        NSMutableArray *nodes = [NSMutableArray array];
        NSEnumerator *e = [contents objectEnumerator];
        NSDictionary *cur;
        CKDirectoryNode *node;
        
        while ((cur = [e nextObject]))
        {
            node = [CKDirectoryNode nodeWithName:[cur objectForKey:cxFilenameKey]];
            [node setProperties:cur];
            [nodes addObject:node];
        }

        [CKDirectoryNode addContents:nodes withPath:path withRoot:myRootNode];
        
        if (!mySelectedNode)
        {
            mySelectedNode = [CKDirectoryNode nodeForPath:myRelativeRootPath withRoot:myRootNode];
        }
    }
    else
    {
        // setting nil removes the subcontents of the path
        CKDirectoryNode *node = [CKDirectoryNode nodeForPath:path withRoot:myRootNode];
        [node setContents:[NSArray array]];
		
		[self _pruneHistoryWithPath:path];
    }
	
	[self _reloadViews];
	
	if ([oStyles indexOfSelectedTabViewItem] == CKOutlineViewStyle)
	{
		// reload the node
		[oOutlineView reloadItem:[CKDirectoryNode nodeForPath:path withRoot:myRootNode]];
	}
}

- (void)nodesRemovedInModel:(NSNotification *)n
{
	// grab the current full path BEFORE we remove any selections!
	NSString *selectedPathBeforeRemoval = [self selectedPath];
		
	NSArray *nodes = [n object];
	
	NSEnumerator *e = [nodes objectEnumerator];
	CKDirectoryNode *cur;
	
	while ((cur = [e nextObject]))
	{
		// remove it from the selection
		if ([mySelection containsObject:cur])
		{
			[mySelection removeObject:cur];
		}
		
		// go through and see if we were visible
		NSString *path = [cur path];
		NSString *parentPath = [[cur parent] path];
		
		[self _pruneHistoryWithPath:path];
		
		if ([selectedPathBeforeRemoval hasPrefix:parentPath])
		{
			unsigned col = [[[self _browserPathForPath:parentPath] pathComponents] count] - 1;
			
			if (col >= 0 && col <= [oStandardBrowser lastColumn])
			{
				[self performSelector:@selector(delayedColumnRefresh:) 
						   withObject:[NSNumber numberWithUnsignedInt:col] 
						   afterDelay:0 
							  inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];		  
				
				// make the parent the current selection
				[mySelection addObject:[CKDirectoryNode nodeForPath:parentPath withRoot:myRootNode]];
				[self _updatePopUpToPath:parentPath];
			}
		}
	}
}

- (void)delayedColumnRefresh:(NSNumber *)col
{
	@try {
		[oBrowser refreshColumn:[col unsignedIntValue]];
		if ([col intValue] == 0)
		{
			[oStandardBrowser loadColumnZero];
		}
		else
		{
			[oStandardBrowser reloadColumn:[col unsignedIntValue]];
		}
	}
	@catch (NSException *ex) {
		
	}
}

- (void)setContents:(NSData *)contents forFile:(NSString *)file
{
	CKDirectoryNode *node = [CKDirectoryNode nodeForPath:file withRoot:myRootNode];
	[node setCachedContents:contents];
	
	if (node == mySelectedNode)
	{
		[self _setupInspectorView:mySelectedNode];
	}
}

- (NSView *)view
{
	return oView;
}

- (NSArray *)selectedPaths
{
	NSMutableArray *paths = [NSMutableArray array];
	NSArray *items = [self _selectedItems];
	NSEnumerator *e = [items objectEnumerator];
	CKDirectoryNode *cur;
	
	while ((cur = [e nextObject]))
	{
		[paths addObject:[cur path]];
	}
	
	return paths;
}

- (NSString *)selectedPath
{	
	NSArray *paths = [self selectedPaths];
	
	if ([paths count] > 0)
	{
		return [paths objectAtIndex:0];
	}
	
	return [oBrowser pathSeparator]; //TODO: check table browser still works with this return type
}

- (NSString *)selectedFolderPath
{
	NSArray *items = [self _selectedItems];
	
	if ([items count])
	{
		CKDirectoryNode *cur = [items objectAtIndex:0];
		
		if (![cur isDirectory])
		{
			cur = [cur parent];
		}
		
		return [cur path];
	}
	// if nothing is selected, then the folder of the relative root should be returned
	return myRelativeRootPath;
}

- (NSArray *)contentsOfSelectedFolder
{
	NSMutableArray *contents = [NSMutableArray array];

	CKDirectoryNode *cur = [CKDirectoryNode nodeForPath:[self selectedFolderPath] withRoot:myRootNode];
	NSEnumerator *e = [[cur contents] objectEnumerator];
	CKDirectoryNode *node;
	
	while ((node = [e nextObject]))
	{
		NSDictionary *d = [NSDictionary dictionaryWithDictionary:[node properties]];
		[contents addObject:d];
	}
	
	return contents;
}

#pragma mark -
#pragma mark UI Actions

- (IBAction)viewStyleChanged:(id)sender
{
    if ([oStyles indexOfSelectedTabViewItem] != [oStyle selectedSegment])
    {
		if ([self _isFiltering])
		{
			[self _resetSearch];
			[self _reloadViewsAutoExpandingNodes:YES];
		}
        
		//setup the outline view columns to start off nicely sized
		if ([oStyle selectedSegment] == CKOutlineViewStyle)
		{
			if (myFlags.firstTimeWithOutlineView)
			{
				myFlags.firstTimeWithOutlineView = NO;
				float width = NSWidth([oOutlineView bounds]);
				NSArray *cols = [oOutlineView tableColumns];
				[[cols objectAtIndex:0] setWidth:width * 0.403426791277259];
				[[cols objectAtIndex:1] setWidth:width * 0.124610591900312];
				[[cols objectAtIndex:2] setWidth:width * 0.233644859813084];
				[[cols objectAtIndex:3] setWidth:width * 0.228317757009346];
			}
			if ([oOutlineView selectedRow] != NSNotFound)
			{
				[oOutlineView scrollItemToTop:[oOutlineView itemAtRow:[oOutlineView selectedRow]]];
			}
		}
		[oStyles selectTabViewItemAtIndex:[oStyle selectedSegment]];
    }
	
	// make the correct view the first responder on a view style switch
	switch ([oStyles indexOfSelectedTabViewItem])
	{
		case CKBrowserStyle: [[oView window] makeFirstResponder:[oStandardBrowser matrixInColumn:[oStandardBrowser selectedColumn]]]; break;
		case CKOutlineViewStyle: [[oView window] makeFirstResponder:oOutlineView]; break;
	}
	
}

- (IBAction)popupChanged:(id)sender
{
	if ([self _isFiltering])
	{
		[self _resetSearch];
	}
	
	// outline view needs a forced deselection
	[oOutlineView deselectAll:self];
	
	CKDirectoryNode *node = [sender representedObjectOfSelectedItem];
	NSString *path = [node path];
	
	// empty the selection
	[mySelection removeAllObjects];
	[mySelection addObject:node];
	
	if (![path hasPrefix:myRelativeRootPath])
	{
		[self _changeRelativeRootToPath:path];
	}

	[self _updatePopUpToPath:path];
	
	// this pushes a history object and fetches the contents
	[self _navigateToPath:path pushToHistoryStack:YES];
	
	// scroll the selected item into view for the outline view
	if ([oOutlineView selectedRow] != NSNotFound)
	{
		[oOutlineView scrollRowToVisible:[oOutlineView selectedRow]];
	}
}

- (IBAction)outlineViewSelected:(id)sender
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(outlineViewSelectedRunloopDelay:) object:nil];
	
	// this seems to be a known issue with table/outline views http://www.cocoabuilder.com/archive/message/cocoa/2004/5/11/106845
	// stop a double click of the outline view doing anything
	NSTableHeaderView *header = [oOutlineView headerView];
	NSEvent *event = [NSApp currentEvent];
	NSPoint location = [event locationInWindow];
	location = [[header superview] convertPoint:location fromView:nil];
	
	if ([header hitTest:location]) return;
	
	NSString *fullPath = nil;
	// update our internal selection tracking
	/* TODO: we may need to limit multi selection to just the one directory as they 
	 can expand folders and have non-concurrent selections, which might mess up the browsers.
	 The finder trims the selection on a view change */
	NSMutableArray *selection = [NSMutableArray array];
	
	NSEnumerator *e = [oOutlineView selectedRowEnumerator];
	NSNumber *cur;
	
	while ((cur = [e nextObject]))
	{
		CKDirectoryNode *node = [oOutlineView itemAtRow:[cur intValue]];
		[selection addObject:node];
		fullPath = [node path];
	}
	
	BOOL needsDelayedReload = YES;
	
	if ([selection count] > 0)
	{
		// if we are searching, we only want to load the folder contents and not push anything on the history stack
		if ([self _isFiltering])
		{
			if ([[oOutlineView itemAtRow:[oOutlineView selectedRow]] isDirectory])
			{
				myDirectoriesLoading++;
				[myDelegate directoryTreeStartedLoadingContents:self];
				[myDelegate directoryTree:self needsContentsForPath:fullPath];
				needsDelayedReload = NO;
			}
		}
		else
		{
			[mySelection removeAllObjects];
			[mySelection addObjectsFromArray:selection];
		}
	}
	else
	{
		BOOL wasDeselection = [oOutlineView rowAtPoint:[[oOutlineView superview] convertPoint:[event locationInWindow] fromView:nil]] != NSNotFound;
		
		if (wasDeselection)
		{
			// we deselected so push the relative root path on the history stack via the nil path check in outlineViewSelectedRunloopDelay:
			[mySelection removeAllObjects];
		}
	}
	
	if (needsDelayedReload)
	{
		[self performSelector:@selector(outlineViewSelectedRunloopDelay:) withObject:nil afterDelay:FILE_NAVIGATION_DELAY inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
	}
}

- (IBAction)outlineViewSelectedRunloopDelay:(id)sender
{	
	NSString *fullPath  = [[[mySelection allObjects] lastObject] path];
	
	if (!fullPath)
	{
		fullPath = [[myRelativeRootPath copy] autorelease];
	}
	[self _navigateToPath:fullPath pushToHistoryStack:YES];
	[self _updatePopUpToPath:fullPath];
}

- (IBAction)standardBrowserSelectedWithDelay:(id)sender
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(standardBrowserSelected:) object:nil];
	
	// update our internal selection tracking
	[mySelection removeAllObjects];
	NSEnumerator *e = [[oStandardBrowser selectedCells] objectEnumerator];
	CKDirectoryBrowserCell *cur;
	
	while ((cur = [e nextObject]))
	{
		[mySelection addObject:[cur representedObject]];
	}
	
	[self performSelector:@selector(standardBrowserSelected:) withObject:nil afterDelay:FILE_NAVIGATION_DELAY inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
}

- (IBAction)standardBrowserSelected:(id)sender
{	
	NSString *fullPath  = [[[mySelection allObjects] lastObject] path];
	if (fullPath)
	{
		[self _navigateToPath:fullPath pushToHistoryStack:YES];
		[self _updatePopUpToPath:fullPath];
	}
}

- (IBAction)browserSelected:(id)sender
{	
	// update our internal selection tracking
	[mySelection removeAllObjects];
	[mySelection addObjectsFromArray:[oBrowser selectedItems]];
	
	NSString *fullPath = [[[oBrowser selectedItems] lastObject] path];
	[self _navigateToPath:fullPath pushToHistoryStack:YES];
	[self _updatePopUpToPath:fullPath];
}

- (CKDirectoryNode *)nodeToFilter
{
	return [[oPopup selectedItem] representedObject];
}

- (IBAction)filterChanged:(id)sender
{
    //only show filtered results in the outline view
    [oStyles selectTabViewItemAtIndex:CKOutlineViewStyle];
    [oStyle selectSegmentWithTag:CKOutlineViewStyle];
	[mySearchString autorelease];
	mySearchString = [[oSearch stringValue] copy];
	
	[self _reloadViewsAutoExpandingNodes:[[sender stringValue] isEqualToString:@""]];
}

- (IBAction)historyChanged:(id)sender
{
	// clear any search string
	if ([self _isFiltering])
	{
		[self _resetSearch];
		[oStyle selectSegmentWithTag:CKBrowserStyle];
		[self viewStyleChanged:oStyle];
	}
	
	
	if ([oHistory selectedSegment] == CKForwardButton)
	{
		myHistoryIndex++;
	}
	else
	{
		myHistoryIndex--;
	}
	
	NSDictionary *rec = [myHistory objectAtIndex:myHistoryIndex];
	NSString *relPath = [rec objectForKey:@"rp"];
	NSString *fullPath = [rec objectForKey:@"fp"];
	
	// fake the selection
	[mySelection removeAllObjects];
	[mySelection addObject:[CKDirectoryNode nodeForPath:fullPath withRoot:myRootNode]];
	
	// outline view needs a forced deselection
	[oOutlineView deselectAll:self];
	
	// we need to make sure the path we are going to is fully expandable for the outline view, just incase they closed the node
	CKDirectoryNode *parent = [[CKDirectoryNode nodeForPath:fullPath withRoot:myRootNode] parent];
	while (parent)
	{
		[myExpandedOutlineItems addObject:[parent path]];
		parent = [parent parent];
	}
	
	[self _changeRelativeRootToPath:relPath];
	myFlags.wasHistoryOperation = YES;
	[self _navigateToPath:fullPath pushToHistoryStack:NO];
	[self _updatePopUpToPath:fullPath];
	[self _updateHistoryButtons];
	
	// scroll the selected item into view for the outline view
	if ([oOutlineView selectedRow] != NSNotFound)
	{
		[oOutlineView scrollRowToVisible:[oOutlineView selectedRow]];
	}
}

- (IBAction)outlineDoubleClicked:(id)sender
{
	// we have to cancel this as the single click action is called before the double click
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(outlineViewSelectedRunloopDelay:) object:nil];
	
	// this seems to be a known issue with table/outline views http://www.cocoabuilder.com/archive/message/cocoa/2004/5/11/106845
	// stop a double click of the outline view doing anything
	NSTableHeaderView *header = [oOutlineView headerView];
	NSEvent *event = [NSApp currentEvent];
	NSPoint location = [event locationInWindow];
	location = [[header superview] convertPoint:location fromView:nil];
	
	if ([header hitTest:location]) return;
	
	// a double click will change the relative root path of where we are browsing
	CKDirectoryNode *node = [oOutlineView itemAtRow:[oOutlineView selectedRow]];
	
	if (node)
	{
		NSString *path = [node path];
		
		if ([node isFilePackage] && ![self treatsFilePackagesAsDirectories]) return;
		
		// clear any search string
		if ([self _isFiltering])
		{
			[self _resetSearch];
			[mySelection removeAllObjects];
			[mySelection addObject:node];
			[self _navigateToPath:path pushToHistoryStack:YES];
			// change back to the browser from the "search results"
			[oStyle selectSegmentWithTag:CKBrowserStyle];
			[self viewStyleChanged:oStyle];
		}
		else
		{
			[mySelection removeAllObjects];
			if ([node isDirectory])
			{
				[self _changeRelativeRootToPath:path];
			}
			[self _navigateToPath:path pushToHistoryStack:YES];
		}
	}
}

#pragma mark -
#pragma mark NSOutlineView Data Source

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	int result = 0;
	
	if ([self _isFiltering])
	{
		if (item == nil)
		{
			return [[[self nodeToFilter] filteredContentsWithNamesLike:mySearchString includeHiddenFiles:myFlags.showsHiddenFiles] count];
		}
		else
		{
			return 0;
		}
	}
	
	if (item == nil)
	{
		item = [CKDirectoryNode nodeForPath:myRelativeRootPath withRoot:myRootNode];
	}

	result = [item countIncludingHiddenFiles:myFlags.showsHiddenFiles];
	
	return result;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(int)index ofItem:(id)item
{
	id child = nil;
	
	if ([self _isFiltering])
	{
		if (item == nil)
		{
			return [[[self nodeToFilter] filteredContentsWithNamesLike:mySearchString includeHiddenFiles:myFlags.showsHiddenFiles] objectAtIndex:index];
		}
	}
	
	if (item == nil)
	{
		item = [CKDirectoryNode nodeForPath:myRelativeRootPath withRoot:myRootNode];
	}
	
	child = [[item contentsIncludingHiddenFiles:myFlags.showsHiddenFiles] objectAtIndex:index];
	
	return child;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	BOOL result = NO;
	
	if ([self _isFiltering]) return NO;
	
	if (item == nil)
	{
		item = [CKDirectoryNode nodeForPath:myRelativeRootPath withRoot:myRootNode];
	}
	
	if ([item isFilePackage])
	{
		if ([self treatsFilePackagesAsDirectories])
		{
			result = YES;
		}
	}
	else
	{
		if ([item isDirectory])
		{
			result = YES;
		}
	}
	
	return result;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	NSString *ident = [tableColumn identifier];
	    
	if ([ident isEqualToString:@"name"])
	{
		NSString *name = [item name];
		if (![self showsFilePackageExtensions] && [item isFilePackage])
		{
			name = [name stringByDeletingPathExtension];
		}
		return [NSDictionary dictionaryWithObjectsAndKeys:name, @"name", [item iconWithSize:NSMakeSize(16,16)], @"icon", nil];
	}
	else if ([ident isEqualToString:@"modified"])
	{
		return [item propertyForKey:NSFileModificationDate];
	}
	else if ([ident isEqualToString:@"size"])
	{
		if ([item isDirectory])
		{
			return @"--";
		}
		else
		{
			return [NSNumber numberWithUnsignedLongLong:[(CKDirectoryNode *)item size]];
		}
	}
	else if ([ident isEqualToString:@"kind"])
	{
		return [(CKDirectoryNode *)item kind];
	}
	return nil;
}

- (void)outlineView:(NSOutlineView *)outlineView toggleColumn:(NSString *)identifier
{
	NSTableColumn *col = [oOutlineView tableColumnWithIdentifier:identifier];
	
	if (col)
	{
		if ([oOutlineView outlineTableColumn] == col)
		{
			if ([[oOutlineView tableColumns] count] > 1)
			{
				[oOutlineView setOutlineTableColumn:[[oOutlineView tableColumns] objectAtIndex:1]];
				[oOutlineView removeTableColumn:col];
			}
		}
		else
		{
			[oOutlineView removeTableColumn:col];
		}
	}
	else
	{
		col = [myOutlineViewColumns objectForKey:identifier];
		[oOutlineView addTableColumn:col];
	}
}

- (BOOL)outlineViewIsShowingHiddenFiles:(NSOutlineView *)outlineView
{
	return [self showsHiddenFiles];
}

- (void)outlineView:(NSOutlineView *)outlineView toggleHiddenFiles:(BOOL)flag
{
	[self setShowHiddenFiles:flag];
}

- (BOOL)outlineViewCanBrowseFilePackages:(NSOutlineView *)outlineView
{
	return [self treatsFilePackagesAsDirectories];
}

- (void)outlineView:(NSOutlineView *)outlineView toggleFilePackages:(BOOL)flag
{
	[self setTreatsFilePackagesAsDirectories:flag];
}

- (BOOL)outlineViewShowsFilePackageExtensions:(NSOutlineView *)outlineView
{
	return [self showsFilePackageExtensions];
}

- (void)outlineView:(NSOutlineView *)outlineView toggleFilePackageExtensions:(BOOL)flag
{
	[self setShowsFilePackageExtensions:flag];
}

#pragma mark -
#pragma mark NSOutlineView Delegate Methods

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldExpandItem:(id)item
{
	BOOL result = NO;
	
	if (myFlags.outlineViewDoubleCallback || myFlags.outlineViewFullReload) 
	{
		myFlags.outlineViewDoubleCallback = NO;
		result = [myExpandedOutlineItems containsObject:[item path]];
	}
	else if ([item isDirectory])
	{		
		if (![myExpandedOutlineItems containsObject:[item path]])
		{
			[myExpandedOutlineItems addObject:[item path]];
			// need to fetch from the delegate
			myDirectoriesLoading++;
			[myDelegate directoryTreeStartedLoadingContents:self];
			[myDelegate directoryTree:self needsContentsForPath:[item path]];
		}
		result = YES;
	}
	return result;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item
{
	if ([item parent])
	{
		[mySelection addObject:[item parent]];
	}
	[mySelection removeObject:item];
	
	[myExpandedOutlineItems removeObject:[item path]];

	// collapsing doesn't trigger the target/action
	[self performSelector:@selector(outlineViewSelected:)
			   withObject:oOutlineView
			   afterDelay:0
				  inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
	
	return YES;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectTableColumn:(NSTableColumn *)tableColumn
{
	return NO;
}

#pragma mark -
#pragma mark NSBrowser Delegate DataSource

- (int)browser:(NSBrowser *)sender numberOfRowsInColumn:(int)column 
{
	CKDirectoryNode *node = nil;
	if (column == 0)
	{
		node = [CKDirectoryNode nodeForPath:myRelativeRootPath withRoot:myRootNode];
	}
	else
	{
		node = [[oStandardBrowser selectedCellInColumn:column - 1] representedObject];
	}
	
	return [node countIncludingHiddenFiles:myFlags.showsHiddenFiles];
}

- (void)browser:(NSBrowser *)sender willDisplayCell:(id)cell atRow:(int)row column:(int)column 
{
	CKDirectoryNode *parent = nil;
	
	if (column == 0)
	{
		parent = [CKDirectoryNode nodeForPath:myRelativeRootPath withRoot:myRootNode];
	}
	else
	{
		parent = [[oStandardBrowser selectedCellInColumn:column - 1] representedObject];
	}
	
	// TODO: this is a HACK to get around a bug when you are in outline view and select a folder, then double click it to change the relative root
	// repeating this a few folders deep then use the history buttons to go back. The setPath: on the NSBrowser will cause the cells to redraw, but 
	// the rows are out of bounds and we haven't had time to track down why. NSBrowser is a PoS.
	if ([[parent contentsIncludingHiddenFiles:myFlags.showsHiddenFiles] count] > row)
	{
		CKDirectoryNode *node = [[parent contentsIncludingHiddenFiles:myFlags.showsHiddenFiles] objectAtIndex:row];
		[cell setLeaf:![self outlineView:nil isItemExpandable:node]];
		[cell setRepresentedObject:[node retain]];
		[cell setTitle:[self _cellDisplayNameWithNode:node]];
	}
}

- (BOOL)browser:(NSBrowser *)sender shouldShowCellExpansionForRow:(int)rowIndex column:(int)columnIndex
{
	return NO;
}

#pragma mark -
#pragma mark CKTableBasedBrowser DataSource Methods

- (unsigned)tableBrowser:(CKTableBasedBrowser *)browser numberOfChildrenOfItem:(id)item
{
	return [self outlineView:nil numberOfChildrenOfItem:item];
}

- (id)tableBrowser:(CKTableBasedBrowser *)browser child:(unsigned)index ofItem:(id)item
{
    return [self outlineView:nil child:index ofItem:item];
}

- (BOOL)tableBrowser:(CKTableBasedBrowser *)browser isItemExpandable:(id)item
{
	return [self outlineView:nil isItemExpandable:item];
}

- (id)tableBrowser:(CKTableBasedBrowser *)browser objectValueByItem:(id)item
{
	return item;
}

- (void)tableBrowser:(CKTableBasedBrowser *)browser setObjectValue:(id)object byItem:(id)item
{
	//[(CKDirectoryNode *)item setName:object];
}

- (NSString *)tableBrowser:(CKTableBasedBrowser *)browser pathForItem:(id)item
{
	NSString *fullPath = [item path];
	
	if ([fullPath length] < [myRelativeRootPath length])
	{
		// we have an orphaned object hanging around
		return nil;
	}
	
	NSString *path = [fullPath substringFromIndex:[myRelativeRootPath length]];
	if (![path hasPrefix:@"/"])
	{
		path = [NSString stringWithFormat:@"/%@", path];
	}
	return path;
}

- (id)tableBrowser:(CKTableBasedBrowser *)browser itemForPath:(NSString *)path
{
	CKDirectoryNode *node = [CKDirectoryNode nodeForPath:[myRelativeRootPath stringByAppendingPathComponent:path] withRoot:myRootNode];
	return node;
}

- (NSView *)tableBrowser:(CKTableBasedBrowser *)browser leafViewWithItem:(id)item
{
	mySelectedNode = item;
	[self _setupInspectorView:item];
	return oInspectorView;
}

- (NSMenu *)tableBrowser:(CKTableBasedBrowser *)browser contextMenuWithItem:(id)selectedItem
{
/*	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"dir options"];
	NSMenuItem *item;
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Show Hidden Files", @"context menu")
									  action:@selector(toggleHiddenFiles:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[self showsHiddenFiles] ? NSOnState : NSOffState];
	[menu addItem:item];
	[item release];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Browse Packages", @"context menu")
									  action:@selector(togglePackageBrowsing:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[self treatsFilePackagesAsDirectories] ? NSOnState : NSOffState];
	[menu addItem:item];
	[item release];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Show Package Extensions", @"context menu")
									  action:@selector(togglePackageExtensions:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[self showsFilePackageExtensions] ? NSOnState : NSOffState];
	[menu addItem:item];
	[item release];
		
	return [menu autorelease];*/
    return nil;
}

#pragma mark -
#pragma mark Table Browser Delegate Methods

- (void)tableBrowser:(CKTableBasedBrowser *)browser willDisplayCell:(id)cell
{
	CKDirectoryNode *node = [cell objectValue];
	
	[cell setLeaf:![self tableBrowser:browser isItemExpandable:node]];
	[cell setTitle:[self _cellDisplayNameWithNode:node]];
}

- (NSString *)directoryNodeFormatter:(CKDirectoryNodeFormatter *)formatter stringRepresentationWithNode:(CKDirectoryNode *)node
{
	return [self _cellDisplayNameWithNode:node];
}

#pragma mark -
#pragma mark Context Menu Support

- (void)toggleHiddenFiles:(id)sender
{
	[self setShowHiddenFiles:[sender state] == NSOffState];
}

- (void)togglePackageBrowsing:(id)sender
{
	[self setTreatsFilePackagesAsDirectories:[sender state] == NSOffState];
}

- (void)togglePackageExtensions:(id)sender
{
	[self setShowsFilePackageExtensions:[sender state] == NSOffState];
}

- (void)newFolder:(id)sender
{
	// deselect if we currently have a file selected
	CKDirectoryNode *selection = [[self _selectedItems] lastObject];
	if (selection && ![selection isDirectory])
	{
		[mySelection removeAllObjects];
		[mySelection addObject:[selection parent]];
		[self _reloadViews];
	}
	[myDelegate performSelector:@selector(directoryTreeWantsNewFolderCreated:)
					 withObject:self
					 afterDelay:0.0
						inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
}

- (void)refresh:(id)sender
{
	NSString *folder = [self selectedFolderPath];
	
	myDirectoriesLoading++;
	[myDelegate directoryTreeStartedLoadingContents:self];
	[myDelegate directoryTree:self needsContentsForPath:folder];
}

#pragma mark -
#pragma mark Tri State Menu Delegate

- (void)gearActionMenuWillDisplay:(NSNotification *)notification
{
	NSMenu *menu = [self triStateMenuButtonNeedsMenu:nil];
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"gear" ofType:@"tiff"];
	NSImage *icon = [[NSImage alloc] initWithContentsOfFile:path];
	[item setImage:icon];
	[icon release];
	[menu insertItem:item atIndex:0];
	[item release];
	[oActionGear setMenu:menu];
}

- (NSMenu *)triStateMenuButtonNeedsMenu:(CKTriStateMenuButton *)button
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"action gear"];
	NSMenuItem *item;
	
	if ([self canCreateDirectories] && [myDelegate respondsToSelector:@selector(directoryTreeWantsNewFolderCreated:)])
	{
		item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"New Folder", @"tree controller action gear")
										  action:@selector(newFolder:)
								   keyEquivalent:@""];
		[item setTarget:self];
		[menu addItem:item];
		[item release];
		
		[menu addItem:[NSMenuItem separatorItem]];
	}
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Refresh", @"tree controller action gear")
									  action:@selector(refresh:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[menu addItem:item];
	[item release];
	
    /*
	[menu addItem:[NSMenuItem separatorItem]];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Show Hidden Files", @"tree controller action gear")
									  action:@selector(toggleHiddenFiles:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[self showsHiddenFiles] ? NSOnState : NSOffState];
	[menu addItem:item];
	[item release];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Browse Packages", @"tree controller action gear")
									  action:@selector(togglePackageBrowsing:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[self treatsFilePackagesAsDirectories] ? NSOnState : NSOffState];
	[menu addItem:item];
	[item release];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Show Package Extensions", @"tree controller action gear")
									  action:@selector(togglePackageExtensions:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[self showsFilePackageExtensions] ? NSOnState : NSOffState];
	[menu addItem:item];
	[item release];
	*/
	if ([myDelegate respondsToSelector:@selector(directoryTreeController:willDisplayActionGearMenu:)])
	{
		[myDelegate directoryTreeController:self willDisplayActionGearMenu:menu];
	}
	
	return [menu autorelease];
}

@end

@implementation CKDirectoryNodeFormatter : NSFormatter

- (void)setDelegate:(id)delegate
{
	if (![delegate respondsToSelector:@selector(directoryNodeFormatter:stringRepresentationWithNode:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException
									   reason:[NSString stringWithFormat:@"-[%@ %@] delegate must implement directoryNodeFormatter:stringRepresentationWithNode:", [self className], NSStringFromSelector(_cmd)]
									 userInfo:nil];
	}
	
	myDelegate = delegate;
}

- (NSString *)stringForObjectValue:(id)anObject
{
	if ([anObject isKindOfClass:[CKDirectoryNode class]])
	{
		return [myDelegate directoryNodeFormatter:self stringRepresentationWithNode:anObject];
	}
	return @"";
}

@end

// NSTable sets a cells objectValue, the tree controller calls setTitle which then clears the objectValue (the node) to be a string.
// we have to have an ivar of the title and override those methods
@implementation CKDirectoryTableBrowserCell

- (void)dealloc
{
	[myTitle release];
	[super dealloc];
}

- (void)setTitle:(NSString *)title
{
	if (title != myTitle)
	{
		[myTitle release];
		myTitle = [title copy];
	}
}

- (NSString *)title
{
	return myTitle;
}

- (NSString *)stringValue
{
	return myTitle;
}

- (NSSize)cellSizeForBounds:(NSRect)aRect 
{
    NSSize s = [super cellSizeForBounds:aRect];
    s.height += 1.0 * 2.0;
	s.width += NSWidth(aRect);
    return s;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	NSImage *iconImage = [[self objectValue] iconWithSize:NSMakeSize(ICON_SIZE, ICON_SIZE)];
	if (iconImage != nil) {
        NSSize imageSize = [iconImage size];
        NSRect imageFrame, highlightRect, textFrame;
		
		// Divide the cell into 2 parts, the image part (on the left) and the text part.
		NSDivideRect(cellFrame, &imageFrame, &textFrame, ICON_INSET_HORIZ + ICON_TEXT_SPACING + imageSize.width, NSMinXEdge);
        imageFrame.origin.x += ICON_INSET_HORIZ;
        imageFrame.size = imageSize;
		
		// Adjust the image frame top account for the fact that we may or may not be in a flipped control view, since when compositing the online documentation states: "The image will have the orientation of the base coordinate system, regardless of the destination coordinates".
        if ([controlView isFlipped]) {
            imageFrame.origin.y += ceil((textFrame.size.height + imageFrame.size.height) / 2);
        } else {
            imageFrame.origin.y += ceil((textFrame.size.height - imageFrame.size.height) / 2);
        }
		
        // We don't draw the background when creating the drag and drop image
		BOOL drawsBackground = YES;
        if (drawsBackground) {
            // If we are highlighted, or we are selected (ie: the state isn't 0), then draw the highlight color
            if ([self isHighlighted] || [self state] != 0) {
                // The return value from highlightColorInView will return the appropriate one for you. 
                [[self highlightColorInView:controlView] set];
            } else {
				[[NSColor controlBackgroundColor] set];
			}
			// Draw the icon area (the portion that won't be caught by the call to [super drawInteriorWithFrame:...] below.)
			highlightRect = NSMakeRect(NSMinX(cellFrame), NSMinY(cellFrame), NSWidth(cellFrame) - NSWidth(textFrame), NSHeight(cellFrame));
			NSRectFill(highlightRect);
        }
		
        [iconImage compositeToPoint:imageFrame.origin operation:NSCompositeSourceOver fraction:1.0];
		
		// Have NSBrowserCell kindly draw the text part, since it knows how to do that for us, no need to re-invent what it knows how to do.
		[super drawInteriorWithFrame:textFrame inView:controlView];
    } else {
		// At least draw something if we couldn't find an icon. You may want to do something more intelligent.
    	[super drawInteriorWithFrame:cellFrame inView:controlView];
    }
}

@end

static NSMutableParagraphStyle *sStyle = nil;

@implementation CKDirectoryCell

+ (void)initialize
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	if (!sStyle)
	{
		sStyle = [[NSMutableParagraphStyle alloc] init];
		[sStyle setLineBreakMode:NSLineBreakByTruncatingTail];
	}
	
	[pool release];
}

- (id)initTextCell:(NSString *)txt
{
	if ((self = [super initTextCell:txt]))
	{
		[self setFont:[NSFont systemFontOfSize:11]];
	}
	return self;
}

- (void)dealloc
{
	[myIcon release];
	[super dealloc];
}

- (void)setObjectValue:(id)obj
{
	if ([obj isKindOfClass:[NSDictionary class]])
	{
		[super setObjectValue:[obj objectForKey:@"name"]];
		myIcon = [[obj objectForKey:@"icon"] retain];
	}
	else
	{
		[super setObjectValue:obj];
	}
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{	
	NSRect imageRect = NSMakeRect(NSMinX(cellFrame), NSMinY(cellFrame), NSHeight(cellFrame), NSHeight(cellFrame));
	imageRect = NSOffsetRect(imageRect, PADDING, 0);
	
	// from omni
	NSMutableAttributedString *label = [[NSMutableAttributedString alloc] initWithAttributedString:[self attributedStringValue]];
	NSRange labelRange = NSMakeRange(0, [label length]);
	if ([NSColor respondsToSelector:@selector(alternateSelectedControlColor)]) 
	{
		NSColor *highlightColor = [self highlightColorWithFrame:cellFrame inView:controlView];
		BOOL highlighted = [self isHighlighted];
		
		if (highlighted && [highlightColor isEqual:[NSColor alternateSelectedControlColor]]) 
		{
            // add the alternate text color attribute.
			[label addAttribute:NSForegroundColorAttributeName value:[NSColor alternateSelectedControlTextColor] range:labelRange];
		}
	}
	
	[label addAttribute:NSParagraphStyleAttributeName value:sStyle range:labelRange];
	NSSize labelSize = [label size];
	NSRect labelRect = NSMakeRect(NSMaxX(imageRect) + PADDING,  
								  NSMidY(cellFrame) - (labelSize.height / 2),
								  NSWidth(cellFrame) - NSWidth(imageRect) - PADDING,
								  labelSize.height);
	[label drawInRect:labelRect];
	[label release];
	
	NSAffineTransform *flip = [NSAffineTransform transform]; // initializing here since used in two places below
	
	if ([controlView isFlipped]) 
	{
		[[NSGraphicsContext currentContext] saveGraphicsState];
		[flip translateXBy:0 yBy:NSMaxY(imageRect)];
		[flip scaleXBy:1 yBy:-1];
		[flip concat];
		imageRect.origin.y = 0;
	}
	
	[myIcon drawInRect:imageRect
			  fromRect:NSZeroRect
			 operation:NSCompositeSourceOver
			  fraction:1.0];
	
	if ([controlView isFlipped]) 
	{
		[flip invert];
		[flip concat];
		[[NSGraphicsContext currentContext] restoreGraphicsState];
	}
}

@end

@implementation CKFileSizeFormatter

- (NSString *)stringForObjectValue:(id)anObject
{
    if (![anObject isKindOfClass:[NSNumber class]]) 
	{
        return [anObject description];
    }
	
    return [NSString formattedFileSize:[anObject doubleValue]];
}

- (BOOL)getObjectValue:(id *)anObject forString:(NSString *)string errorDescription:(NSString **)error
{
	return NO;
}

@end

@implementation CKDynamicDateFormattingCell

- (id)initTextCell:(NSString *)txt
{
	if ((self != [super initTextCell:txt]))
	{
		[self release];
		return nil;
	}
	
	/*
	 These are from NSUserDefaults:
		NSTimeDateFormatString = "%A, %e %B %Y %1I:%M:%S %p %Z";
		NSDateFormatString = "%A, %e %B %Y";
		NSShortTimeDateFormatString = "%e/%m/%y %1I:%M %p";
		NSShortDateFormatString = "%e/%m/%y";
	 
	 This is how the finder behaves with resizing:
		"%A, %e %B %Y, %1I:%M %p"
		"%e %B %Y, %1I:%M %p"
		"%e/%m/%y %1I:%M %p";
		"%e/%m/%y";
	 */
	
	//This is deprecated, and also unused. Not sure what we should be doing here. -Brian.
	
//	NSString *dateFormat = [[NSUserDefaults standardUserDefaults] objectForKey:NSShortTimeDateFormatString];
//	NSDateFormatter *formatter = [[[NSDateFormatter alloc] initWithDateFormat:dateFormat allowNaturalLanguage:YES] autorelease];
//	[self setFormatter:formatter];
	
	return self;
}

- (void)setFormat:(NSString *)format
{
	[[self formatter] setDateFormat:format];
}

@end

@interface NSObject (CKOutlineViewDataSourceExtensions)
- (void)outlineView:(NSOutlineView *)outlineView toggleColumn:(NSString *)identifier;
@end

@implementation CKTableHeaderView

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"columns"];
	NSMenuItem *item;
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Name", @"outline view column context menu item")
									  action:nil
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[[self tableView] tableColumnWithIdentifier:@"name"] != nil ? NSOnState : NSOffState];
	[item setRepresentedObject:@"name"];
	[menu addItem:item];
	[item release];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Date Modified", @"outline view column context menu item")
									  action:@selector(toggleColumn:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[[self tableView] tableColumnWithIdentifier:@"modified"] != nil ? NSOnState : NSOffState];
	[item setRepresentedObject:@"modified"];
	[menu addItem:item];
	[item release];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Size", @"outline view column context menu item")
									  action:@selector(toggleColumn:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[[self tableView] tableColumnWithIdentifier:@"size"] != nil ? NSOnState : NSOffState];
	[item setRepresentedObject:@"size"];
	[menu addItem:item];
	[item release];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Kind", @"outline view column context menu item")
									  action:@selector(toggleColumn:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[[self tableView] tableColumnWithIdentifier:@"kind"] != nil ? NSOnState : NSOffState];
	[item setRepresentedObject:@"kind"];
	[menu addItem:item];
	[item release];
	
	return [menu autorelease];
}

- (void)toggleColumn:(id)sender
{
	NSString *identifier = [sender representedObject];
	
	if ([[[self tableView] dataSource] respondsToSelector:@selector(outlineView:toggleColumn:)])
	{
		[[[self tableView] dataSource] outlineView:(NSOutlineView *)[self tableView] toggleColumn:identifier];
	}
}

@end

@interface NSObject(CKDirectoryOutlineViewDeleteableDataSource)
- (void)tableView:(NSTableView *)tableView deleteRows:(NSArray *)rows;
@end

@implementation CKDirectoryOutlineView

- (void)dealloc
{
	[myQuickSearchString release];
	[super dealloc];
}

- (void)reloadData
{
	if (myIsReloading) return;
	myIsReloading = YES;
	[super reloadData];
	myIsReloading = NO;
}

- (void)searchConcatenationEnded
{
	[myQuickSearchString deleteCharactersInRange:NSMakeRange(0, [myQuickSearchString length])];
}

#define KEYPRESS_DELAY 0.25

- (void)keyDown:(NSEvent *)theEvent
{
	[self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
/*
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchConcatenationEnded) object:nil];
	
	if ([[theEvent characters] characterAtIndex:0] == NSDeleteFunctionKey ||
		[[theEvent characters] characterAtIndex:0] == NSDeleteCharFunctionKey ||
		[[theEvent characters] characterAtIndex:0] == NSDeleteLineFunctionKey)
	{
		[self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
	}
	else if ([[theEvent characters] characterAtIndex:0] == NSUpArrowFunctionKey)
	{
		if ([self selectedRow] > 0)
		{
			[self selectRow:[self selectedRow] - 1 byExtendingSelection:NO];
			[self scrollRowToVisible:[self selectedRow] - 1];
			if ([self target] && [self action])
			{
				[[self target] performSelector:[self action] withObject:self];
			}
		}
	}
	else if ([[theEvent characters] characterAtIndex:0] == NSDownArrowFunctionKey)
	{
		if ([self selectedRow] < [self numberOfRows] - 1)
		{
			[self selectRow:[self selectedRow] + 1 byExtendingSelection:NO];
			[self scrollRowToVisible:[self selectedRow] + 1];
			if ([self target] && [self action])
			{
				[[self target] performSelector:[self action] withObject:self];
			}
		}
	}
	else
	{
		if (!myQuickSearchString)
		{
			myQuickSearchString = [[NSMutableString alloc] initWithString:@""];
		}
		[myQuickSearchString appendString:[theEvent characters]];
		// search for the string as it gets built up
		
		int i, rows = [self numberOfRows];
		NSTableColumn *column = [[self tableColumns] objectAtIndex:0]; 
		NSCell *cell = [column dataCell];
		
		for (i = 0; i < rows; i++)
		{
			[cell setObjectValue:[[self dataSource] outlineView:self objectValueForTableColumn:column byItem:[self itemAtRow:i]]];
			
			if ([[cell stringValue] hasPrefix:myQuickSearchString])
			{
				[self selectRow:i byExtendingSelection:NO];
				if ([self target] && [self action])
				{
					[[self target] performSelector:[self action] withObject:self];
				}
				break;
			}
		}
		
		[self performSelector:@selector(searchConcatenationEnded) withObject:nil afterDelay:KEYPRESS_DELAY];
	}
 */
}

- (void)deleteBackward:(id)sender
{
	if ([[self delegate] respondsToSelector:@selector(tableView:deleteRows:)])
	{
		[[self delegate] tableView:self deleteRows:[[self selectedRowEnumerator] allObjects]];
	}
}

- (void)deleteForward:(id)sender
{
	if ([[self delegate] respondsToSelector:@selector(tableView:deleteRows:)])
	{
		[[self delegate] tableView:self deleteRows:[[self selectedRowEnumerator] allObjects]];
	}
}

// these are from http://www.cocoabuilder.com/archive/message/cocoa/2002/7/28/72439
- (void)moveDown:(id)sender 
{
	[self scrollLineDown:sender];
	if ([self target] && [self action])
	{
		[[self target] performSelector:[self action] withObject:self];
	}
}

- (void)moveUp:(id)sender 
{
	[self scrollLineUp:sender];
	if ([self target] && [self action])
	{
		[[self target] performSelector:[self action] withObject:self];
	}
}

- (void)scrollToRow:(int)row selectRow:(BOOL)select 
{
	if (select) 
	{
		[self selectRow:row byExtendingSelection:NO];
	}
	[self scrollRowToVisible:row];
}

- (void)scrollLineUp:(id)sender 
{
	int row = [self selectedRow];
	if (row < 0) 
	{
		row = [self numberOfRows];
	}
	if (--row >= 0) 
	{
		[self scrollToRow:row selectRow:YES];
	}
}

- (void)scrollLineDown:(id)sender 
{
	int row = [self selectedRow];
	if (++row < [self numberOfRows]) 
	{
		[self scrollToRow:row selectRow:YES];
	}
}

- (void)scrollToBeginningOfDocument:(id)sender 
{
	int rows = [self numberOfRows];
	if (rows) 
	{
		[self scrollToRow:rows selectRow:NO];
	}
}

- (void)scrollToEndOfDocument:(id)sender 
{
	int rows = [self numberOfRows];
	if (rows) 
	{
		[self scrollToRow:rows-1 selectRow:NO];
	}
}

- (void)cancel:(id)sender 
{
	[self abortEditing];
	[[self window] makeFirstResponder:self];
}

- (void)moveRight:(id)sender 
{
	id row;
	NSEnumerator *enumerator = [self selectedRowEnumerator];
	
	while (row = [enumerator nextObject]) 
	{
		[self expandItem:[self itemAtRow:[row intValue]]];
	}
}

- (void)moveLeft:(id)sender 
{
	id row;
	NSEnumerator *enumerator = [self selectedRowEnumerator];
	
	while (row = [enumerator nextObject]) 
	{
		[self collapseItem:[self itemAtRow:[row intValue]]];
	}
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    /*
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"dir options"];
	NSMenuItem *item;
	
	if ([[self dataSource] respondsToSelector:@selector(outlineViewIsShowingHiddenFiles:)])
	{
		item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Show Hidden Files", @"context menu")
										  action:@selector(toggleHiddenFiles:)
								   keyEquivalent:@""];
		[item setTarget:self];
		[item setState:[[self dataSource] outlineViewIsShowingHiddenFiles:self] ? NSOnState : NSOffState];
		[menu addItem:item];
		[item release];
	}
	
	if ([[self dataSource] respondsToSelector:@selector(outlineViewCanBrowseFilePackages:)])
	{
		item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Browse Packages", @"context menu")
										  action:@selector(togglePackageBrowsing:)
								   keyEquivalent:@""];
		[item setTarget:self];
		[item setState:[[self dataSource] outlineViewCanBrowseFilePackages:self] ? NSOnState : NSOffState];
		[menu addItem:item];
		[item release];
	}
	
	if ([[self dataSource] respondsToSelector:@selector(outlineViewShowsFilePackageExtensions:)])
	{
		item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInConnectionKitBundle(@"Show Package Extensions", @"context menu")
										  action:@selector(togglePackageExtensions:)
								   keyEquivalent:@""];
		[item setTarget:self];
		[item setState:[[self dataSource] outlineViewShowsFilePackageExtensions:self] ? NSOnState : NSOffState];
		[menu addItem:item];
		[item release];
	}	

	return [menu autorelease];*/
    return nil;
}

- (void)toggleHiddenFiles:(id)sender
{
	if ([[self dataSource] respondsToSelector:@selector(outlineView:toggleHiddenFiles:)])
	{
		[[self dataSource] outlineView:self toggleHiddenFiles:[sender state] == NSOffState];
	}
}

- (void)togglePackageBrowsing:(id)sender
{
	if ([[self dataSource] respondsToSelector:@selector(outlineView:toggleFilePackages:)])
	{
		[[self dataSource] outlineView:self toggleFilePackages:[sender state] == NSOffState];
	}
}

- (void)togglePackageExtensions:(id)sender
{
	if ([[self dataSource] respondsToSelector:@selector(outlineView:toggleFilePackageExtensions:)])
	{
		[[self dataSource] outlineView:self toggleFilePackageExtensions:[sender state] == NSOffState];
	}
}

@end

@implementation NSOutlineView (CKScrollToTop)

- (void)scrollItemToTop:(id)item
{
	int row = [self rowForItem:item];
	[self selectRow:row byExtendingSelection:NO];
	//scrolling the row only moves it to the bottom of the scroll view, but we want it to go to the top so you can see the folders contents
	if (!NSIntersectsRect([[self enclosingScrollView] documentVisibleRect], [self rectOfRow:row]))
	{
		// only scroll it if it is not already visible
		[self scrollRowToVisible:row];
		NSRect bounds = [[self enclosingScrollView] documentVisibleRect];
		NSRect r = [self rectOfRow:row];
		
		if (NSMinY(r) > NSMidY(bounds))
		{
			// only scroll up if it is at the bottom
			r.origin.y = NSMaxY(bounds) - (2 * NSHeight(r));
			r.size.height += NSHeight(bounds);
			[self scrollRectToVisible:r];
		}
	}
}

@end

@implementation CKTriStateButton

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder])
    {
        [[self cell] setImageDimsWhenDisabled:NO];
        
        // save the normal button image
        [self setNormalImage:[self image]];
        
        // locate the disabled image
        NSBundle *thisBundle = [NSBundle bundleForClass:[self class]];
        NSString *disabledImagePath = [thisBundle pathForImageResource:[self alternateTitle]];
        if (![disabledImagePath isEqualToString:@""])
        {
            NSImage *anImage = [[[NSImage alloc] initByReferencingFile:disabledImagePath] autorelease];
			
            // save the disabled button image
            [self setDisabledImage:anImage];
        }
        [self setAlternateTitle:@""];
        if ([self isEnabled] == NO)
		{
			[self setImage:myDisabledImage];
		}
    }
    return self;
}

- (void)dealloc
{
    [myNormalImage release];
    [myDisabledImage release];
    [super dealloc];
}

- (void)setNormalImage:(NSImage *)image
{
    [image retain];
    [myNormalImage release];
    myNormalImage = image;
}

- (void)setDisabledImage:(NSImage *)image
{
    [image retain];
    [myDisabledImage release];
    myDisabledImage = image;
}

- (void)setEnabled:(BOOL)value
{
    if(value == YES)
	{
		[self setImage:myNormalImage];
	}
    else
	{
		[self setImage:myDisabledImage];
	}
    [super setEnabled:value];    
}

@end

@implementation CKTriStateMenuButton

- (void)setDelegate:(id)delegate
{
	if (![delegate respondsToSelector:@selector(triStateMenuButtonNeedsMenu:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException
									   reason:@"delegate must implement triStateMenuButtonNeedsMenu:"
									 userInfo:nil];
	}
	myDelegate = delegate;
}

- (void)mouseDown:(NSEvent *)theEvent
{
	if ([self isEnabled])
	{
		NSMenu *menu = [myDelegate triStateMenuButtonNeedsMenu:self];
		if (menu) {
			NSImage *orig = [[self image] retain];
			[self setImage:[self alternateImage]];
			NSPoint p = [self frame].origin;
			p = [[self superview] convertPoint:p toView:nil];
			p.y -= 5;
			NSEvent *e = [NSEvent mouseEventWithType:NSLeftMouseDown
											location:p
									   modifierFlags:0
										   timestamp:[NSDate timeIntervalSinceReferenceDate]
										windowNumber:[[self window] windowNumber]
											 context:[NSGraphicsContext currentContext]
										 eventNumber:0
										  clickCount:0
											pressure:0];
			[NSMenu popUpContextMenu:menu withEvent:e forView:self];
			[self setImage:orig];
			[orig release];
		} 
	}
}

@end

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
#import "CKDirectoryNode.h"
#import "NSTabView+Connection.h"
#import "NSPopUpButton+Connection.h"
#import "AbstractConnectionProtocol.h"
#import "NSString+Connection.h"
#import "NSNumber+Connection.h"
#import "CKTableBasedBrowser.h"

enum {
	CKBackButton = 0,
	CKForwardButton
};

NSString *cxRemoteFilenamesPBoardType = @"cxRemoteFilenamesPBoardType";
NSString *cxLocalFilenamesPBoardType = @"cxLocalFilenamesPBoardType";

@interface CKDirectoryTreeController (Private)
- (void)changeRelativeRootToPath:(NSString *)path;
- (void)setupInspectorView:(CKDirectoryNode *)node;
- (BOOL)isFiltering;
@end

@interface NSOutlineView (CKScrollToTop)

- (void)scrollItemToTop:(id)item;

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
	
	myFlags.allowsDrags = YES;
	myFlags.allowsDrops = NO;
	myFlags.isNavigatingToPath = NO;
	myFlags.outlineViewDoubleCallback = NO;
	myFlags.filePackages = YES;
	myFlags.showsFilePackageExtensions = NO;
	
	myCachedContentsThresholdSize = 65536; // 64k threshold
	
	return self;
}

- (void)dealloc
{
	[myRootNode release];
	[myRootDirectory release];
	[mySelectedDirectory release];
	[myHistory release];
	
	[super dealloc];
}

- (void)awakeFromNib
{
	[oPopup removeAllItems];
	[oStyle selectSegmentWithTag:CKBrowserStyle];
	[self viewStyleChanged:oStyle];
	[oHistory setEnabled:NO forSegment:CKBackButton];
	[oHistory setEnabled:NO forSegment:CKForwardButton];
	
	// create all the outline view columns
	myOutlineViewColumns = [[NSMutableDictionary alloc] initWithCapacity:8];
	NSTableColumn *col;
	
	col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	[col setEditable:NO];
	[[col headerCell] setTitle:LocalizedStringInThisBundle(@"Name", @"outline view column header name")];
	[col setDataCell:[[[CKDirectoryCell alloc] initTextCell:@""] autorelease]];
	[myOutlineViewColumns setObject:col forKey:@"name"];
	[col release];
	
	col = [[NSTableColumn alloc] initWithIdentifier:@"modified"];
	[col setEditable:NO];
	[[col headerCell] setTitle:LocalizedStringInThisBundle(@"Date Modified", @"outline view column header name")];
	CKDynamicDateFormattingCell *modifiedCell = [[[CKDynamicDateFormattingCell alloc] initTextCell:@""] autorelease];
	[col setDataCell:modifiedCell];
	[col setMinWidth:150];
	[myOutlineViewColumns setObject:col forKey:@"modified"];
	[col release];
	
	col = [[NSTableColumn alloc] initWithIdentifier:@"size"];
	[col setEditable:NO];
	[[col headerCell] setTitle:LocalizedStringInThisBundle(@"Size", @"outline view column header name")];
	NSTextFieldCell *sizeCell = [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
	[sizeCell setAlignment:NSRightTextAlignment];
	[sizeCell setFormatter:[[[CKFileSizeFormatter alloc] init] autorelease]];
	[col setDataCell:sizeCell];
	[col setMinWidth:80];
	[myOutlineViewColumns setObject:col forKey:@"size"];
	[col release];
	
	col = [[NSTableColumn alloc] initWithIdentifier:@"kind"];
	[col setEditable:NO];
	[[col headerCell] setTitle:LocalizedStringInThisBundle(@"Kind", @"outline view column header name")];
	NSTextFieldCell *kindCell = [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
	[col setDataCell:kindCell];
	[col setMinWidth:150];
	[myOutlineViewColumns setObject:col forKey:@"kind"];
	[col release];
	
	// set the header view for the table
	CKTableHeaderView *header = [[CKTableHeaderView alloc] initWithFrame:[[oOutlineView headerView] frame]];
	[oOutlineView setHeaderView:header];
	[header release];
	
	[oOutlineView addTableColumn:[myOutlineViewColumns objectForKey:@"name"]];
	[oOutlineView setOutlineTableColumn:[myOutlineViewColumns objectForKey:@"name"]];
	[oOutlineView removeTableColumn:[oOutlineView tableColumnWithIdentifier:@"placeholder"]];
	[oOutlineView setDoubleAction:@selector(outlineDoubleClicked:)];
	
	// set up the browser
#define MAX_VISIBLE_COLUMNS 4
	//[oBrowser setMaxVisibleColumns:MAX_VISIBLE_COLUMNS];
    //[oBrowser setMinColumnWidth:NSWidth([oBrowser bounds])/(float)MAX_VISIBLE_COLUMNS];
	//[oBrowser setColumnResizingType:NSBrowserUserColumnResizing];
	[oBrowser setCellClass:[CKDirectoryBrowserCell class]];
	//[oBrowser setMatrixClass:[CKDirectoryBrowserMatrix class]];
	//[oBrowser setSeparatesColumns:YES];
	[oBrowser setTarget:self];
	[oBrowser setAction:@selector(browserSelected:)];
	[oBrowser setDelegate:self];
	[oBrowser setDataSource:self];
	
	[oOutlineView setDataSource:self];
	[oOutlineView setDelegate:self];
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

- (void)reloadViews
{
	// reload the data
	id selectedItem = [oOutlineView itemAtRow:[oOutlineView selectedRow]];
	[oOutlineView reloadData];
	[oOutlineView scrollItemToTop:selectedItem];
	[oOutlineView selectRow:[oOutlineView rowForItem:selectedItem] byExtendingSelection:NO];
	
	NSString *browserPath = [oBrowser path];
	[oBrowser reloadData];
	if (![self isFiltering])
	{
		[oBrowser setPath:browserPath];
	}
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
		[oOutlineView setEnabled:YES];
	}
	else
	{
		[oHistory setEnabled:NO];
		[oStyle setEnabled:NO];
		[oPopup setEnabled:NO];
		[oSearch setEnabled:NO];
		[oBrowser setEnabled:NO];
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
	
	[self reloadViews];
}

- (BOOL)showsHiddenFiles
{
	return myFlags.showsHiddenFiles;
}

- (void)setTreatsFilePackagesAsDirectories:(BOOL)flag
{
	myFlags.filePackages = flag;
	
	[self reloadViews];
}

- (BOOL)treatsFilePackagesAsDirectories
{
	return myFlags.filePackages;
}

- (void)setShowsFilePackageExtensions:(BOOL)flag
{
	myFlags.showsFilePackageExtensions = flag;
	
	[self reloadViews];
}

- (BOOL)showsFilePackageExtensions
{
	return myFlags.showsFilePackageExtensions;
}

- (void)setRootDirectory:(NSString *)dir
{
	if (dir != myRootDirectory)
	{
		[myRootDirectory autorelease];
		myRootDirectory = [dir copy];
		[self changeRelativeRootToPath:dir];	
		
		[oBrowser setPath:dir];
		[oBrowser reloadData];
		
		if (dir)
		{
			[myDelegate directoryTreeStartedLoadingContents:self];
			myDirectoriesLoading++;
			[myDelegate directoryTree:self needsContentsForPath:dir];
		}
	}
	if (!dir)
	{
		[myRootNode autorelease];
		myRootNode = [[CKDirectoryNode nodeWithName:@"/"] retain];
	}
}

- (NSString *)rootDirectory
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

- (void)setContents:(NSArray *)contents forPath:(NSString *)path
{
	myDirectoriesLoading--;
	if (myDirectoriesLoading == 0)
	{
		[myDelegate directoryTreeFinishedLoadingContents:self];
	}
	
	// convert contents to CKDirectoryNodes
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
	
	[self changeRelativeRootToPath:myRelativeRootPath];
	
	[self reloadViews];
}

- (void)setContents:(NSData *)contents forFile:(NSString *)file
{
	CKDirectoryNode *node = [CKDirectoryNode nodeForPath:file withRoot:myRootNode];
	[node setCachedContents:contents];
	
	if (node == mySelectedNode)
	{
		[self setupInspectorView:mySelectedNode];
	}
}

- (NSView *)view
{
	return oView;
}

- (NSArray *)selectedPaths
{
	NSMutableArray *paths = [NSMutableArray array];
	NSArray *items = [oBrowser selectedItems];
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
	
	return nil;
}

- (NSString *)selectedFolderPath
{
	NSArray *items = [oBrowser selectedItems];
	
	if ([items count])
	{
		CKDirectoryNode *cur = [items objectAtIndex:0];
		
		if (![cur isDirectory])
		{
			cur = [cur parent];
		}
		
		return [cur path];
	}
	
	return nil;
}

- (NSArray *)contentsOfSelectedFolder
{
	NSMutableArray *contents = [NSMutableArray array];
	NSArray *items = [oBrowser selectedItems];
	
	if ([items count])
	{
		CKDirectoryNode *cur = [items objectAtIndex:0];
		
		if (![cur isDirectory])
		{
			cur = [cur parent];
		}
		
		NSEnumerator *e = [[cur contents] objectEnumerator];
		CKDirectoryNode *node;
		
		while ((node = [e nextObject]))
		{
			NSDictionary *d = [NSDictionary dictionaryWithDictionary:[node properties]];
			[contents addObject:d];
		}
	}
	
	return contents;
}

#pragma mark -
#pragma mark Interface Helper Methods

- (void)navigateToPath:(NSString *)path
{
	// stop being re-entrant from the outlineview's shouldExpandItem: delegate method
	if(myFlags.isNavigatingToPath) return;
	myFlags.isNavigatingToPath = YES;
	
	//NSLog(@"%@%@", NSStringFromSelector(_cmd), path);
	
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
		
		// expand the folder in the outline view only if it isn't the active view
		if ([oStyles indexOfSelectedTabViewItem] != CKOutlineViewStyle)
		{
			[oOutlineView expandItem:mySelectedNode];
		}
	}
	
	// handle the history
	if ([myHistory count] > 0 && myHistoryIndex < ([myHistory count] - 1))
	{
		// we have used the history buttons and are now taking a new path so we need to remove history from this point forward
		NSRange oldPathRange = NSMakeRange(myHistoryIndex, [myHistory count] - 1 - myHistoryIndex);
		[myHistory removeObjectsInRange:oldPathRange];
	}
	
	// push the new navigation item on the stack
	[myHistory addObject:[NSDictionary dictionaryWithObjectsAndKeys:path, @"fp", myRelativeRootPath, @"rp", nil]];
	myHistoryIndex++;
	
	// update the forward/back buttons
	[oHistory setEnabled:([myHistory count] > 0) forSegment:CKBackButton];
	[oHistory setEnabled:NO forSegment:CKForwardButton]; // a new path is pushed on so no other objects are in front of this one
	
	// make sure the views are in sync
	if ([oStyles indexOfSelectedTabViewItem] != CKBrowserStyle)
	{
		if ([path isEqualToString:myRelativeRootPath])
		{
			[oBrowser setPath:@"/"];
		}
		else
		{
			[oBrowser setPath:[path substringFromIndex:[myRelativeRootPath length]]];
		}
		//[oBrowser scrollColumnToVisible:[[[[mySelectedNode path] substringFromIndex:[myRelativeRootPath length]] componentsSeparatedByString:@"/"] count]];
	}
	
	[oOutlineView scrollItemToTop:mySelectedNode];
	
	myFlags.isNavigatingToPath = NO;
	
	if ([self target] && [self action])
	{
		[[self target] performSelector:[self action] withObject:self];
	}
}

- (void)changeRelativeRootToPath:(NSString *)path
{
	[myRelativeRootPath autorelease];
	myRelativeRootPath = [path copy];
	
	CKDirectoryNode *walk = [CKDirectoryNode nodeForPath:path withRoot:myRootNode];
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"dir structure"];
	NSMenuItem *item;
	
	while (walk)
	{
		item = [[NSMenuItem alloc] initWithTitle:[walk name] 
										  action:nil
								   keyEquivalent:@""];
		[item setRepresentedObject:walk];
		[item setImage:[walk iconWithSize:NSMakeSize(16,16)]];
		[menu insertItem:item atIndex:0];
		[item release];
		walk = [walk parent];
	}
	[oPopup setMenu:menu];
	[menu release];
	
	[oPopup selectItemWithRepresentedObject:[CKDirectoryNode nodeForPath:path withRoot:myRootNode]];
}

- (BOOL)isFiltering
{
	NSString *filterString = [oSearch stringValue];
	return (filterString && ![filterString isEqualToString:@""]);
}

- (void)setupInspectorView:(CKDirectoryNode *)node
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

#pragma mark -
#pragma mark UI Actions

- (IBAction)viewStyleChanged:(id)sender
{
	[oStyles selectTabViewItemAtIndex:[oStyle selectedSegment]];
}

- (IBAction)popupChanged:(id)sender
{
	CKDirectoryNode *node = [sender representedObjectOfSelectedItem];
	NSString *path = [node path];
	
	[self changeRelativeRootToPath:path];
	[oOutlineView reloadData];
	[oBrowser reloadData];
	// this pushes a history object and fetches the contents
	[self navigateToPath:path];
}

- (IBAction)outlineViewSelected:(id)sender
{
	NSString *fullPath = [[oOutlineView itemAtRow:[oOutlineView selectedRow]] path];
	[self navigateToPath:fullPath];
}

- (IBAction)browserSelected:(id)sender
{
	NSString *fullPath = [myRelativeRootPath stringByAppendingPathComponent:[oBrowser path]];
	[self navigateToPath:fullPath];
}

- (IBAction)filterChanged:(id)sender
{
	[self reloadViews];
}

- (IBAction)historyChanged:(id)sender
{
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
	
	[self changeRelativeRootToPath:relPath];
	
	CKDirectoryNode *node = [CKDirectoryNode nodeForPath:[rec objectForKey:@"fp"] withRoot:myRootNode];
	NSMutableArray *nodes = [NSMutableArray arrayWithObject:node];
	CKDirectoryNode *parent = [node parent];
	
	while ((parent))
	{
		[nodes addObject:parent];
		parent = [parent parent];
	}
	
	NSEnumerator *e = [nodes reverseObjectEnumerator];
	CKDirectoryNode *cur;
	
	while ((cur = [e nextObject]))
	{
		// this stops the navigateToPath: stuff being called.
		myFlags.outlineViewDoubleCallback = YES;
		[oOutlineView expandItem:cur];
	}
	
	[oOutlineView scrollItemToTop:node];
	[oBrowser setPath:[fullPath substringFromIndex:[relPath length]]];
	
	// update the forward/back buttons
	[oHistory setEnabled:(myHistoryIndex > 0) forSegment:CKBackButton];
	[oHistory setEnabled:(myHistoryIndex < [myHistory count] - 1) forSegment:CKForwardButton];
}

- (IBAction)outlineDoubleClicked:(id)sender
{
	// a double click will change the relative root path of where we are browsing
	CKDirectoryNode *node = [oOutlineView itemAtRow:[oOutlineView selectedRow]];
	if ([node isFilePackage] && ![self treatsFilePackagesAsDirectories]) return;
	
	NSString *path = [node path];
	[self changeRelativeRootToPath:path];
	[oOutlineView reloadData];
	[oOutlineView deselectAll:self];
	[oBrowser setPath:[oBrowser pathSeparator]];
	[oBrowser reloadData];
}

#pragma mark -
#pragma mark NSOutlineView Data Source

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	//NSLog(@"%@%@", NSStringFromSelector(_cmd), [item path]);
	int result = 0;
	
	if (item == nil)
	{
		if ([self isFiltering])
		{
			return [[[CKDirectoryNode nodeForPath:myRelativeRootPath withRoot:myRootNode] filteredContentsWithNamesLike:[oSearch stringValue] includeHiddenFiles:myFlags.showsHiddenFiles] count];
		}
		item = [CKDirectoryNode nodeForPath:myRelativeRootPath withRoot:myRootNode];
	}
	
	result = [item countIncludingHiddenFiles:myFlags.showsHiddenFiles];
	
	return result;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(int)index ofItem:(id)item
{
	//NSLog(@"%@%@", NSStringFromSelector(_cmd), [item path]);
	id child = nil;
	
	if (item == nil)
	{
		if ([self isFiltering])
		{
			return [[[CKDirectoryNode nodeForPath:myRelativeRootPath withRoot:myRootNode] filteredContentsWithNamesLike:[oSearch stringValue] includeHiddenFiles:myFlags.showsHiddenFiles] objectAtIndex:index];
		}
		item = [CKDirectoryNode nodeForPath:myRelativeRootPath withRoot:myRootNode];
	}
	
	child = [[item contentsIncludingHiddenFiles:myFlags.showsHiddenFiles] objectAtIndex:index];
	
	return child;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	BOOL result = NO;
	
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
		return [NSNumber numberWithUnsignedLongLong:[(CKDirectoryNode *)item size]];
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
	if (myFlags.outlineViewDoubleCallback) 
	{
		myFlags.outlineViewDoubleCallback = NO;
		return YES;
	}
	
	if ([item isDirectory])
	{
		myFlags.outlineViewDoubleCallback = YES;
		// need to fetch from the delegate
		[self navigateToPath:[item path]];
	}
	
	return YES;
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
	return [item name];
}

- (void)tableBrowser:(CKTableBasedBrowser *)browser setObjectValue:(id)object byItem:(id)item
{
	[(CKDirectoryNode *)item setName:object];
}

- (NSString *)tableBrowser:(CKTableBasedBrowser *)browser pathForItem:(id)item
{
	NSString *path = [[item path] substringFromIndex:[myRelativeRootPath length]];
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
	[self setupInspectorView:item];
	return oInspectorView;
}

- (NSMenu *)tableBrowser:(CKTableBasedBrowser *)browser contextMenuWithItem:(id)selectedItem
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"dir options"];
	NSMenuItem *item;
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInThisBundle(@"Show Hidden Files", @"context menu")
									  action:@selector(toggleHiddenFiles:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[self showsHiddenFiles] ? NSOnState : NSOffState];
	[menu addItem:item];
	[item release];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInThisBundle(@"Browse Packages", @"context menu")
									  action:@selector(togglePackageBrowsing:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[self treatsFilePackagesAsDirectories] ? NSOnState : NSOffState];
	[menu addItem:item];
	[item release];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInThisBundle(@"Show Package Extensions", @"context menu")
									  action:@selector(togglePackageExtensions:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[self showsFilePackageExtensions] ? NSOnState : NSOffState];
	[menu addItem:item];
	[item release];
		
	return [menu autorelease];
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

@end

static NSMutableParagraphStyle *sStyle = nil;
#define PADDING 5

@implementation CKDirectoryBrowserCell

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

- (void)setObjectValue:(id)obj
{
	if ([obj isKindOfClass:[CKDirectoryNode class]])
	{
		myNode = obj;
		[self setLeaf:![myNode isDirectory]];
		[self setEnabled:YES];
		[super setObjectValue:[obj name]];
	}
	else
	{
		[super setObjectValue:obj];
	}
}

- (id)objectValue
{
	return [myNode name];
}

- (NSString *)stringValue
{
	return [myNode name];
}

- (NSString *)path
{
	return [myNode path];
}

#define ICON_SIZE 16.0

- (NSSize)cellSizeForBounds:(NSRect)aRect 
{
    NSSize s = [super cellSizeForBounds:aRect];
    s.height += 1.0 * 2.0;
	s.width += NSWidth(aRect);
    return s;
}

- (void)setMakeDragImage:(BOOL)flag
{
	myMakingDragImage = flag;
}

#define ARROW_SIZE 7.0
static NSImage *sArrow = nil;
static NSImage *sSelectedArrow = nil;

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{		
	NSRect imageRect = NSMakeRect(NSMinX(cellFrame), NSMidY(cellFrame) - (ICON_SIZE / 2.0), ICON_SIZE, ICON_SIZE);
	NSRect arrowRect = NSMakeRect(NSMaxX(cellFrame) - ARROW_SIZE - PADDING, NSMidY(cellFrame) - (ARROW_SIZE / 2.0), ARROW_SIZE, ARROW_SIZE);
	
	imageRect = NSOffsetRect(imageRect, PADDING, 0);
	
	BOOL highlighted = [self isHighlighted];
	
	if (highlighted) 
	{
	    [[self highlightColorInView: controlView] set];
	} 
	else 
	{
		if (!myMakingDragImage)
		{
			[[NSColor controlBackgroundColor] set];
		}
	    else
		{
			[[NSColor clearColor] set];
		}
	}
	
	NSRect highlightRect = NSMakeRect(NSMinX(cellFrame), NSMinY(cellFrame), NSWidth(cellFrame), NSHeight(cellFrame));
	NSRectFill(highlightRect);
	
	NSAffineTransform *flip;
	
	if ([controlView isFlipped]) 
	{
		[[NSGraphicsContext currentContext] saveGraphicsState];
		flip = [NSAffineTransform transform];
		[flip translateXBy:0 yBy:NSMaxY(imageRect)];
		[flip scaleXBy:1 yBy:-1];
		[flip concat];
		imageRect.origin.y = 0;
	}
	
	[[myNode iconWithSize:NSMakeSize(ICON_SIZE, ICON_SIZE)] drawInRect:imageRect
															  fromRect:NSZeroRect
															 operation:NSCompositeSourceOver
															  fraction:1.0];
	
	if ([controlView isFlipped]) 
	{
		[flip invert];
		[flip concat];
		[[NSGraphicsContext currentContext] restoreGraphicsState];
	}
	
	NSMutableAttributedString *label = [[NSMutableAttributedString alloc] initWithAttributedString:[self attributedStringValue]];
	NSRange labelRange = NSMakeRange(0, [label length]);
	NSColor *highlightColor = [self highlightColorInView:controlView];
	
	if (highlighted && [highlightColor isEqual:[NSColor alternateSelectedControlColor]]) 
	{
		// add the alternate text color attribute.
		[label addAttribute:NSForegroundColorAttributeName value:[NSColor alternateSelectedControlTextColor] range:labelRange];
	}
	
	[label addAttribute:NSParagraphStyleAttributeName value:sStyle range:labelRange];
	NSSize labelSize = [label size];
	NSRect labelRect = NSMakeRect(NSMaxX(imageRect) + PADDING,  
								  NSMidY(cellFrame) - (labelSize.height / 2),
								  NSMinX(arrowRect) - NSMaxX(imageRect) - (2 * PADDING),
								  labelSize.height);
	[label drawInRect:labelRect];
	[label release];
	
	if (![self isLeaf])
	{
		if (!sArrow)
		{
			NSBundle *b = [NSBundle bundleForClass:[self class]];
			NSString *path = [b pathForResource:@"container_triangle" ofType:@"tiff"];
			sArrow = [[NSImage alloc] initWithContentsOfFile:path];
			path = [b pathForResource:@"container_triangle_selected" ofType:@"tiff"];
			sSelectedArrow = [[NSImage alloc] initWithContentsOfFile:path];
		}
		
		NSImage *arrow = sArrow;
		if (highlighted) arrow = sSelectedArrow;
		
		NSAffineTransform *flip;
		
		if ([controlView isFlipped]) 
		{
			[[NSGraphicsContext currentContext] saveGraphicsState];
			flip = [NSAffineTransform transform];
			[flip translateXBy:0 yBy:NSMaxY(arrowRect)];
			[flip scaleXBy:1 yBy:-1];
			[flip concat];
			arrowRect.origin.y = 0;
		}
		
		[arrow drawInRect:arrowRect
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
}

@end

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
	
	NSAffineTransform *flip;
	
	if ([controlView isFlipped]) 
	{
		[[NSGraphicsContext currentContext] saveGraphicsState];
		flip = [NSAffineTransform transform];
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
        return nil;
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
	[self setFormatter:[[[NSDateFormatter alloc] initWithDateFormat:[[NSUserDefaults standardUserDefaults] objectForKey:NSShortTimeDateFormatString] allowNaturalLanguage:YES] autorelease]];
	
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
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInThisBundle(@"Name", @"outline view column context menu item")
									  action:nil
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[[self tableView] tableColumnWithIdentifier:@"name"] != nil ? NSOnState : NSOffState];
	[item setRepresentedObject:@"name"];
	[menu addItem:item];
	[item release];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInThisBundle(@"Date Modified", @"outline view column context menu item")
									  action:@selector(toggleColumn:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[[self tableView] tableColumnWithIdentifier:@"modified"] != nil ? NSOnState : NSOffState];
	[item setRepresentedObject:@"modified"];
	[menu addItem:item];
	[item release];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInThisBundle(@"Size", @"outline view column context menu item")
									  action:@selector(toggleColumn:)
							   keyEquivalent:@""];
	[item setTarget:self];
	[item setState:[[self tableView] tableColumnWithIdentifier:@"size"] != nil ? NSOnState : NSOffState];
	[item setRepresentedObject:@"size"];
	[menu addItem:item];
	[item release];
	
	item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInThisBundle(@"Kind", @"outline view column context menu item")
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


@implementation CKDirectoryOutlineView

- (void)dealloc
{
	[myQuickSearchString release];
	[super dealloc];
}

- (void)searchConcatenationEnded
{
	[myQuickSearchString deleteCharactersInRange:NSMakeRange(0, [myQuickSearchString length])];
}

#define KEYPRESS_DELAY 0.25

- (void)keyDown:(NSEvent *)theEvent
{
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

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"dir options"];
	NSMenuItem *item;
	
	if ([[self dataSource] respondsToSelector:@selector(outlineViewIsShowingHiddenFiles:)])
	{
		item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInThisBundle(@"Show Hidden Files", @"context menu")
										  action:@selector(toggleHiddenFiles:)
								   keyEquivalent:@""];
		[item setTarget:self];
		[item setState:[[self dataSource] outlineViewIsShowingHiddenFiles:self] ? NSOnState : NSOffState];
		[menu addItem:item];
		[item release];
	}
	
	if ([[self dataSource] respondsToSelector:@selector(outlineViewCanBrowseFilePackages:)])
	{
		item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInThisBundle(@"Browse Packages", @"context menu")
										  action:@selector(togglePackageBrowsing:)
								   keyEquivalent:@""];
		[item setTarget:self];
		[item setState:[[self dataSource] outlineViewCanBrowseFilePackages:self] ? NSOnState : NSOffState];
		[menu addItem:item];
		[item release];
	}
	
	if ([[self dataSource] respondsToSelector:@selector(outlineViewShowsFilePackageExtensions:)])
	{
		item = [[NSMenuItem alloc] initWithTitle:LocalizedStringInThisBundle(@"Show Package Extensions", @"context menu")
										  action:@selector(togglePackageExtensions:)
								   keyEquivalent:@""];
		[item setTarget:self];
		[item setState:[[self dataSource] outlineViewShowsFilePackageExtensions:self] ? NSOnState : NSOffState];
		[menu addItem:item];
		[item release];
	}	

	return [menu autorelease];
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

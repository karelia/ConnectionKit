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

#import "CKTableBasedBrowser.h"
#import "CKDirectoryBrowserCell.h"
#import <Carbon/Carbon.h>

@class CKResizingButton;

@interface CKBrowserTableView : NSTableView
{
	NSMutableString *myQuickSearchString;
}
@end

@interface NSObject (CKBrowserTableViewDelegateExtensions)
- (void)tableView:(NSTableView *)tableView deleteRows:(NSArray *)rows;
- (void)tableView:(NSTableView *)tableView didKeyPress:(NSString *)partialSearch;
- (NSMenu *)tableView:(NSTableView *)tableView contextMenuForEvent:(NSEvent *)theEvent;
- (void)tableViewNavigateForward:(NSTableView *)tableView;
- (void)tableViewNavigateBackward:(NSTableView *)tableView;

@end

@interface CKTableBrowserScrollView : NSScrollView
{
	CKResizingButton *myResizer;
	
	struct __cktv_flags {
		unsigned canResize: 1;
		unsigned unused: 1;
	} myFlags;
}

- (void)setCanResize:(BOOL)flag;
- (BOOL)canResize;
- (CKResizingButton *)resizer;

@end

@interface CKTableBasedBrowser (Private)

- (void)reflowColumns;
- (NSString *)parentPathOfPath:(NSString *)path;
- (NSString *)parentPathOfItem:(id)item;
- (id)parentOfItem:(id)item;
- (void)updateScrollers;
- (void)leafInspectItem:(id)item scrollToVisible:(BOOL)showColumn;
- (void)tableSelectedCell:(id)sender notifyTarget:(BOOL)flag scrollToVisible:(BOOL)showColumn;
- (unsigned)rowForItem:(id)item;
- (void)removeAllColumns;
- (NSRect)boundsForColumn:(unsigned)col;
- (CKTableBrowserScrollView *)createScrollerWithRect:(NSRect)rect;
- (id)createColumn:(unsigned)colIndex;
- (void)setPath:(NSString *)path checkPath:(BOOL)flag;
- (void)removeLeafView;
- (void)tableSelectedCell:(id)sender;

@end

#define SCROLLER_WIDTH 16.0

static Class sCellClass = nil;

@implementation CKTableBasedBrowser

+ (void)initialize
{
	sCellClass = [CKDirectoryBrowserCell class];
}

+ (Class)cellClass
{
	return sCellClass;
}

- (id)initWithFrame:(NSRect)rect
{
	if ((self != [super initWithFrame:rect]))
	{
		[self release];
		return nil;
	}
	
	[self setCellClass:[CKTableBasedBrowser class]];
	myColumns = [[NSMutableArray alloc] initWithCapacity:8];
    myScrollers = [[NSMutableArray alloc] initWithCapacity:8];
	myColumnWidths = [[NSMutableDictionary alloc] initWithCapacity:8];
    myColumnSelectedCells = [[NSMutableDictionary alloc] initWithCapacity:8];
	mySelection = [[NSMutableArray alloc] initWithCapacity:32];
	
	myAutosaveName = @"Default";
	myPathSeparator = @"/";
	myCurrentPath = @"/";
	
	myMinColumnWidth = 180;
	myMaxColumnWidth = -1;
	myRowHeight = 18;
	myDefaultColumnWidth = -1;
	
	myFlags.allowsMultipleSelection = NO;
	myFlags.allowsResizing = YES;
	myFlags.isEditable = NO;
	myFlags.isEnabled = YES;
	
	return self;
}

- (void)dealloc
{
	[myColumns release];
    [myScrollers release];
	[myColumnWidths release];
    [myColumnSelectedCells release];
	[mySelection release];
	[myCellPrototype release];
	[myAutosaveName release];
	[myPathSeparator release];
	
	[super dealloc];
}

- (void)drawRect:(NSRect)rect
{
	[[NSColor whiteColor] set];
	NSRectFill(rect);
}

- (void)setCellClass:(Class)aClass
{
	myCellClass = aClass;
}

- (id)cellPrototype
{
	return myCellPrototype;
}

- (void)setCellPrototype:(id)prototype
{
	[myCellPrototype autorelease];
	myCellPrototype = [prototype retain];
}

- (void)setEnabled:(BOOL)flag
{
	if (myFlags.isEnabled != flag)
	{
		myFlags.isEnabled = flag;
		
		// go through and dis/en able things
		NSEnumerator *e = [myColumns objectEnumerator];
		NSTableView *cur;
		
		while ((cur = [e nextObject]))
		{
			[cur setEnabled:flag];
			[[[cur enclosingScrollView] verticalScroller] setEnabled:flag];
		}
	}
}

- (BOOL)isEnabled
{
	return myFlags.isEnabled;
}

- (void)setAllowsMultipleSelection:(BOOL)flag
{
	if (myFlags.allowsMultipleSelection != flag)
	{
		myFlags.allowsMultipleSelection = flag;
		
		if (myFlags.allowsMultipleSelection)
		{
			// we need to make sure that the current selection(s) hold to the new rule
			
		}
	}
}

- (BOOL)allowsMultipleSelection
{
	return myFlags.allowsMultipleSelection;
}

- (void)setAllowsColumnResizing:(BOOL)flag
{
	if (myFlags.allowsResizing != flag)
	{
		myFlags.allowsResizing = flag;
		
		//update the current columns
		NSEnumerator *e = [myColumns objectEnumerator];
		NSTableView *cur;
		
		while ((cur = [e nextObject]))
		{
			[(CKTableBrowserScrollView *)[cur enclosingScrollView] setCanResize:myFlags.allowsResizing];
		}
	}
}

- (BOOL)allowsColumnResizing
{
	return myFlags.allowsResizing;
}

- (void)setEditable:(BOOL)flag
{
	if (myFlags.isEditable != flag)
	{
		myFlags.isEditable = flag;
		
		// update the table views to make sure their columns aren't editable
		NSEnumerator *e = [myColumns objectEnumerator];
		NSTableView *cur;
		
		while ((cur = [e nextObject]))
		{
			NSEnumerator *f = [[cur tableColumns] objectEnumerator];
			NSTableColumn *col;
			
			while ((col = [f nextObject]))
			{
				[col setEditable:flag];
			}
		}
	}
}

- (BOOL)isEditable
{
	return myFlags.isEditable;
}

- (void)setRowHeight:(float)height
{
	myRowHeight = height;
	
	// update all current cols
	NSEnumerator *e = [myColumns objectEnumerator];
	NSTableView *cur;
	
	while ((cur = [e nextObject]))
	{
		[cur setRowHeight:myRowHeight];
	}
}

- (float)rowHeight
{
	return myRowHeight;
}

- (void)setMinColumnWidth:(float)size
{
	if (myMinColumnWidth > myMaxColumnWidth)
	{
		myMaxColumnWidth = size;
	}
	myMinColumnWidth = size;
	
	[self reflowColumns];
}

- (float)minColumnWidth
{
	return myMinColumnWidth;
}

- (void)setMaxColumnWidth:(float)size
{
	if (myMaxColumnWidth < myMinColumnWidth)
	{
		myMinColumnWidth = size;
	}
	myMaxColumnWidth = size;
	
	[self reflowColumns];
}

- (float)maxColumnWidth
{
	return myMaxColumnWidth;
}

- (void)setDefaultColumnWidth:(float)width
{
	myDefaultColumnWidth = width;
    
    // remove all existing scrollers
    NSEnumerator *e = [myScrollers objectEnumerator];
    NSScroller *cur;
    
    while ((cur = [e nextObject]))
    {
        [cur removeFromSuperviewWithoutNeedingDisplay];
    }
    [myScrollers removeAllObjects];
    [self removeAllColumns];
    
    // add in scrollers to fit the width
    unsigned i = 0;
    NSRect bounds = [[self enclosingScrollView] documentVisibleRect];
    CKTableBrowserScrollView *scroller = [self createScrollerWithRect:[self boundsForColumn:i]];
    NSRect r = [scroller frame];
    [self addSubview:scroller];
    i++;
    
    while (NSMaxX(r) < NSMaxX(bounds) - 1)
    {
        scroller = [self createScrollerWithRect:[self boundsForColumn:i]];
        r = [scroller frame];
        [self addSubview:scroller];
        i++;
    }
	
	if (myDefaultColumnWidth < myMinColumnWidth)
	{
		myMinColumnWidth = myDefaultColumnWidth;
	}
    
    myMinVisibleColumns = [myScrollers count];
	[self reloadData];
}

- (void)setPathSeparator:(NSString *)sep
{
	if (myPathSeparator != sep)
	{
		[myPathSeparator autorelease];
		myPathSeparator = [sep copy];
	}
}

- (NSString *)pathSeparator
{
	return myPathSeparator;
}

- (void)selectAll:(id)sender
{
	if (myFlags.allowsMultipleSelection)
	{
		// TODO
	}
}

- (void)selectItem:(id)item
{
	[self selectItems:[NSArray arrayWithObject:item]];
}

- (void)selectItems:(NSArray *)items
{
	//unsigned i, c = [items count];
	
	// remove current selection
	[mySelection removeAllObjects];
	if ([myColumns count] > 0)
	{
		// only need to deselect everything in the first column as other columns will auto refresh
		// [[myColumns objectAtIndex:0] deselectAll:self]; 
	}
	
	//NSTableView *firstSelectedItemColumn = nil;
	
	if ([items count] > 0)
	{
		//unsigned col, row;
		id item = [items objectAtIndex:0];
		
		// set the path based on the first item
		NSString *path = [myDataSource tableBrowser:self pathForItem:item];
		[self setPath:path];
		
		// this assignment to path does not appear to be used
		// path = [myDataSource tableBrowser:self pathForItem:item];
	}
	
//	for (i = 0; i < c; i++)
//	{
//		id item = [items objectAtIndex:i];
//		unsigned col, row;
//		
//		[self column:&col row:&row forItem:item];
//		
//		if (col != NSNotFound)
//		{
//			NSTableView *column = [myColumns objectAtIndex:col];
//			if (column == firstSelectedItemColumn) // we can only multiselect in the same column
//			{
//				[column selectRow:row byExtendingSelection:myFlags.allowsMultipleSelection];
//				[self tableSelectedCell:column notifyTarget:NO scrollToVisible:NO];
//			}
//		}
//	}
}

- (NSArray *)selectedItems
{
	NSMutableArray *items = [NSMutableArray array];
	NSEnumerator *e = [mySelection objectEnumerator];
	NSString *cur;
	
	while ((cur = [e nextObject]))
	{
		id item = [myDataSource tableBrowser:self itemForPath:cur];
		if (item)
		{
			[items addObject:item];
		}
	}
	return items;
}

- (void)setPath:(NSString *)path checkPath:(BOOL)flag
{    
	NSLog(@"%s%@", _cmd, path);
    NSString *currentPathDisplayed = [[[self path] copy] autorelease];
    if (!currentPathDisplayed) currentPathDisplayed = [self pathSeparator];
    
    BOOL showColumn = [path isEqualToString:[self path]];
    
    if (path == nil || [path isEqualToString:@""] || [path isEqualToString:[self pathSeparator]]) 
	{
        [self removeAllColumns];
        [mySelection removeAllObjects];
		[myCurrentPath autorelease]; myCurrentPath = [[self pathSeparator] copy];
		
		// remove all scrollers except for the myMinVisibleColumns ones
		if ([myScrollers count] > myMinVisibleColumns)
		{
			[myScrollers removeObjectsInRange:NSMakeRange(myMinVisibleColumns, [myScrollers count] - myMinVisibleColumns)];
		}
        
        // add the root column back
        NSScrollView *column = [self createColumn:0];
        [self addSubview:column];
        [self updateScrollers];
	}
	else
	{        
        id item = [myDataSource tableBrowser:self itemForPath:path];
        if (item)
        {
            // push it on as a selection so the reloading of the tables picks up the correct source
            [mySelection addObject:[[path copy] autorelease]];
            
            // enumerate over the path and simulate table clicks
            NSString *separator = [self pathSeparator];
            NSRange r = [path rangeOfString:currentPathDisplayed];
            if (r.location == NSNotFound)
            {
                r = [path rangeOfString:separator];
            }
            else
            {
                r = [path rangeOfString:separator options:NSLiteralSearch range:NSMakeRange(NSMaxRange(r), [path length] - NSMaxRange(r))];
            }
            unsigned row, col;
            
            while (r.location != NSNotFound)
            {
                NSString *bit = [path substringToIndex:r.location];
                [self column:&col row:&row forItem:[myDataSource tableBrowser:self itemForPath:bit]];
                
				NSLog(@"%@ r=%d c=%d", bit, row, col);
				
				// TODO: this might be a leaf node.
                if (col == NSNotFound)
                {
                    NSScrollView *column = [self createColumn:[myColumns count]];
                    [self addSubview:column];
                    [self column:&col row:&row forItem:[myDataSource tableBrowser:self itemForPath:bit]];
                }
                
                if (col != NSNotFound && row != NSNotFound)
                {
                    NSTableView *column = nil;
                    
                    if (col < [myColumns count])
                    {
                        column = [myColumns objectAtIndex:col];
                    }
                    else
                    {
                        column = [self createColumn:[myColumns count]];
                        [self addSubview:column];
                        column = [(NSScrollView *)column documentView];
                    }
                    [column reloadData];
                    [column selectRow:row byExtendingSelection:NO];
                    [self tableSelectedCell:column notifyTarget:NO scrollToVisible:NO];
                    [column scrollRowToVisible:row];
                }
                
                r = [path rangeOfString:separator options:NSLiteralSearch range:NSMakeRange(NSMaxRange(r), [path length] - NSMaxRange(r))];
            }
            // now do the last path component
            [self column:&col row:&row forItem:item];
            if (col != NSNotFound && row != NSNotFound)
            {
                NSTableView *column = [myColumns objectAtIndex:col];
                [column selectRow:row byExtendingSelection:NO];
                [self tableSelectedCell:column notifyTarget:NO scrollToVisible:showColumn];
                [column scrollRowToVisible:row];
                [[self window] makeFirstResponder:column];
            }
            else
            {
                // reload just the last column
                [[myColumns lastObject] reloadData];
            }
            [self updateScrollers];
        }
        else
        {
            // the path doesn't exist anymore so we should get the parent path
            NSLog(@"path no long exists");
        }
    }
}

- (void)setPath:(NSString *)path
{
    [self setPath:path checkPath:YES];
}

- (NSString *)path
{
	if ([mySelection count] == 0) return nil;
	
	return [mySelection lastObject];
}

- (void)setTarget:(id)target
{
	myTarget = target;
}

- (id)target
{
	return myTarget;
}

- (void)setAction:(SEL)anAction
{
	myAction = anAction;
}

- (SEL)action
{
	return myAction;
}

- (void)setDoubleAction:(SEL)anAction
{
	myDoubleAction = anAction;
}

- (SEL)doubleAction
{
	return myDoubleAction;
}

- (void)setDataSource:(id)ds
{
	if (![ds respondsToSelector:@selector(tableBrowser:numberOfChildrenOfItem:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"dataSource must implement tableBrowser:numberOfChildrenOfItem:" userInfo:nil];
	}
	if (![ds respondsToSelector:@selector(tableBrowser:child:ofItem:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"dataSource must implement tableBrowser:child:ofItem:" userInfo:nil];
	}
	if (![ds respondsToSelector:@selector(tableBrowser:isItemExpandable:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"dataSource must implement tableBrowser:isItemExpandable:" userInfo:nil];
	}
	if (![ds respondsToSelector:@selector(tableBrowser:objectValueByItem:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"dataSource must implement tableBrowser:objectValueByItem:" userInfo:nil];
	}
	if (![ds respondsToSelector:@selector(tableBrowser:pathForItem:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"dataSource must implement tableBrowser:pathForItem:" userInfo:nil];
	}
	if (![ds respondsToSelector:@selector(tableBrowser:itemForPath:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"dataSource must implement tableBrowser:itemForPath:" userInfo:nil];
	}
	myDataSourceFlags.numberOfChildrenOfItem = YES;
	myDataSourceFlags.childOfItem = YES;
	myDataSourceFlags.isItemExpandable = YES;
	myDataSourceFlags.objectValueByItem = YES;
	myDataSourceFlags.itemForPath = YES;
	myDataSourceFlags.pathForItem = YES;
	
	// these are optionals
	myDataSourceFlags.setObjectValueByItem = [ds respondsToSelector:@selector(tableBrowser:setObjectValue:byItem:)];
	myDataSourceFlags.acceptDrop = [ds respondsToSelector:@selector(tableBrowser:acceptDrop:item:childIndex:)];
	myDataSourceFlags.validateDrop = [ds respondsToSelector:@selector(tableBrowser:validateDrop:proposedItem:proposedChildIndex:)];
	myDataSourceFlags.writeItemsToPasteboard = [ds respondsToSelector:@selector(tableBrowser:writeItems:toPasteboard:)];
		
	myDataSource = ds;
	
	[self updateScrollers];
	[self reloadData];
}

- (id)dataSource
{
	return myDataSource;
}

- (void)setDelegate:(id)delegate
{
	myDelegateFlags.shouldExpandItem = [delegate respondsToSelector:@selector(tableBrowser:shouldExpandItem:)];
	myDelegateFlags.shouldSelectItem = [delegate respondsToSelector:@selector(tableBrowser:shouldSelectItem:)];
	myDelegateFlags.willDisplayCell = [delegate respondsToSelector:@selector(tableBrowser:willDisplayCell:)];
	myDelegateFlags.tooltipForCell = [delegate respondsToSelector:@selector(tableBrowser:toolTipForCell:rect:item:mouseLocation:)];
	myDelegateFlags.shouldEditItem = [delegate respondsToSelector:@selector(tableBrowser:shouldEditItem:)];
	myDelegateFlags.leafViewWithItem = [delegate respondsToSelector:@selector(tableBrowser:leafViewWithItem:)];
	myDelegateFlags.contextMenuWithItem = [delegate respondsToSelector:@selector(tableBrowser:contextMenuWithItem:)];
	
	myDelegate = delegate;
}

- (id)delegate
{
	return myDelegate;
}

- (BOOL)isExpandable:(id)item
{
	return [myDataSource tableBrowser:self isItemExpandable:item];
}

- (void)expandItem:(id)item
{
	if ([self isExpandable:item])
	{
		// TODO
	}
}

- (unsigned)columnWithTable:(NSTableView *)table
{
	return [myColumns indexOfObjectIdenticalTo:table];
}


- (NSString *)pathToColumn:(unsigned)column
{
	NSString *separator = [self pathSeparator];
	if (myCurrentPath == nil || [myCurrentPath isEqualToString:separator] || (int)column <= 0) return separator;
	
	NSMutableString *path = [NSMutableString stringWithString:separator];
	NSRange range = [myCurrentPath rangeOfString:separator];
	NSRange lastRange = NSMakeRange(0, [separator length]);
	unsigned i;
	
	for (i = 0; i < column; i++)
	{
		//if (range.location == NSNotFound) return nil; // incase the column requested is invalid compared to the current path
		range = [myCurrentPath rangeOfString:separator options:NSLiteralSearch range:NSMakeRange(NSMaxRange(range), [myCurrentPath length] - NSMaxRange(range))];
		NSRange componentRange;
		
		if (range.location == NSNotFound)
		{
			componentRange = NSMakeRange(NSMaxRange(lastRange), [myCurrentPath length] - NSMaxRange(lastRange));
		}
		else
		{
			componentRange = NSMakeRange(NSMaxRange(lastRange), NSMaxRange(range) - NSMaxRange(lastRange));
		}
		
		[path appendString:[myCurrentPath substringWithRange:componentRange]];
		lastRange = range;
	}
		
	return path;
}

- (unsigned)columnToItem:(id)item
{
	NSString *itemPath = [myDataSource tableBrowser:self pathForItem:item];
	BOOL isItemVisible = NO;
	
	// see if the path is visible
	NSString *parentPath = [self parentPathOfPath:itemPath];
	if ([myCurrentPath hasPrefix:parentPath])
	{
		isItemVisible = YES;
	}
	
	unsigned column = NSNotFound;
	
	if (isItemVisible)
	{
		unsigned i, c = [myColumns count];
		
		for (i = 0; i < c; i++)
		{
			if ([[self pathToColumn:i] isEqualToString:parentPath])
			{
				column = i;
				break;
			}
		}
	}
	
	
	return column;
}

- (void)removeAllColumns
{
	NSEnumerator *e = [myColumns objectEnumerator];
	NSTableView *cur;
	
	while ((cur = [e nextObject]))
	{
		NSScrollView *scroller = [cur enclosingScrollView];
		[cur setDataSource:nil];
        [scroller setDocumentView:nil];
	}
	[myColumns removeAllObjects];
    
    [self removeLeafView];
}

- (CKTableBrowserScrollView *)createScrollerWithRect:(NSRect)rect
{
    CKTableBrowserScrollView *scroller = [[CKTableBrowserScrollView alloc] initWithFrame:rect];
	[scroller setHasVerticalScroller:YES];
	[scroller setHasHorizontalScroller:NO];
	[[scroller resizer] setDelegate:self];
	[scroller setAutoresizingMask: NSViewHeightSizable];
    [myScrollers addObject:scroller];
    
    return [scroller autorelease];
}

- (id)createColumn:(unsigned)colIndex
{
    NSRect rect = [self boundsForColumn:colIndex];
	CKTableBrowserScrollView *scroller = nil;
    
    if ([myScrollers count] > colIndex)
    {
        scroller = [myScrollers objectAtIndex:colIndex];
    }
    else
    {
        scroller = [self createScrollerWithRect:rect];
    }
    
	CKBrowserTableView *table = [[CKBrowserTableView alloc] initWithFrame:[scroller documentVisibleRect]];
	[scroller setDocumentView:table];
	[myColumns addObject:table];
	[table setAutoresizingMask:NSViewHeightSizable];
	[table setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
	[table release];
    
    [[scroller contentView] setCopiesOnScroll:NO];
	
	// configure table
	NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"ckbrowser"];
	[col setEditable:myFlags.isEditable];
	if ([self cellPrototype])
	{
		[col setDataCell:[self cellPrototype]];
	}
	else
	{
		NSCell *cell = [[myCellClass alloc] initTextCell:@""];
		[col setDataCell:cell];
		[cell release];
	}
	[table setAllowsEmptySelection:YES];
	[table setHeaderView:nil];
	[table addTableColumn:col];
	[col setWidth:NSWidth([table frame])];
    [table sizeToFit];
	[table setTarget:self];
	[table setAction:@selector(tableSelectedCell:)];
	[table setAllowsColumnResizing:NO];
	[table setAllowsColumnReordering:NO];
	[table setAllowsColumnSelection:NO];
	[table setAllowsMultipleSelection:myFlags.allowsMultipleSelection];
	[table setRowHeight:myRowHeight];
	[table setFocusRingType:NSFocusRingTypeNone];
	
	[col release];
	
	[table setDataSource:self];
	[table setDelegate:self];
	
	return scroller;
}

- (NSRect)boundsForColumn:(unsigned)col
{
    NSRect bounds = [[self enclosingScrollView] documentVisibleRect];
	NSRect columnRect = NSMakeRect(0, 0, myMinColumnWidth, NSHeight(bounds));
    
    NSTableView *lastColumn = nil;
    
    if ([myColumns count] > col)
    {
        lastColumn = [myColumns objectAtIndex:col];
    }
    
    if (lastColumn)
    {
        NSScrollView *scroller = [lastColumn enclosingScrollView];
        columnRect.origin.x = NSMaxX([scroller frame]) + 1;
    }
    else
    {
        // see if there is a scroller already created for this column and use it
        if ([myScrollers count] > col)
        {
            columnRect = [[myScrollers objectAtIndex:col] frame];
            return columnRect;
        }
        else
        {
            // try the last scroller
            if ([myScrollers lastObject])
            {
                columnRect.origin.x = NSMaxX([[myScrollers lastObject] frame]) + 1;
            }
        }
    }
    
    // see if there is a custom width
    if ([myColumnWidths objectForKey:[NSNumber numberWithUnsignedInt:col]])
    {
        columnRect.size.width = [[myColumnWidths objectForKey:[NSNumber numberWithUnsignedInt:col]] floatValue];
    }
    else if (myDefaultColumnWidth > 0)
    {
        columnRect.size.width = myDefaultColumnWidth;
    }
    else
    {
        columnRect.size.width = myMinColumnWidth;
    }
    
    return columnRect;
}

- (void)updateScrollers
{
	// get the total width of the subviews
	float maxX = 0;
	
	maxX = NSMaxX([[myScrollers lastObject] frame]);

	NSRect docArea = [[self enclosingScrollView] documentVisibleRect];
	NSRect bounds = NSMakeRect(0, 0, maxX, NSHeight(docArea));
	
	if (maxX < NSWidth(docArea))
	{
		bounds.size.width = NSWidth(docArea);
	}
	
	[self setFrameSize:bounds.size];
}

- (void)refreshColumn:(unsigned)col
{
	if (col < [myColumns count])
	{
		[[myColumns objectAtIndex:col] reloadData];
		[self tableSelectedCell:[myColumns objectAtIndex:col]];
	}
}

- (void)reloadData
{
	// load the first column and then subsequent columns based on the myCurrentPath
	
	// if required create column, then reload the data
/*	NSArray *pathComponents = [myCurrentPath componentsSeparatedByString:[self pathSeparator]];
	if ([myCurrentPath isEqualToString:[self pathSeparator]])
	{
		pathComponents = [pathComponents subarrayWithRange:NSMakeRange(1, [pathComponents count] - 1)];
	}
	
	unsigned i, c = [pathComponents count];
	
	for (i = 0; i < c; i++)
	{
		if (i >= [myColumns count])
		{			
			// create the column
			NSScrollView *col = [self createColumn:i];
			[self addSubview:col];
		}
		NSTableView *column = [myColumns objectAtIndex:i];
		[column reloadData];
	}
	
	// update the horizontal scroller
	[self updateScrollers];
	
	// if there are any columns that aren't needed anymore, remove them
	for (i = c; i < [myColumns count]; i++)
	{
		NSScrollView *col = [[myColumns objectAtIndex:i] enclosingScrollView];
		[col removeFromSuperview];
	}
    
    [self removeLeafView];
	[myColumns removeObjectsInRange:NSMakeRange(c, [myColumns count] - c)];
	
	[self updateScrollers];*/
}

- (void)reloadItem:(id)item
{
	unsigned column = [self columnToItem:item];
	if (column != NSNotFound)
	{
		[[myColumns objectAtIndex:column] reloadData];
	}
}

- (void)reloadItem:(id)item reloadChildren:(BOOL)flag
{
	[self reloadItem:item];
	
	// TODO - reload children
}

- (id)itemAtColumn:(unsigned)column row:(unsigned)row
{
	return nil;
}

- (NSString *)parentPathOfPath:(NSString *)path
{
	NSRange r = [path rangeOfString:[self pathSeparator] options:NSBackwardsSearch];
	
	if (r.location != NSNotFound)
	{
		path = [path substringToIndex:r.location];
	}
	
	if ([path isEqualToString:@""]) path = [self pathSeparator];
	
	return path;
}

- (NSString *)parentPathOfItem:(id)item
{
	NSString *path = [myDataSource tableBrowser:self pathForItem:item];
	return [self parentPathOfPath:path];
}

- (id)parentOfItem:(id)item
{
	return [myDataSource tableBrowser:self itemForPath:[self parentPathOfItem:item]];
}

- (unsigned)rowForItem:(id)item
{
	id parent = [self parentOfItem:item];
	unsigned i, c = [myDataSource tableBrowser:self numberOfChildrenOfItem:parent];
	for (i = 0; i < c; i++)
	{
		if ([myDataSource tableBrowser:self child:i ofItem:parent] == item)
		{
			return i;
		}
	}
	return NSNotFound;
}

- (void)column:(unsigned *)column row:(unsigned *)row forItem:(id)item
{
	unsigned col = [self columnToItem:item];
	unsigned r = [self rowForItem:item];
	
	if (column) *column = col;
	if (row) *row = r;
}

- (void)setAutosaveName:(NSString *)name
{
	if (myAutosaveName != name)
	{
		[myAutosaveName autorelease];
		myAutosaveName = [name copy];
	}
}

- (NSString *)autosaveName
{
	return myAutosaveName;
}

- (void)scrollItemToVisible:(id)item
{
	
}

- (NSRect)frameOfColumnContainingItem:(id)item
{
	return NSZeroRect;
}

- (void)leafInspectItem:(id)item scrollToVisible:(BOOL)showColumn
{
	if (myDelegateFlags.leafViewWithItem)
	{
		myLeafView = [myDelegate tableBrowser:self leafViewWithItem:item];
		if (myLeafView)
		{
            CKTableBrowserScrollView *scroller = nil;
            if ([myScrollers count] > [myColumns count])
            {
                scroller = [myScrollers objectAtIndex:[myColumns count]];
            }
            else
            {
                scroller = [self createScrollerWithRect:[self boundsForColumn:[myColumns count]]];
            }
			NSRect lastColumnFrame = [scroller frame];
			
			// get the custom width for the column
			if ([myColumnWidths objectForKey:[NSNumber numberWithUnsignedInt:[myColumns count]]])
			{
				lastColumnFrame.size.width = [[myColumnWidths objectForKey:[NSNumber numberWithUnsignedInt:[myColumns count]]] floatValue];
			}
			else if (myDefaultColumnWidth > 0)
			{
				lastColumnFrame.size.width = myDefaultColumnWidth;
			}
			else if (NSWidth([myLeafView frame]) + SCROLLER_WIDTH > NSWidth(lastColumnFrame))
			{
				lastColumnFrame.size.width = NSWidth([myLeafView frame]) + SCROLLER_WIDTH;
			}
			
			[myColumnWidths setObject:[NSNumber numberWithFloat:NSWidth(lastColumnFrame)] forKey:[NSNumber numberWithUnsignedInt:[myColumns count]]];
			
			if (NSHeight([myLeafView frame]) > NSHeight(lastColumnFrame))
			{
				lastColumnFrame.size.height = NSHeight([myLeafView frame]);
			}
			lastColumnFrame.size.width -= SCROLLER_WIDTH;
			[myLeafView setFrame:lastColumnFrame];
			
			[scroller setDocumentView:myLeafView];
			[myLeafView scrollRectToVisible:NSMakeRect(0,NSMaxY(lastColumnFrame) - 1,1,1)];
			[self addSubview:scroller];
			[self updateScrollers];
			
			// scroll it to visible
            if (showColumn)
            {
                lastColumnFrame.size.width += SCROLLER_WIDTH;
                [self scrollRectToVisible:lastColumnFrame];
            }
		}
	}
}

- (void)removeLeafView
{
    if (myLeafView)
    {
        // there is a bug when setting the document view to nil the scroller still appears
        NSRect origRect = [myLeafView frame];
        NSRect docRect = [[myLeafView enclosingScrollView] documentVisibleRect];
        [myLeafView setFrame:NSMakeRect(0,0,NSWidth(docRect),NSHeight(docRect))];
        [[myLeafView enclosingScrollView] setDocumentView:nil];
        [[myLeafView enclosingScrollView] setNeedsDisplay:YES];
        [myLeafView setFrame:origRect];
        myLeafView = nil;
        [self setNeedsDisplay:YES];
    }
}

- (void)tableSelectedCell:(id)sender notifyTarget:(BOOL)flag scrollToVisible:(BOOL)showColumn
{
	/*
	NSString *lastSelectedPath = [[[mySelection lastObject] copy] autorelease];
	 */
	
	if (!myFlags.allowsMultipleSelection)
	{
		[mySelection removeAllObjects];
	}
	
	int column = [self columnWithTable:sender];
	int row = [sender selectedRow];
		
    if ((row < 0 || row == NSNotFound))
    {
        int rowSelectedBeforeThisEvent = [[myColumnSelectedCells objectForKey:[NSNumber numberWithInt:column]] intValue];
        id lastSelected = [myDataSource tableBrowser:self child:rowSelectedBeforeThisEvent ofItem:[myDataSource tableBrowser:self itemForPath:[self pathToColumn:column]]];
		id parentLastSelected = [self parentOfItem:lastSelected];
		NSString *parentPath = [myDataSource tableBrowser:self pathForItem:parentLastSelected];
		[mySelection addObject:parentPath];
		
        if ([myColumns count] - 1 != column)
        {
            // if we were a folder then we need to remove the column to the right
            if ([myDataSource tableBrowser:self isItemExpandable:lastSelected])
            {
                int i;
                for (i = column + 1; i < [myColumns count]; i++)
                {
                    NSTableView *table = [myColumns objectAtIndex:i];
                    NSScrollView *scroller = [table enclosingScrollView];
                    [table setDataSource:nil];
                    [scroller setDocumentView:nil];
                }
                NSRange r = NSMakeRange(column + 1, i - column - 1);
                [myColumns removeObjectsInRange:r];
            }
            [self removeLeafView];
            
            if (flag)
            {
                if (myTarget && myAction)
                {
                    [myTarget performSelector:myAction withObject:self];
                }
            }
        }
        else
        {
            // we are the last table so it is a leaf that was selected
            [self removeLeafView];
        }
        return;
    }
	
	NSString *path = [self pathToColumn:column];
	id containerItem = nil;
	id item = nil;
	BOOL isDirectory = NO;
	
    containerItem = [myDataSource tableBrowser:self itemForPath:path];
    item = [myDataSource tableBrowser:self child:row ofItem:containerItem];
    isDirectory = [myDataSource tableBrowser:self isItemExpandable:item];

	/*
	 Selection Changes handled
	 - selection is going to drill down into a directory
	 - selection is above the current directory
	 - selection is in the current directory
	 - multiple selection is maintained to the last column
	 */
	
	/* this code seems to be unused...
	id currentContainerItem = nil;
    id lastSelectedItem = [myDataSource tableBrowser:self itemForPath:lastSelectedPath];
    
	if (lastSelectedItem)
	{
		currentContainerItem = [self parentOfItem:lastSelectedItem];
	}
	else
	{
		currentContainerItem = [myDataSource tableBrowser:self itemForPath:path];
	}
	*/
	
	// remove the leaf view if it is visible
	[self removeLeafView];
	
	// remove columns greater than the currently selected one
	unsigned i;
	if ([myColumns count] > column + 1)
	{
		for (i = column + 1; i < [myColumns count]; i++)
		{
			NSTableView *table = [myColumns objectAtIndex:i];
			NSScrollView *scroller = [table enclosingScrollView];
			[table setDataSource:nil];
			[scroller setDocumentView:nil];
		}
		NSRange r = NSMakeRange(column + 1, i - column - 1);
		[myColumns removeObjectsInRange:r];
	}
    
    // leave 2 empty scrollers 
    if ([myScrollers count] > [myColumns count] + 2)
    {
        unsigned i = [myColumns count] + 2;
        
        for (; i < [myScrollers count]; i++)
        {
            [[myScrollers objectAtIndex:i] removeFromSuperviewWithoutNeedingDisplay];
        }
        i = [myColumns count] + 2;
        [myScrollers removeObjectsInRange:NSMakeRange(i, [myScrollers count] - i)];
    }
    
    [myColumnSelectedCells setObject:[NSNumber numberWithInt:row] forKey:[NSNumber numberWithInt:column]];
	
	if (isDirectory)
	{
		[myCurrentPath autorelease];
		myCurrentPath = [[myDataSource tableBrowser:self pathForItem:item] copy];
		
		// since we have gone into a new dir, any selections, even in a multi selection are now invalid
		[mySelection removeAllObjects];
		[mySelection addObject:[[myCurrentPath copy] autorelease]];
		
		// create a new column		
		id newColumn = [self createColumn:[myColumns count]];
		NSRect lastColumnFrame = [newColumn frame];
        [self addSubview:newColumn];
		[self updateScrollers];
		
        if (showColumn)
        {
            [self scrollRectToVisible:lastColumnFrame];
        }
	}
	else
	{
		// add to the current selection
        if (item)
        {
            [mySelection addObject:[myDataSource tableBrowser:self pathForItem:item]];
            [self leafInspectItem:item scrollToVisible:showColumn];
        }
	}

	if (flag)
	{
		if (myTarget && myAction)
		{
			[myTarget performSelector:myAction withObject:self];
		}
	}
}

- (void)delayedTableSelectedCell:(id)sender
{
	[self tableSelectedCell:sender notifyTarget:YES scrollToVisible:YES];
}

- (void)tableSelectedCell:(id)sender
{
	[self delayedTableSelectedCell:sender];
//	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(delayedTableSelectedCell:) object:nil];
//	[self performSelector:@selector(delayedTableSelectedCell:) withObject:sender afterDelay:0.1 inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
}

#pragma mark -
#pragma mark NSTableView Data Source

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	unsigned columnIndex = [self columnWithTable:aTableView];
	NSString *path = [self pathToColumn:columnIndex];
	
	id item = [myDataSource tableBrowser:self itemForPath:path];
	
	return [myDataSource tableBrowser:self numberOfChildrenOfItem:item];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	unsigned columnIndex = [self columnWithTable:aTableView];
	NSString *path = [self pathToColumn:columnIndex];
	id item = [myDataSource tableBrowser:self itemForPath:path];
		
	return [myDataSource tableBrowser:self child:rowIndex ofItem:item];
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	
}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id <NSDraggingInfo>)info row:(int)row dropOperation:(NSTableViewDropOperation)operation
{
	return NO;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)operation
{
	return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
	return NO;
}

#pragma mark -
#pragma mark NSTableView Delegate

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	if (myDelegateFlags.willDisplayCell)
	{
		// - (void)tableBrowser:(CKTableBasedBrowser *)browser willDisplayCell:(id)cell
		[myDelegate tableBrowser:self willDisplayCell:aCell];
	}
}

- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(int)rowIndex
{
	if (myFlags.isEnabled)
	{
		return YES;
	}
	
	return NO;
}

- (void)tableView:(NSTableView *)tableView didKeyPress:(NSString *)partialSearch
{
	// see if there is a cell that starts with the partial search string
	NSString *path = [self pathToColumn:[self columnWithTable:tableView]];
	id item = [myDataSource tableBrowser:self itemForPath:path];
	if (![item isDirectory])
	{
		item = [self parentOfItem:item];
	}
	NSCell *cell = [[[tableView tableColumns] objectAtIndex:0] dataCell];
	
	unsigned i, c = [myDataSource tableBrowser:self numberOfChildrenOfItem:item];
	id matchItem;
	
	for (i = 0; i < c; i++)
	{
		matchItem = [myDataSource tableBrowser:self child:i ofItem:item];
		[cell setObjectValue:matchItem];
		
		if ([[cell stringValue] hasPrefix:partialSearch])
		{
			// select the cell
			[tableView selectRow:i byExtendingSelection:NO];
			[tableView scrollRowToVisible:i];
			[self tableSelectedCell:tableView];
			break;
		}
	}
}

- (NSMenu *)tableView:(NSTableView *)tableView contextMenuForItem:(id)item
{
	if (myDelegateFlags.contextMenuWithItem)
	{
		return [myDelegate tableBrowser:self contextMenuWithItem:item];
	}
	
	return nil;
}

- (void)tableViewNavigateForward:(NSTableView *)tableView
{
	unsigned column = [self columnWithTable:tableView];
	NSString *path = [self pathToColumn:column + 1];
	id item = [myDataSource tableBrowser:self itemForPath:path];
	
	if ([item isDirectory])
	{
		if (column < [myColumns count] - 1)
		{
			NSTableView *next = [myColumns objectAtIndex:column + 1];
			
			if ([myDataSource tableBrowser:self numberOfChildrenOfItem:item] > 0)
			{
				[[self window] makeFirstResponder:next];
				[next selectRow:0 byExtendingSelection:NO];
				if ([next target] && [next action])
				{
					[[next target] performSelector:[next action] withObject:next];
				}
			}
		}
	}
}

- (void)tableViewNavigateBackward:(NSTableView *)tableView
{
	unsigned column = [self columnWithTable:tableView];
	if (column > 0)
	{
		NSTableView *previous = [myColumns objectAtIndex:column - 1];
		[[self window] makeFirstResponder:previous];
		
		if ([previous target] && [previous action])
		{
			[[previous target] performSelector:[previous action] withObject:previous];
		}
		
		[self scrollRectToVisible:[[previous enclosingScrollView] frame]];
	}
}

#pragma mark -
#pragma mark Resizer Delegate

- (void)resizer:(CKResizingButton *)resizer ofScrollView:(CKTableBrowserScrollView *)scrollView  movedBy:(float)xDelta affectsAllColumns:(BOOL)flag;
{
	unsigned column = [myScrollers indexOfObject:scrollView];
	NSScrollView *scroller = [myScrollers objectAtIndex:column];
	
	NSLog(@"%d %f", column, xDelta);
	[myColumnWidths setObject:[NSNumber numberWithFloat:NSWidth([scroller frame]) + xDelta] forKey:[NSNumber numberWithUnsignedInt:column]];
	
	if (flag)
	{
		// remove all custom sizes
		[myColumnWidths removeAllObjects];
		// set new default
		myDefaultColumnWidth = NSWidth([scroller frame]) + xDelta;
	}
	
	NSRect frame = [scroller frame];
	frame.size.width += xDelta;
	// apply constraints
	if (NSWidth(frame) < myMinColumnWidth)
	{
		frame.size.width = myMinColumnWidth;
	}
	if (myLeafView && [scroller documentView] == myLeafView)
	{
		if (NSWidth(frame) < NSWidth([myLeafView frame]) + SCROLLER_WIDTH)
		{
			frame.size.width = NSWidth([myLeafView frame]) + SCROLLER_WIDTH;
		}
	}
	if (myMaxColumnWidth > 0 && NSWidth(frame) > myMaxColumnWidth)
	{
		frame.size.width = myMaxColumnWidth;
	}
	[scroller setFrame:frame];
	NSRect lastFrame = frame;
	
	// adjust views to the right
	for ( ++column; column < [myScrollers count]; column++)
	{
		NSScrollView *scroller = [myScrollers objectAtIndex:column];
		frame = [scroller frame];
		frame.origin.x = NSMaxX(lastFrame) + 1;
		
		if (flag)
		{
			frame.size.width = myDefaultColumnWidth;
			
			if ([scroller documentView] == myLeafView)
			{
				if (NSWidth(frame) < NSWidth([myLeafView frame]) + SCROLLER_WIDTH)
				{
					frame.size.width = NSWidth([myLeafView frame]) + SCROLLER_WIDTH;
				}
			}
		}
		
		[scroller setFrame:frame];
		lastFrame = frame;
	}
	
	[self setNeedsDisplay:YES];
	[self updateScrollers];
}

@end

static NSImage *sResizeImage = nil;

@interface CKResizingButton : NSView
{
	id myDelegate;
}

- (void)setDelegate:(id)delegate;

@end

@interface NSObject (CKResizingButtonDelegate)

- (void)resizer:(CKResizingButton *)resizer ofScrollView:(CKTableBrowserScrollView *)scrollView  movedBy:(float)xDelta affectsAllColumns:(BOOL)flag;

@end

@implementation CKResizingButton

- (id)initWithFrame:(NSRect)frame
{
	if ((self != [super initWithFrame:frame]))
	{
		[self release];
		return nil;
	}
	
	if (!sResizeImage)
	{
		NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"browser_resizer" ofType:@"tiff"];
		sResizeImage = [[NSImage alloc] initWithContentsOfFile:path];
	}
	
	return self;
}

- (void)setDelegate:(id)delegate
{
	if (![delegate respondsToSelector:@selector(resizer:ofScrollView:movedBy:affectsAllColumns:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"delegate does not respond to resizer:movedBy:" userInfo:nil];
	}
	myDelegate = delegate;
}

- (void)drawRect:(NSRect)rect
{
	[sResizeImage drawInRect:rect
					fromRect:NSZeroRect
				   operation:NSCompositeSourceOver
					fraction:1.0];
}

- (void)mouseDown:(NSEvent *)theEvent
{
	NSPoint point = [theEvent locationInWindow]; 
	BOOL allCols = ((GetCurrentKeyModifiers() & (optionKey | rightOptionKey)) != 0) ? YES : NO;
	float lastDelta = 0;
	
	while (1)
	{
		theEvent = [[self window] nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)];
		NSPoint thisPoint = [theEvent locationInWindow];
		float thisDelta = thisPoint.x - point.x;
		
		// need to see if there was a direction change then we need to come back through the control to go the other way
		if ((thisDelta > 0 && lastDelta < 0) ||
			(thisDelta < 0 && lastDelta > 0))
		{
			
		}
		
		[myDelegate resizer:self ofScrollView:(CKTableBrowserScrollView *)[self superview] movedBy:thisDelta affectsAllColumns:allCols];
			
		point = thisPoint;
		lastDelta = thisDelta;
		
		if ([theEvent type] == NSLeftMouseUp) {
            break;
        }
	}
}

@end

#define RESIZER_KNOB_SIZE 15.0

@implementation CKTableBrowserScrollView

- (id)initWithFrame:(NSRect)frame
{
	if ((self != [super initWithFrame:frame]))
	{
		[self release];
		return nil;
	}
	
	myResizer = [[CKResizingButton alloc] initWithFrame:NSMakeRect(0, 0, RESIZER_KNOB_SIZE, RESIZER_KNOB_SIZE)];
	
	return self;
}

- (void)dealloc
{
	[myResizer release];
	[super dealloc];
}

- (CKResizingButton *)resizer
{
	return myResizer;
}

- (void)setCanResize:(BOOL)flag
{
	myFlags.canResize = flag;
	[self setNeedsDisplay:YES];
}

- (BOOL)canResize
{
	return myFlags.canResize;
}

- (void)drawRect:(NSRect)rect
{
	[super drawRect:rect];
	[myResizer setNeedsDisplay:YES];
}

- (void)tile
{
	[super tile];
	
	if ([self documentView])
	{
		NSScroller *vert = [self verticalScroller];
		NSRect frame = [vert frame];
		frame.size.height -= RESIZER_KNOB_SIZE;
		
		[vert setFrame:frame];
		
		NSRect resizerRect = [myResizer frame];
		resizerRect.origin.x = NSMinX(frame);
		resizerRect.origin.y = NSMaxY(frame) ;
		resizerRect.size.width = RESIZER_KNOB_SIZE;
		resizerRect.size.height = RESIZER_KNOB_SIZE;
		
		[myResizer setFrame:resizerRect];
		[self addSubview:myResizer];
	}
	else
	{
		[myResizer removeFromSuperview];
	}
}

- (void)scrollWheel:(NSEvent *)theEvent
{
	BOOL isHorizontal = ((GetCurrentKeyModifiers() & (shiftKey | rightShiftKey)) != 0) ? YES : NO;
	
	if (isHorizontal)
	{
		// us -> CKTableBasedBrowser -> scrollview
		[[[self superview] enclosingScrollView] scrollWheel:theEvent];
	}
	else
	{
		[super scrollWheel:theEvent];
	}
}

- (void)reflectScrolledClipView:(NSClipView *)aClipView
{
    [aClipView setCopiesOnScroll:NO];
    [super reflectScrolledClipView:aClipView];
}

@end

@implementation CKBrowserTableView

#define KEYPRESS_DELAY 0.25
#define ARROW_NAVIGATION_DELAY 0.25

- (void)dealloc
{
	[myQuickSearchString release];
	[super dealloc];
}

- (void)searchConcatenationEnded
{
	[myQuickSearchString deleteCharactersInRange:NSMakeRange(0, [myQuickSearchString length])];
}

- (void)delayedSelectionChange
{
	if ([self target] && [self action])
	{
		[[self target] performSelector:[self action] withObject:self];
	}
}

- (void)keyDown:(NSEvent *)theEvent
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchConcatenationEnded) object:nil];
	
	if ([[theEvent characters] characterAtIndex:0] == NSDeleteFunctionKey ||
		[[theEvent characters] characterAtIndex:0] == NSDeleteCharFunctionKey ||
		[[theEvent characters] characterAtIndex:0] == NSDeleteLineFunctionKey)
	{
		[self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
	}
	else if ([[theEvent characters] characterAtIndex:0] == NSLeftArrowFunctionKey)
	{
		if ([[self delegate] respondsToSelector:@selector(tableViewNavigateBackward:)])
		{
			[[self delegate] tableViewNavigateBackward:self];
		}
	}
	else if ([[theEvent characters] characterAtIndex:0] == NSRightArrowFunctionKey)
	{
		if ([[self delegate] respondsToSelector:@selector(tableViewNavigateForward:)])
		{
			[[self delegate] tableViewNavigateForward:self];
		}
	}
	// we are using a delayed selector approach here so if someone just holds their finger down on the arrows, it won't go and fetch every single directory
	else if ([[theEvent characters] characterAtIndex:0] == NSUpArrowFunctionKey)
	{
		if ([self selectedRow] > 0)
		{
			[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(delayedSelectionChange) object:nil];
			
			[self selectRow:[self selectedRow] - 1 byExtendingSelection:NO];
			[self scrollRowToVisible:[self selectedRow] - 1];
			
			//[self delayedSelectionChange];
			[self performSelector:@selector(delayedSelectionChange) withObject:nil afterDelay:ARROW_NAVIGATION_DELAY inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
		}
	}
	else if ([[theEvent characters] characterAtIndex:0] == NSDownArrowFunctionKey)
	{
		if ([self selectedRow] < [[self dataSource] numberOfRowsInTableView:self] - 1)
		{
			[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(delayedSelectionChange) object:nil];
			
			[self selectRow:[self selectedRow] + 1 byExtendingSelection:NO];
			[self scrollRowToVisible:[self selectedRow] + 1];
			
			//[self delayedSelectionChange];
			[self performSelector:@selector(delayedSelectionChange) withObject:nil afterDelay:ARROW_NAVIGATION_DELAY inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
		}
	}
	else
	{
		if (!myQuickSearchString)
		{
			myQuickSearchString = [[NSMutableString alloc] initWithString:@""];
		}
		[myQuickSearchString appendString:[theEvent characters]];
		// send the string as it gets built up
		if ([[self delegate] respondsToSelector:@selector(tableView:didKeyPress:)])
		{
			[[self delegate] tableView:self didKeyPress:myQuickSearchString];
		}
		[self performSelector:@selector(searchConcatenationEnded) withObject:nil afterDelay:KEYPRESS_DELAY inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
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
	if ([[self delegate] respondsToSelector:@selector(tableView:contextMenuForItem:)])
	{
		int row = [self rowAtPoint:[self convertPoint:[theEvent locationInWindow] fromView:nil]];
		id item = nil;
		
		if (row > 0)
		{
			item = [[self dataSource] tableView:self objectValueForTableColumn:[[self tableColumns] objectAtIndex:0] row:row];
		}
		return [[self delegate] tableView:self contextMenuForItem:item];
	}
	return nil;
}

- (void)scrollWheel:(NSEvent *)theEvent
{
	BOOL isHorizontal = ((GetCurrentKeyModifiers() & (shiftKey | rightShiftKey)) != 0) ? YES : NO;
	
	if (isHorizontal)
	{
		// us -> scrollview -> CKTableBasedBrowser -> scrollview
		[[[[self enclosingScrollView] superview] enclosingScrollView] scrollWheel:theEvent];
	}
	else
	{
		[super scrollWheel:theEvent];
	}
}

@end

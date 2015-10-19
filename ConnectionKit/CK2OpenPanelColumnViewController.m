//
//  CK2OpenPanelBrowserController.m
//  ConnectionKit
//
//  Created by Paul Kim on 12/29/12.
//  Copyright (c) 2012 Paul Kim. All rights reserved.
//
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this list
// of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice, this
// list of conditions and the following disclaimer in the documentation and/or other
// materials provided with the distribution.
//
// Neither the name of Karelia Software nor the names of its contributors may be used to
// endorse or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
// SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
// TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
// WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "CK2OpenPanelColumnViewController.h"
#import "CK2OpenPanelController.h"
#import "CK2FileCell.h"
#import "CK2BrowserPreviewController.h"
#import "NSURL+CK2OpenPanel.h"
#import "NSImage+CK2OpenPanel.h"

@implementation CK2OpenPanelColumnViewController

@synthesize rootURL = _rootURL;

- (void)dealloc
{
    [_previewController release];
    [_rootURL release];
    [super dealloc];
}

- (void)awakeFromNib
{
    [_browser setCellClass:[CK2FileCell class]];
    [_browser setDoubleAction:@selector(itemDoubleClicked:)];
}

- (BOOL)allowsMutipleSelection
{
    return [_browser allowsMultipleSelection];
}

- (void)setAllowsMutipleSelection:(BOOL)allowsMutipleSelection
{
    [_browser setAllowsMultipleSelection:allowsMutipleSelection];
}

- (BOOL)hasFixedRoot
{
    return YES;
}

// Gets the index path of the directory url and the indexset of the URLs under it. "urls" is passed by reference as
// this method can change the list if only a subset can be selected (like when switching from the outline view to this
// one). Will return YES if the list of urls has changed.
- (BOOL)getIndexPath:(NSIndexPath **)indexPath indexSet:(NSIndexSet **)indexSet ofURLs:(NSArray **)urls inDirectory:(NSURL *)directoryURL
{
    CK2OpenPanelController      *controller;
    NSURL                       *root, *tempURL;
    NSUInteger                  count;
    __block NSUInteger          *indexes, indexCount;
    NSMutableIndexSet           *resultIndexes;
    NSMutableArray              *newURLs;
    
    if (![_browser isLoaded])
    {
        [_browser loadColumnZero];
    }
    
    controller = [self controller];
    if (directoryURL == nil)
    {
        if ([*urls count] > 0)
        {
            directoryURL = [*urls objectAtIndex:0];
        }
        else
        {
            return NO;
        }
    }
    if (![controller URLCanHazChildren:directoryURL])
    {
        directoryURL = [directoryURL ck2_parentURL];
    }
    
    root = [self rootURL];

    if (indexPath != NULL)
    {
        NSMutableArray  *ancestorURLs;
        NSURL           *parentURL;
        NSArray         *children;
        NSUInteger      row;
        
        ancestorURLs = [NSMutableArray array];
        tempURL = directoryURL;
        while (![tempURL isEqual:root])
        {
            if (tempURL == nil)
            {
                NSLog(@"Ancestor URL not found going up from %@ to %@", directoryURL, root);
                *urls = @[];
                return YES;
            }
            [ancestorURLs insertObject:tempURL atIndex:0];
            tempURL = [tempURL ck2_parentURL];
        }
        [ancestorURLs insertObject:root atIndex:0];
        
        count = [ancestorURLs count];
        
        indexes = NULL;
        if (count > 0)
        {
            indexes = (NSUInteger *)malloc(sizeof(NSUInteger) * count);
            
            indexCount = 0;
            
            parentURL = nil;
            
            for (tempURL in ancestorURLs)
            {
                if (parentURL != nil)
                {
                    children = [controller childrenForURL:parentURL];
                    
                    row = [children indexOfObject:tempURL];
                    
                    if (row == NSNotFound)
                    {
                        NSLog(@"Can't find entry in browser %@", tempURL);
                        break;
                    }
                    else
                    {
                        indexes[indexCount++] = row;
                    }
                }
                parentURL = tempURL;
            }
            
            if (indexCount > 0)
            {
                *indexPath = [NSIndexPath indexPathWithIndexes:indexes length:indexCount];
            }
            
            free(indexes);
        }
    }
    
    resultIndexes = [NSMutableIndexSet indexSet];
    newURLs = [NSMutableArray array];
    
    for (tempURL in *urls)
    {
        NSArray     *children;
        NSUInteger  row;
        
        children = [controller childrenForURL:directoryURL];
        row = [children indexOfObject:tempURL];
        
        if (row == NSNotFound)
        {
            tempURL = [tempURL ck2_URLByDeletingTrailingSlash];
            
            row = [children indexOfObject:tempURL];
        }
        
        if (row != NSNotFound)
        {
            [resultIndexes addIndex:row];
            [newURLs addObject:tempURL];
        }
    }
    
    if (indexSet != NULL)
    {
        *indexSet = resultIndexes;
    }
    
    if ([newURLs count] != [*urls count])
    {
        *urls = newURLs;
        return YES;
    }
    return NO;
}

- (void)reload
{
    [_browser loadColumnZero];
}

- (void)update
{
    CK2OpenPanelController      *controller;
    NSArray                     *urls;
    NSIndexPath                 *indexPath;
    NSIndexSet                  *indexSet;
    
    controller = [self controller];
    urls = [controller URLs];
    
    indexPath = nil;
    indexSet = nil;
    if ([self getIndexPath:&indexPath indexSet:&indexSet ofURLs:&urls inDirectory:[controller directoryURL]])
    {
        [controller setURLs:urls updateDirectory:NO sender:self];
    }
    
    if (indexPath != nil)
    {
        NSUInteger      column;
        
        [_browser setSelectionIndexPath:indexPath];
        column = [indexPath length];
        
        if (column > 0)
        {
            [_browser selectRowIndexes:indexSet inColumn:column];
            [_browser scrollColumnToVisible:column];
            [_browser scrollRowToVisible:[indexSet lastIndex] inColumn:column];
            [_browser scrollRowToVisible:[indexSet firstIndex] inColumn:column];
        }
    }
    else
    {
        [_browser selectRowIndexes:[NSIndexSet indexSet] inColumn:0];
    }
}

- (void)urlDidLoad:(NSURL *)url
{
    NSURL       *viewRoot;
    
    viewRoot = [self rootURL];
    
    // Only care about the url if it's visible (under the current view root).
    if ([viewRoot ck2_isAncestorOfURL:url])
    {
        NSIndexPath         *indexPath;
        NSArray             *urls;
        
        indexPath = nil;
        urls = @[ url ];
        [self getIndexPath:&indexPath indexSet:NULL ofURLs:&urls inDirectory:nil];
        
        if (indexPath != nil)
        {
            [_browser reloadColumn:[indexPath length]];
        }
        else
        {
            [_browser loadColumnZero];
        }
        [_browser setNeedsDisplay:YES];
    }
}

- (NSArray *)selectedURLs
{
    NSIndexPath         *indexPath;
    NSIndexSet          *indexSet;
    NSInteger           column;
    NSMutableArray      *urls;
    
    urls = [NSMutableArray array];
    indexPath = [_browser selectionIndexPath];
    
    column = [indexPath length] - 1;
    if (column >= 0)
    {
        indexSet = [_browser selectedRowIndexesInColumn:column];

        [indexSet enumerateIndexesUsingBlock:
         ^(NSUInteger idx, BOOL *stop)
        {
            NSURL       *url;
            
            url = [_browser itemAtRow:idx inColumn:column];
            
            if (url != nil)
            {
                [urls addObject:url];
            }
        }];
    }
    return urls;
}

- (IBAction)itemDoubleClicked:(id)sender
{
    [self goToSelectedItem:sender];
}

- (IBAction)goToSelectedItem:(id)sender
{
    NSArray                 *urls;
    BOOL                    isValid;
    CK2OpenPanelController  *controller;
    
    controller = [self controller];
    urls = [self selectedURLs];
    isValid = YES;
    for (NSURL *url in urls)
    {
        if (![controller isURLValid:url])
        {
            isValid = NO;
            break;
        }
    }
    
    if (isValid)
    {
        [controller ok:self];
    }
}


#pragma mark NSBrowserDelegate methods

- (id)rootItemForBrowser:(NSBrowser *)browser
{
    return [self rootURL];
}

- (id)browser:(NSBrowser *)browser child:(NSInteger)index ofItem:(id)item
{
    NSArray     *children;
    
    children = [[self controller] childrenForURL:item];
    
    if (index >= [children count])
    {
        NSLog(@"Got out of range index for some reason");
    }
    return [children objectAtIndex:index];
}

- (BOOL)browser:(NSBrowser *)browser isLeafItem:(id)item
{
    return ![[self controller] URLCanHazChildren:item];
}

- (NSInteger)browser:(NSBrowser *)browser numberOfChildrenOfItem:(id)item
{
    return [[[self controller] childrenForURL:item] count];
}

- (id)browser:(NSBrowser *)browser objectValueForItem:(id)item
{
    return [item ck2_displayName];
}

- (BOOL)browser:(NSBrowser *)browser shouldEditItem:(id)item
{
    return NO;
}

- (void)browser:(NSBrowser *)browser willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column
{
    NSURL                       *url;
    CK2OpenPanelController      *controller;
    
    controller = [self controller];
    url = [browser itemAtRow:row inColumn:column];
    
    [cell setImage:[url ck2_icon]];
    
    if ([controller isURLValid:url] || [controller URLCanHazChildren:url])
    {
        [cell setTextColor:[NSColor controlTextColor]];
    }
    else
    {
        [cell setTextColor:[NSColor disabledControlTextColor]];
    }

    [cell setTextOnly:[url ck2_isPlaceholder]];
}

- (NSIndexSet *)browser:(NSBrowser *)browser selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes inColumn:(NSInteger)column
{
    NSMutableIndexSet       *indexSet;
    CK2OpenPanelController  *controller;
    
    controller = [self controller];
    indexSet = [NSMutableIndexSet indexSet];
    
    [proposedSelectionIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop)
     {
         NSURL                   *url;
         
         url = [browser itemAtRow:idx inColumn:column];
         
         if ([controller isURLValid:url] || [controller URLCanHazChildren:url])
         {
             [indexSet addIndex:idx];
         }
     }];
    
    // If we are not selecting any new items, returning an empty indexset will nuke the original selection. We
    // rectify that here.
    if ([indexSet count] == 0)
    {
        [indexSet addIndexes:[browser selectedRowIndexesInColumn:column]];
    }
    
    return indexSet;
}

- (BOOL)browser:(NSBrowser *)browser canDragRowsWithIndexes:(NSIndexSet *)rowIndexes inColumn:(NSInteger)column withEvent:(NSEvent *)event
{
    return NO;
}

- (BOOL)browser:(NSBrowser *)browser writeRowsWithIndexes:(NSIndexSet *)rowIndexes inColumn:(NSInteger)column toPasteboard:(NSPasteboard *)pasteboard
{
    return NO;
}

- (NSViewController *)browser:(NSBrowser *)browser previewViewControllerForLeafItem:(id)item
{
    if (_previewController == nil)
    {
        _previewController = [[CK2BrowserPreviewController alloc] init];
    }
    return _previewController;
}

@end

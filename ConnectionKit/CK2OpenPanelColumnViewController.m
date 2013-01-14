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
#import "NSURL+CK2OpenPanel.h"

@interface CK2OpenPanelColumnViewController ()

@end

@implementation CK2OpenPanelColumnViewController


- (void)awakeFromNib
{
    [_browser setCellClass:[CK2FileCell class]];
    [_browser setDoubleAction:@selector(itemDoubleClicked:)];
}

- (BOOL)hasFixedRoot
{
    return YES;
}

- (NSIndexPath *)indexPathOfURL:(NSURL *)url
{
    NSURL               *tempURL;
    NSArray             *targetComponents, *children;
    NSUInteger          i, count, row, *indexes, indexCount;
    NSIndexPath         *indexPath;
    
    if (![_browser isLoaded])
    {
        [_browser loadColumnZero];
    }
    indexPath = nil;
    targetComponents = [url pathComponents];
    count = [targetComponents count];
    
    indexes = NULL;
    if (count > 1)
    {
        indexes = (NSUInteger *)malloc(sizeof(NSUInteger) * (count - 1));
    }
    indexCount = 0;
    
    tempURL = [url root];
    
    for (i = 1; i < count; i++)
    {
        children = [[self controller] childrenForURL:tempURL];
        tempURL = [tempURL URLByAppendingPathComponent:[targetComponents objectAtIndex:i] isDirectory:YES];
        
        row = [children indexOfObject:tempURL];
        
        if (row == NSNotFound)
        {
            if (i == count - 1)
            {
                NSString    *path;
                
                // Try again but without the trailing slash
                path = [tempURL path];
                if ([path hasSuffix:@"/"])
                {
                    path = [path substringToIndex:[path length] - 1];
                }
                // Quite the rigamarole just to get an URL without the trailing slash
                tempURL = [[NSURL URLWithString:[path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] relativeToURL:[url root]] absoluteURL];
                    
                row = [children indexOfObject:tempURL];
            }
        }
        
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
    
    if (indexCount > 0)
    {
        indexPath = [NSIndexPath indexPathWithIndexes:indexes length:indexCount];
    }
    
    if (indexes != NULL)
    {
        free(indexes);
    }
    
    return indexPath;
}

- (void)reload
{
    [_browser loadColumnZero];
}

- (void)update
{
    NSIndexPath     *indexPath;
    NSURL           *url;
    
    url = [[self controller] URL];
    indexPath = [self indexPathOfURL:url];
    
    if (indexPath != nil)
    {
        NSUInteger      length;
        
        [_browser setSelectionIndexPath:indexPath];
        length = [indexPath length];
        
        if (length > 0)
        {
            NSUInteger  i;

            i = length - 1;
            if ([url canHazChildren])
            {
                [_browser scrollColumnToVisible:length];
            }
            else
            {
                [_browser scrollColumnToVisible:i];
            }

            [_browser scrollRowToVisible:[indexPath indexAtPosition:i] inColumn:i];
        }
    }
    else
    {
        [_browser selectRowIndexes:nil inColumn:0];
    }
}

- (void)urlDidLoad:(NSURL *)url
{
    NSIndexPath         *indexPath;
    
    indexPath = [self indexPathOfURL:url];
    
    if (indexPath != nil)
    {
/*        NSUInteger          lastColIndex;
        
        lastColIndex = [indexPath length] - 1;
        [_browser reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:[indexPath indexAtPosition:lastColIndex]] inColumn:lastColIndex];*/
        [_browser reloadColumn:[indexPath length]];
    }
    else
    {
        [_browser loadColumnZero];
    }
    [_browser setNeedsDisplay:YES];
}

- (IBAction)itemSelected:(id)sender
{
    NSURL               *url;
    NSInteger           column, row;
    NSIndexPath         *indexPath;
    
    indexPath = [_browser selectionIndexPath];
    column = [indexPath length] - 1;
    if (column >= 0)
    {
        row = [indexPath indexAtPosition:column];
        
        if (row != NSNotFound)
        {
            url = [_browser itemAtRow:row inColumn:column];
            
            [[self controller] setURL:url updateDirectory:YES sender:self];
        }
        else
        {
            NSLog(@"WHAT THE?");
        }
    }
}

- (IBAction)itemDoubleClicked:(id)sender
{
    NSURL               *url;
    NSInteger           column, row;
    NSIndexPath         *indexPath;
    
    indexPath = [_browser selectionIndexPath];
    column = [indexPath length] - 1;
    if (column > 0)
    {
        row = [indexPath indexAtPosition:column];
        
        if (row != NSNotFound)
        {
            url = [_browser itemAtRow:row inColumn:column];
            
            if ([_controller isURLValid:url])
            {
                [_controller ok:self];
            }
        }
    }
}


#pragma mark NSBrowserDelegate methods

- (id)rootItemForBrowser:(NSBrowser *)browser
{
    return [[[_controller openPanel] directoryURL] root];
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
    return ![item canHazChildren];
}

- (NSInteger)browser:(NSBrowser *)browser numberOfChildrenOfItem:(id)item
{
    return [[_controller childrenForURL:item] count];
}

- (id)browser:(NSBrowser *)browser objectValueForItem:(id)item
{
    return [item displayName];
}

- (BOOL)browser:(NSBrowser *)browser shouldEditItem:(id)item
{
    return NO;
}

- (void)browser:(NSBrowser *)browser willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column
{
    NSURL       *url;
    
    url = [browser itemAtRow:row inColumn:column];
    [cell setImage:[url icon]];
    
    [cell setStringValue:[url displayName]];
    
    if ([_controller isURLValid:url])
    {
        [cell setTextColor:[NSColor controlTextColor]];
    }
    else
    {
        [cell setTextColor:[NSColor disabledControlTextColor]];
    }
    [cell setBackgroundColor:[NSColor controlBackgroundColor]];
    
    [cell setControlView:browser];
}

- (NSIndexSet *)browser:(NSBrowser *)browser selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes inColumn:(NSInteger)column
{
    NSMutableIndexSet       *indexSet;
    
    indexSet = [NSMutableIndexSet indexSet];
    
    [proposedSelectionIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop)
     {
         NSURL                   *url;
         
         url = [browser itemAtRow:idx inColumn:column];
         
         if ([_controller isURLValid:url])
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

@end

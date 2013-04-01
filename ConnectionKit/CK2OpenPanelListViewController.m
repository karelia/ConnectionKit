//
//  CK2OpenPanelListController.m
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

#import "CK2OpenPanelListViewController.h"
#import "CK2OpenPanelController.h"
#import "NSURL+CK2OpenPanel.h"
#import "NSImage+CK2OpenPanel.h"
#import "CK2FileCell.h"

@interface CK2OpenPanelListViewController ()

@end

@implementation CK2OpenPanelListViewController

- (void)awakeFromNib
{
    [_outlineView setDoubleAction:@selector(itemDoubleClicked:)];
    [_outlineView setTarget:self];
}

- (BOOL)allowsMutipleSelection
{
    return [_outlineView allowsMultipleSelection];
}

- (void)setAllowsMutipleSelection:(BOOL)allowsMutipleSelection
{
    [_outlineView setAllowsMultipleSelection:allowsMutipleSelection];
}

- (void)reload
{
    [_outlineView reloadData];
}

- (void)update
{
    NSArray                 *urls;
    NSURL                   *url;
    CK2OpenPanelController  *controller;
    NSMutableIndexSet       *indexSet;
    NSRect                  rect;
    
    controller = [self controller];
    
    [_outlineView reloadData];
    
    urls = [controller URLs];
    indexSet = [NSMutableIndexSet indexSet];
    rect = NSZeroRect;
  
    for (url in urls)
    {
        if (![url isEqual:[[controller openPanel] directoryURL]])
        {
            NSInteger       row;
            
            row = [_outlineView rowForItem:url];
            if (row > 0)
            {
                [indexSet addIndex:row];
                rect = NSUnionRect(rect, [_outlineView rectOfRow:row]);
            }
        }
    }
    [_outlineView selectRowIndexes:indexSet byExtendingSelection:NO];
    [_outlineView scrollRectToVisible:rect];
}

- (void)urlDidLoad:(NSURL *)url
{
    if ([url isEqual:[[[self controller] openPanel] directoryURL]])
    {
        [_outlineView reloadData];
    }
    else
    {
        [_outlineView reloadItem:url reloadChildren:YES];
    }
}

- (NSArray *)selectedURLs
{
    NSIndexSet      *indexSet;
    NSMutableArray  *urls;
    
    indexSet = [_outlineView selectedRowIndexes];
    
    urls = [NSMutableArray array];
    
    [indexSet enumerateIndexesUsingBlock:
     ^(NSUInteger idx, BOOL *stop)
     {
         NSURL       *url;
         
         url = [_outlineView itemAtRow:idx];
         if (url != nil)
         {
             [urls addObject:url];
         }
     }];
    
    return urls;
}

- (IBAction)itemDoubleClicked:(id)sender
{
    [self goToSelectedItem:sender];
}

- (IBAction)goToSelectedItem:(id)sender
{
    CK2OpenPanelController      *controller;
    NSArray                     *urls;
    
    controller = [self controller];
    urls = [self selectedURLs];
    
    if ([urls count] == 1)
    {
        NSURL                   *url;
        
        url = [urls objectAtIndex:0];
        if ([controller URLCanHazChildren:url])
        {
            if (![url isEqual:[[controller openPanel] directoryURL]])
            {
                [controller addToHistory];
                [controller setURLs:urls updateDirectory:YES sender:self];
            }
        }
        else
        {
            if ([controller isURLValid:url])
            {
                [controller ok:self];
            }
        }
    }
}

#define HISTORY_LIST_EXPANDED_ITEMS_KEY     @"listViewExpandedItems"

- (void)saveViewHistoryState:(NSMutableDictionary *)dict
{
    NSUInteger          count, i;
    NSMutableArray      *items;
    id                  item;
    
    count = [_outlineView numberOfRows];
    items = [NSMutableArray array];
    
    for (i = 0; i < count; i++)
    {
        item = [_outlineView itemAtRow:i];
        
        if ([_outlineView isItemExpanded:item])
        {
            [items addObject:item];
        }
    }
    
    [dict setObject:items forKey:HISTORY_LIST_EXPANDED_ITEMS_KEY];
}

- (void)restoreViewHistoryState:(NSDictionary *)dict
{
    NSArray     *items;
    
    items = [dict objectForKey:HISTORY_LIST_EXPANDED_ITEMS_KEY];
    
    for (id item in items)
    {
        [_outlineView expandItem:item];
    }    
}

#pragma mark NSOutlineViewDataSource methods

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    CK2OpenPanelController  *controller;
    
    controller = [self controller];
    if (item == nil)
    {
        item = [[controller openPanel] directoryURL];
    }
    return [[controller childrenForURL:item] objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    CK2OpenPanelController  *controller;
    
    controller = [self controller];
    if (item == nil)
    {
        item = [[controller openPanel] directoryURL];
    }
    return [controller URLCanHazChildren:item];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
        CK2OpenPanelController  *controller;
    
    controller = [self controller];
    
    if (item == nil)
    {
        item = [[controller openPanel] directoryURL];
    }
    return [[controller childrenForURL:item] count];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    id              identifier;
    
    if (item == nil)
    {
        item = [[[self controller] openPanel] directoryURL];
    }
    
    identifier = [tableColumn identifier];
    if ([identifier isEqual:@"Name"])
    {
        return [item ck2_displayName];
    }
    else if ([identifier isEqual:@"Date Modified"])
    {
        return [item ck2_dateModified];
    }
    else if ([identifier isEqual:@"Size"])
    {
        id      value;
        
        value = [(NSURL *)item ck2_size];
        
        if (value == nil)
        {
            return @"--";
        }
        return value;
    }
    else if ([identifier isEqual:@"Kind"])
    {
        return [(NSURL *)item ck2_kind];
    }
    return nil;
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    CK2OpenPanelController  *controller;
    
    controller = [self controller];
    if ([[tableColumn identifier] isEqual:@"Name"])
    {
        [cell setImage:[item ck2_icon]];
        [cell setTextOnly:[item ck2_isPlaceholder]];
    }
    
    if ([controller isURLValid:item] || [controller URLCanHazChildren:item])
    {
        [cell setTextColor:[NSColor controlTextColor]];
    }
    else
    {
        [cell setTextColor:[NSColor disabledControlTextColor]];
    }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
    CK2OpenPanelController  *controller;
    
    controller = [self controller];
    return [controller isURLValid:item] || [controller URLCanHazChildren:item];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id < NSDraggingInfo >)info item:(id)item childIndex:(NSInteger)index
{
    return NO;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id < NSDraggingInfo >)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
    return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard
{
    return NO;
}

- (id)outlineView:(NSOutlineView *)outlineView itemForPersistentObject:(id)object
{
    //PENDING:
    return [NSURL URLWithString:object];
}

- (id)outlineView:(NSOutlineView *)outlineView persistentObjectForItem:(id)item
{
    //PENDING:
    return [item description];
}



@end

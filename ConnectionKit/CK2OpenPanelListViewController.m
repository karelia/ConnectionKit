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

@interface CK2OpenPanelListViewController ()

@end

@implementation CK2OpenPanelListViewController

- (void)awakeFromNib
{
    [_outlineView setDoubleAction:@selector(itemDoubleClicked:)];
    [_outlineView setTarget:self];
}

- (void)reload
{
    [_outlineView reloadData];
}

- (void)update
{
    NSURL                   *url;
    CK2OpenPanelController  *controller;
    
    controller = [self controller];
    
    [_outlineView reloadData];
    
    url = [[self controller] URL];
    
    if (![url isEqual:[[controller openPanel] directoryURL]])
    {
        NSInteger       row;
        
        row = [_outlineView rowForItem:[controller URL]];
        if (row > 0)
        {
            [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
            [_outlineView scrollRowToVisible:row];
        }
        else
        {
            NSLog(@"NO ROW FOR ITEM: %@", [controller URL]);
        }
    }
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

- (IBAction)itemSelected:(id)sender
{
    NSInteger       row;
    
    row = [_outlineView clickedRow];
    
    if (row != -1)
    {
        NSURL       *url;
        
        url = [_outlineView itemAtRow:row];
        [[self controller] setURL:url updateDirectory:NO sender:self];
    }
    else
    {
        NSLog(@"WHAT THE?");
    }
}

- (IBAction)itemDoubleClicked:(id)sender
{
    NSInteger                   row;
    CK2OpenPanelController      *controller;
    
    controller = [self controller];
    row = [_outlineView clickedRow];
    
    if (row != -1)
    {
        NSURL       *url;
        
        url = [_outlineView itemAtRow:row];
        
        if ([url canHazChildren])
        {
            if (![url isEqual:[[controller openPanel] directoryURL]])
            {
                [controller addToHistory];
                [controller setURL:url updateDirectory:YES sender:self];
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
    else
    {
        NSLog(@"WHAT THE?");
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
    if (item == nil)
    {
        item = [[[self controller] openPanel] directoryURL];
    }
    return [item canHazChildren];
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
        return [item displayName];
    }
    else if ([identifier isEqual:@"Date Modified"])
    {
        return [item dateModified];
    }
    else if ([identifier isEqual:@"Size"])
    {
        id      value;
        
        value = [(NSURL *)item size];
        
        if (value == nil)
        {
            return @"--";
        }
        return value;
    }
    else if ([identifier isEqual:@"Kind"])
    {
        return [(NSURL *)item kind];
    }
    return nil;
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    if ([[tableColumn identifier] isEqual:@"Name"])
    {
        [cell setImage:[item icon]];
    }
    
    if ([[self controller] isURLValid:item])
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
    return [[self controller] isURLValid:item];
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

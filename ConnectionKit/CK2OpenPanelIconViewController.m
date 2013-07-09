//
//  CK2OpenPanelIconViewController.m
//  ConnectionKit
//
//  Created by Paul Kim on 1/9/13.
//  Copyright (c) 2013 Paul Kim. All rights reserved.
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

#import "CK2OpenPanelIconViewController.h"
#import "CK2OpenPanelController.h"
#import "NSURL+CK2OpenPanel.h"
#import "CK2IconViewItem.h"
#import "CK2IconItemView.h"
#import "CK2IconView.h"

@interface CK2OpenPanelIconViewController ()

@end

@implementation CK2OpenPanelIconViewController


- (void)awakeFromNib
{
    CK2IconViewItem     *iconItem;
    
    iconItem = (CK2IconViewItem *)[_iconView itemPrototype];
    [iconItem setTarget:self];
    [iconItem setAction:@selector(itemSelected:)];
    [iconItem setDoubleAction:@selector(itemDoubleClicked:)];
}

- (BOOL)allowsMutipleSelection
{
    return [_iconView allowsMultipleSelection];
}

- (void)setAllowsMutipleSelection:(BOOL)allowsMutipleSelection
{
    [_iconView setAllowsMultipleSelection:allowsMutipleSelection];
}

- (void)reload
{
    CK2OpenPanelController  *controller;
    NSArray                 *children;
    NSUInteger              i, count;
    NSURL                   *url;
    
    controller = [self controller];
    
    children = [controller childrenForURL:[[controller openPanel] directoryURL]];
    [_iconView setContent:children];
    
    if (([children count] == 1) && [[children lastObject] ck2_isPlaceholder])
    {
        [_iconView setMessageMode:YES];
    }
    else
    {
        [_iconView setMessageMode:NO];
    }
    
    count = [children count];
    
    for (i = 0; i < count; i++)
    {
        url = [children objectAtIndex:i];
        
        [(CK2IconViewItem *)[_iconView itemAtIndex:i] setEnabled:([controller isURLValid:url] || [controller URLCanHazChildren:url])];
    }
    [_iconView setNeedsDisplay:YES];
}

- (void)update
{
    CK2OpenPanelController  *controller;
    NSArray                 *children, *urls;
    NSUInteger              i;
    NSURL                   *url, *directoryURL;
    NSMutableIndexSet       *indexSet;
    NSRect                  rect;
    NSMutableArray          *newURLs;
    
    [self reload];
    
    controller = [self controller];
    directoryURL = [[controller openPanel] directoryURL];
    
    children = [controller childrenForURL:directoryURL];
    
    urls = [controller URLs];
    indexSet = [NSMutableIndexSet indexSet];
    rect = NSZeroRect;
    
    newURLs = [NSMutableArray array];
    
    for (url in urls)
    {
        if (![url isEqual:directoryURL])
        {
            i = [children indexOfObject:url];
            
            if (i != NSNotFound)
            {
                [indexSet addIndex:i];
                rect = NSUnionRect(rect, [_iconView frameForItemAtIndex:i]);
                [newURLs addObject:url];
            }
        }
    }
    [_iconView setSelectionIndexes:indexSet];
    [_iconView scrollRectToVisible:rect];
    
    if ([newURLs count] != [urls count])
    {
        // Only a subset of the URLs actually are visible so we update the internal URLs to match.
        [controller setURLs:newURLs updateDirectory:NO sender:self];
    }
}


- (void)urlDidLoad:(NSURL *)url
{
    [self reload];
}

- (NSArray *)selectedURLs
{
    NSIndexSet      *indexSet;
    NSArray         *urls;
    
    indexSet = [_iconView selectionIndexes];
    if ([indexSet count] > 0)
    {
        urls = [[_iconView content] objectsAtIndexes:indexSet];
    }
    else
    {
        urls = [NSArray array];
    }
    return urls;
}

- (IBAction)itemDoubleClicked:(id)sender
{
    [self goToSelectedItem:sender];
}

- (IBAction)goToSelectedItem:(id)sender
{
    CK2OpenPanelController  *controller;
    NSArray                 *urls;
    
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
    }
    else
    {
        BOOL    isValid;

        isValid = YES;
        for (NSURL *url in urls)
        {
            if (![controller isURLValid:url])
            {
                isValid = NO;
            }
        }
        
        if (isValid)
        {
            [controller ok:self];
        }
    }
}

@end

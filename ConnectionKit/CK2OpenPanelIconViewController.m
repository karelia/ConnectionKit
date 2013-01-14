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

@interface CK2OpenPanelIconViewController ()

@end

@implementation CK2OpenPanelIconViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:_iconView];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidBecomeKeyNotification object:[[self controller] openPanel]];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResignKeyNotification object:[[self controller] openPanel]];

    [super dealloc];
}

- (void)awakeFromNib
{
    CK2IconViewItem     *iconItem;
    
    iconItem = (CK2IconViewItem *)[_iconView itemPrototype];
    [iconItem setTarget:self];
    [iconItem setAction:@selector(itemSelected:)];
    [iconItem setDoubleAction:@selector(itemDoubleClicked:)];

    [_iconView setPostsFrameChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(iconViewDidResize:) name:NSViewFrameDidChangeNotification object:_iconView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidBecomeKey:) name:NSWindowDidBecomeKeyNotification object:[[self controller] openPanel]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidResignKey:) name:NSWindowDidResignKeyNotification object:[[self controller] openPanel]];
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
    
    count = [children count];
    
    for (i = 0; i < count; i++)
    {
        url = [children objectAtIndex:i];
        
        [(CK2IconViewItem *)[_iconView itemAtIndex:i] setEnabled:[controller isURLValid:url]];
    }
    [_iconView setNeedsDisplay:YES];
}

- (void)update
{
    CK2OpenPanelController  *controller;
    NSArray                 *children;
    NSUInteger              i;
    NSURL                   *url, *directoryURL;
    
    [self reload];
    
    controller = [self controller];
    directoryURL = [[controller openPanel] directoryURL];
    
    children = [controller childrenForURL:directoryURL];
    
    url = [controller URL];
    
    if (![url isEqual:directoryURL])
    {
        i = [children indexOfObject:url];
        
        if (i != NSNotFound)
        {
            NSRect  rect;
            
            [_iconView setSelectionIndexes:[NSIndexSet indexSetWithIndex:i]];
            
            rect = [_iconView frameForItemAtIndex:i];
            [_iconView scrollRectToVisible:rect];
        }
        else
        {
            NSLog(@"No index found for item: %@", url);
        }
    }
    
    [self iconViewDidResize:nil];
}


- (void)urlDidLoad:(NSURL *)url
{
    [self reload];
}

- (IBAction)itemSelected:(id)sender
{
    NSURL       *url;
    
    url = [sender representedObject];
    [[self controller] setURL:url updateDirectory:NO sender:self];
}

- (IBAction)itemDoubleClicked:(id)sender
{
    CK2OpenPanelController  *controller;
    NSURL                   *url;
    
    controller = [self controller];
    url = [sender representedObject];
    
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

- (void)iconViewDidResize:(NSNotification *)notification
{
    NSUInteger  colCount;
    CGFloat     calcWidth;
    NSSize      size, minSize;
    NSRect      frame;
    
    // NSCollectionView tends to align things towards the left. We want the icons to be evenly distributed so we
    // set the minimum width of each item to force such a layout.
    frame = [_iconView frame];
    minSize = [[[_iconView itemPrototype] view] frame].size;
    
    colCount = NSWidth(frame) / minSize.width;
    calcWidth = NSWidth(frame) / colCount;
    
    [_iconView setMaxNumberOfColumns:colCount];
    
    size = NSMakeSize(calcWidth, minSize.width);
    [_iconView setMinItemSize:size];
    // Setting the max size gets rid of odd scroller behavior
    [_iconView setMaxItemSize:size];
    
}


#pragma mark NSWindowDelegate

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    [_iconView setNeedsDisplay:YES];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    [_iconView setNeedsDisplay:YES];
}

@end

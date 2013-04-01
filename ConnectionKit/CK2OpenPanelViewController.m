//
//  CK2OpenPanelViewController.m
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

#import "CK2OpenPanelViewController.h"
#import "CK2OpenPanelController.h"

@implementation CK2OpenPanelViewController

- (id)init
{
    if ((self = [super initWithNibName:nil bundle:nil]) != nil)
    {
    }
    return self;
}

@synthesize controller = _controller;

- (BOOL)allowsMutipleSelection
{
    return NO;
}

- (void)setAllowsMutipleSelection:(BOOL)allowsMutipleSelection
{
}

- (void)reload
{
}

- (void)update
{
}

- (BOOL)hasFixedRoot
{
    return NO;
}

- (void)urlDidLoad:(NSURL *)url
{
}

- (NSArray *)selectedURLs
{
    return [NSArray array];
}


- (IBAction)itemSelected:(id)sender
{
    NSArray         *urls;
    
    urls = [self selectedURLs];
    
    if ([urls count] > 0)
    {
        [[self controller] setURLs:urls updateDirectory:[self hasFixedRoot] sender:self];
    }
}

- (IBAction)itemDoubleClicked:(id)sender
{
}

- (void)saveViewHistoryState:(NSMutableDictionary *)dict
{
}

- (void)restoreViewHistoryState:(NSDictionary *)dict
{
}

- (IBAction)goToSelectedItem:(id)sender
{
}



@end

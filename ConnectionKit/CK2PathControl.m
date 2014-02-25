//
//  CK2PathControl.m
//  ConnectionKit
//
//  Created by Paul Kim on 12/27/12.
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

#import "CK2PathControl.h"
#import "NSURL+CK2OpenPanel.h"
#import "CK2OpenPanelController.h"
#import "NSImage+CK2OpenPanel.h"

#define ICON_SIZE       16.0

@implementation CK2PathControl

@synthesize URL = _url;

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame pullsDown:NO]) != nil)
    {
        [[self menu] setAutoenablesItems:NO];
    }
    
    return self;
}

- (void)dealloc
{
    [_url release];
    [super dealloc];
}

- (void)urlSelected:(id)sender
{
    [self setURL:[sender representedObject]];
    [self sendAction:[self action] to:[self target]];
}

- (void)setURL:(NSURL *)url
{
    if (![url isEqual:_url])
    {
        NSMenu          *menu;
        
        [_url release];
        _url = [url retain];

        menu = [self menu];
        [menu removeAllItems];
        
        if (url != nil)
        {
            NSSize          size;
            NSURL           *tempURL;

            size = NSMakeSize(ICON_SIZE, ICON_SIZE);
            tempURL = _url;
            
            while (tempURL != nil)
            {
                NSImage         *image;
                NSString        *title;
                NSMenuItem      *item;
                
                image = [[[tempURL ck2_icon] copy] autorelease];
                title = [tempURL ck2_displayName];
                
                if ([title isEqual:@"/"])
                {
                    title = [tempURL host];
                }
                else if (title == nil)   // happens for URLs like ftpes://user@example.com
                {
                    title = @"";
                }
                
                item = [[NSMenuItem alloc] initWithTitle:title action:@selector(urlSelected:) keyEquivalent:@""];
                [item setTarget:self];
                [image setSize:size];
                [item setImage:image];
                [item setRepresentedObject:tempURL];
                [menu addItem:item];
                [item release];
                
                tempURL = [tempURL ck2_parentURL];
            }
        }
        [self selectItemAtIndex:0];
    }
}


@end

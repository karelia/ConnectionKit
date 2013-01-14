//
//  CKRemoteOpenPanel.m
//  ConnectionKit
//
//  Created by Paul Kim on 12/14/12.
//  Copyright (c) 2012 Paul Kim. All rights reserved.
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


#import "CK2OpenPanel.h"
#import "CK2OpenPanelController.h"

@interface CK2OpenPanel ()

@property (readwrite, copy) void        (^completionBlock)(NSInteger result);

- (void)endWithCode:(NSInteger)code;

@end

@implementation CK2OpenPanel

@synthesize title = _title;
@synthesize prompt = _prompt;
@synthesize canChooseFiles = _canChooseFiles;
@synthesize canChooseDirectories = _canChooseDirectories;
@synthesize showsHiddenFiles = _showsHiddenFiles;
@synthesize treatsFilePackagesAsDirectories = _treatsFilePackagesAsDirectories;
@synthesize canCreateDirectories = _canCreateDirectories;
@synthesize completionBlock = _completionBlock;

+ (CK2OpenPanel *)openPanel
{
    return [[[CK2OpenPanel alloc] init] autorelease];
}

- (id)init
{
    if ((self = [super initWithContentRect:NSMakeRect(0.0, 0.0, 525.0, 350.0) styleMask:NSTitledWindowMask | NSResizableWindowMask backing:NSBackingStoreBuffered defer:NO]) != nil)
    {
        NSRect  rect;
        NSView  *view;

        [self setTitle:@"Open"];
        [self setHidesOnDeactivate:NO];
        
        _viewController  = [[CK2OpenPanelController alloc] initWithPanel:self];
        
        view = [_viewController view];
        rect = [[self class] frameRectForContentRect:[view frame] styleMask:[self styleMask]];
        
        [self setFrame:rect display:NO];
        [self setContentView:view];
        
        [self setDirectoryURL:[NSURL fileURLWithPath:@"/"] completionBlock:NULL];
        [self setCanChooseDirectories:YES];
        [self setCanChooseFiles:NO];
        [self setCanCreateDirectories:NO];
        [self setTreatsFilePackagesAsDirectories:YES];
        [self setShowsHiddenFiles:NO];
        [self setMinSize:NSMakeSize(515.0, 475.0)];
    }
    return self;
}

- (void)dealloc
{
    [self setCompletionBlock:nil];
    [_viewController release];
    [super dealloc];
}

- (id <CK2OpenPanelDelegate>)delegate
{
    // Both protocols (this one and NSWindowDelegate) are totally optional so we
    // can cast with impunity, as NSSavePanel most likely does for its delegate
    return (id <CK2OpenPanelDelegate>)[super delegate];
}

- (void)setDelegate:(id <CK2OpenPanelDelegate>)delegate
{
    // Both protocols (this one and NSWindowDelegate) are totally optional so we
    // can cast with impunity, as NSSavePanel most likely does for its delegate
    [super setDelegate:(id <NSWindowDelegate>)delegate];
}

- (void)setDirectoryURL:(NSURL *)directoryURL completionBlock:(void (^)(NSError *error))block
{
    [_viewController changeDirectory:directoryURL completionBlock:block];
}

- (NSURL *)directoryURL
{
    return [_viewController directoryURL];
}

- (NSURL *)URL
{
    return [_viewController URL];
}

- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSInteger result))handler
{
    CFRetain(self);
    [NSApp beginSheet:self modalForWindow:window modalDelegate:self didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:[handler copy]];
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    if (sheet == self)
    {
        void    (^completionBlock)(NSInteger result);
        
        completionBlock = contextInfo;
        
        if (completionBlock != nil)
        {
            completionBlock(returnCode);
            [completionBlock release];
        }
    }
    else
    {
        NSLog(@"SAY WHAT??");
    }
}

- (void)beginWithCompletionHandler:(void (^)(NSInteger result))handler
{
    CFRetain(self);
    
    [self setCompletionBlock:handler];
    [self center];
    [self makeKeyAndOrderFront:self];
}

- (NSInteger)runModal
{
    // NSFileHandlingPanelOKButton, NSFileHandlingPanelCancelButton
    [self center];
    return [NSApp runModalForWindow:self];
}

- (void)endWithCode:(NSInteger)code
{
    [self close];
    [_viewController resetSession];
    
    if ([self isModalPanel])
    {
        [NSApp stopModalWithCode:code];
    }
    else
    {
        //PENDING: need to test
        if ([self isSheet])
        {
            [NSApp endSheet:self returnCode:code];
        }
        else
        {
            void        (^block)(NSInteger);
            
            block = [self completionBlock];
            
            if (block != nil)
            {
                block(code);
                [self setCompletionBlock:nil];
            }
        }
        CFRelease(self);
    }
}

- (IBAction)ok:(id)sender
{
    if ([[self delegate] respondsToSelector:@selector(panel:validateURL:error:)])
    {
        NSError     *error;
        
        error = nil;
        if (![[self delegate] panel:self validateURL:[self URL] error:&error])
        {
            NSBeginCriticalAlertSheet([NSString stringWithFormat: @"The operation couldn't be completed. %@ error %ld", [error domain], [error code]], @"OK", nil, nil, self, self, NULL, NULL, NULL, @"");

            return;
        }
    }
    [self endWithCode:NSFileHandlingPanelOKButton];
}

- (IBAction)cancel:(id)sender
{
    [self endWithCode:NSFileHandlingPanelCancelButton];
}

@end

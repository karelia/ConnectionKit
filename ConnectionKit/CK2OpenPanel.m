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
#import "NSURL+CK2OpenPanel.h"

@interface CK2OpenPanel ()

@property (readwrite, copy) void        (^completionBlock)(NSInteger result);

- (void)endWithCode:(NSInteger)code;

@end

@implementation CK2OpenPanel

@synthesize title = _title;
@synthesize prompt = _prompt;
@synthesize message = _message;
@synthesize canChooseFiles = _canChooseFiles;
@synthesize canChooseDirectories = _canChooseDirectories;
@synthesize allowsMultipleSelection = _allowsMultipleSelection;
@synthesize showsHiddenFiles = _showsHiddenFiles;
@synthesize treatsFilePackagesAsDirectories = _treatsFilePackagesAsDirectories;
@synthesize canCreateDirectories = _canCreateDirectories;
@synthesize allowedFileTypes = _allowedFileTypes;
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

        [self setTitle:NSLocalizedStringFromTableInBundle(@"Open", nil, [NSBundle bundleForClass:[self class]], @"Default open panel title")];
        [self setHidesOnDeactivate:NO];
        
        _viewController  = [[CK2OpenPanelController alloc] initWithPanel:self];
        
        view = [_viewController view];
        rect = [[self class] frameRectForContentRect:[view frame] styleMask:[self styleMask]];
        
        [self setFrame:rect display:NO];
        [self setContentView:view];
        
        [self setCanChooseDirectories:YES];
        [self setCanChooseFiles:NO];
        [self setCanCreateDirectories:NO];
        [self setTreatsFilePackagesAsDirectories:NO];
        [self setShowsHiddenFiles:NO];
        [self setMinSize:NSMakeSize(515.0, 475.0)];
    }
    return self;
}

- (void)dealloc
{
    [_viewController close]; // holds a weak ref to us which needs breaking
    
    [_viewController release];
    [_title release];
    [_prompt release];
    [_message release];
    [_allowedFileTypes release];
    [_completionBlock release];
    
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

- (NSView *)accessoryView
{
    return [_viewController accessoryView];
}

- (void)setAccessoryView:(NSView *)accessoryView
{
    [_viewController setAccessoryView:accessoryView];
}

- (NSURL *)directoryURL
{
    return [_viewController directoryURL];
}

- (void)setDirectoryURL:(NSURL *)directoryURL;
{
    [self setDirectoryURL:directoryURL completionHandler:nil];
}

- (void)setDirectoryURL:(NSURL *)directoryURL completionHandler:(void (^)(NSError *))block;
{
    // Kick off async loading of the URL, but also store our own copy for clients to immediately pull out again if they wish
    [_viewController changeDirectory:directoryURL completionHandler:^(NSError *error) {
        
        // Re-dispatch using runloop so there's no danger from clients deciding
        // to call -runModal within it
        NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
            block(error);
        }];
        
        [[NSRunLoop currentRunLoop] performSelector:@selector(start)
                                             target:operation
                                           argument:nil
                                              order:0
                                              modes:@[NSRunLoopCommonModes]];
    }];
}

- (NSURL *)URL
{
    return [_viewController URL];
}

- (NSArray *)URLs
{
    return [_viewController URLs];
}

- (void)willAppear;
{
    // Default to root if no-one's supplied anything better
    if (![self directoryURL]) [self setDirectoryURL:[NSURL fileURLWithPath:@"/"]];
    
    [_viewController reload];
}

- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSInteger result))handler
{
    [self willAppear];
    
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
        
        CFRelease(self);    // cancels out retain in -beginSheet
    }
}

- (void)beginWithCompletionHandler:(void (^)(NSInteger result))handler
{
    [self willAppear];
        
    [self setCompletionBlock:handler];
    [self center];
    [self makeKeyAndOrderFront:self];
}

- (NSInteger)runModal
{
    [self willAppear];
    
    [self center];
    return [NSApp runModalForWindow:self];
}

- (void)endWithCode:(NSInteger)code
{
    [self close];
    
    if ([self isModalPanel])
    {
        [NSApp stopModalWithCode:code];
    }
    else if ([self isSheet])
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
    
    [_viewController resetSession];
}

- (IBAction)ok:(id)sender
{
    if ([[self delegate] respondsToSelector:@selector(panel:validateURL:error:)])
    {
        NSError     *error;
        
        for (NSURL *url in [self URLs])
        {
            error = nil;
            if (![[self delegate] panel:self validateURL:url error:&error])
            {
                [self presentError:error modalForWindow:self delegate:nil didPresentSelector:NULL contextInfo:NULL];
                return;
            }
        }
    }
    [self endWithCode:NSFileHandlingPanelOKButton];
}

- (IBAction)cancel:(id)sender
{
    [self endWithCode:NSFileHandlingPanelCancelButton];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    // Certain keys, like up and down arrows, will trigger this method being called even if the command key isn't down
    // so we need to check here.
    if (([event modifierFlags] & NSDeviceIndependentModifierFlagsMask & NSCommandKeyMask) != 0)
    {
        NSString    *string;
        
        string = [event charactersIgnoringModifiers];
        
        if ([string isEqual:@">"])
        {
            [self setShowsHiddenFiles:![self showsHiddenFiles]];
            return YES;
        }
        else if ([string isEqual:@"H"])
        {
            [_viewController home:self];
            return YES;
        }
        else if ([string isEqual:@"G"])
        {
            [_viewController showPathFieldWithString:[[self directoryURL] path]];
            return YES;
        }
        else if ([string isEqual:@"["])
        {
            [_viewController back:self];
            return YES;
        }
        else if ([string isEqual:@"]"])
        {
            [_viewController forward:self];
            return YES;
        }
        else if ([string isEqual:[NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey]])
        {
            NSURL       *parentURL;
            
            parentURL = [[self directoryURL] ck2_parentURL];
            
            if (parentURL != nil)
            {
                [_viewController changeDirectory:parentURL completionHandler:
                 ^(NSError *error)
                 {
                     if (error != nil)
                     {
                         NSLog(@"Could not navigate to enclosing folder from URL %@: %@", [self directoryURL], error);
                         NSBeginCriticalAlertSheet(NSLocalizedStringFromTableInBundle(@"Could not go to enclosing folder.", nil, [NSBundle bundleForClass:[self class]], @"Enclosing folder error"),
                                                   NSLocalizedStringFromTableInBundle(@"OK", nil, [NSBundle bundleForClass:[self class]], @"OK Button"), nil, nil, self, nil, NULL, NULL, NULL, @"%@", [error localizedDescription]);
                         [_viewController back:self];
                     }
                 }];
            }
            return YES;
        }
        else if ([string isEqual:[NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey]])
        {
            [_viewController goToSelectedItem:self];
            return YES;
        }
    }
    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event
{
    if ([event type] == NSKeyDown)
    {
        NSString    *string;
        NSUInteger  flags;
        
        string = [event characters];
        flags = [event modifierFlags] & NSDeviceIndependentModifierFlagsMask;

        if (([string isEqual:@"/"] || [string isEqual:@"~"]) && ((flags & NSCommandKeyMask) == 0))
        {
            [_viewController showPathFieldWithString:string];
            return;
        }
    }
    [super keyDown:event];
}

- (void)validateVisibleColumns
{
    [_viewController validateVisibleColumns];
}

@end

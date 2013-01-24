//
//  CKRemoteOpenPanel.h
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

#import <Cocoa/Cocoa.h>

//TODO: Provide support for symlinks
//TODO: Handle/display errors better
//TODO: Save window/view dimensions and state (like which view is selected)
//TODO: Implement "form-fitting" text selection in icon view
//TODO: Restore outlineview expanded items when reverting history
//TODO: Implement "hidden" feature where you can type in a path (a little sheet shows up when you type / or ~)

@protocol CK2OpenPanelDelegate;
@class CK2OpenPanelController;

@interface CK2OpenPanel : NSPanel
{
    CK2OpenPanelController      *_viewController;
    NSString                    *_title;
    NSString                    *_prompt;
    NSString                    *_message;
    BOOL                        _canChooseFiles;
    BOOL                        _canChooseDirectories;
    BOOL                        _allowsMultipleSelection;
    BOOL                        _showsHiddenFiles;
    BOOL                        _treatsFilePackagesAsDirectories;
    BOOL                        _canCreateDirectories;
    NSArray                     *_allowedFileTypes;
    
    void                        (^_completionBlock)(NSInteger result);
}

@property (readwrite, copy) NSString    *title;
@property (readwrite, copy) NSString    *prompt;
@property (readwrite, copy) NSString    *message;
@property (readwrite, retain) NSView    *accessoryView;
@property (readwrite, assign) BOOL      canChooseFiles;
@property (readwrite, assign) BOOL      canChooseDirectories;
@property (readwrite, assign) BOOL      allowsMultipleSelection;
@property (readwrite, assign) BOOL      showsHiddenFiles;
@property (readwrite, assign) BOOL      treatsFilePackagesAsDirectories;
@property (readwrite, assign) BOOL      canCreateDirectories;
@property (readwrite, copy) NSArray     *allowedFileTypes;
@property (readwrite, copy, nonatomic) NSURL       *directoryURL;

@property (readonly, copy) NSURL        *URL;
@property (readonly, copy) NSArray      *URLs;



+ (CK2OpenPanel *)openPanel;

- (id <CK2OpenPanelDelegate>)delegate;
- (void)setDelegate:(id <CK2OpenPanelDelegate>)delegate;

// The completion block will not be called until the given URL and all URLs up to it are fully loaded.
// That way, if you show the panel in the completion block, nothing will be "in progress". You can still show
// the panel beforehand but much of the UI will be disabled until the URLs are loaded. The UI will still be responsive
// in that you'll see progress indicators spinning and you can still cancel.
// Note that the completion block is called on the main thread.
// .directoryURL immediately reflects the URL called with
- (void)setDirectoryURL:(NSURL *)directoryURL completionBlock:(void (^)(NSError *error))block;

- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSInteger result))handler;
- (void)beginWithCompletionHandler:(void (^)(NSInteger result))handler;
- (NSInteger)runModal;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;

- (void)validateVisibleColumns;

@end


@protocol CK2OpenPanelDelegate <NSObject>

@optional

- (void)panel:(id)sender didChangeToDirectoryURL:(NSURL *)url;
- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url;
- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError;
- (void)panelSelectionDidChange:(id)sender;

- (void)panel:(id)sender didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

@end

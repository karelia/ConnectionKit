//
//  CKRemoteViewController.h
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
#import <dispatch/dispatch.h>
#import <ConnectionKit/CK2FileManager.h>

@class CK2OpenPanel, CK2BrowserPreviewController, CK2PathControl, CK2FileManager, CK2OpenPanelColumnViewController, CK2OpenPanelListViewController, CK2OpenPanelIconViewController, CK2PathFieldWindowController;

@interface CK2OpenPanelController : NSViewController <NSTabViewDelegate, CK2FileManagerDelegate>
{
    IBOutlet NSView                 *_topSection;
    IBOutlet NSTextField            *_hostField;
    IBOutlet NSView                 *_buttonSection;
    IBOutlet CK2PathControl         *_pathControl;
    IBOutlet NSSegmentedControl     *_viewPicker;
    IBOutlet NSView                 *_middleSection;
    IBOutlet NSTabView              *_tabView;
    IBOutlet NSView                 *_bottomSection;
    IBOutlet NSButton               *_okButton;
    IBOutlet NSButton               *_cancelButton;
    IBOutlet NSButton               *_refreshButton;
    IBOutlet NSProgressIndicator    *_progressIndicator;
    IBOutlet NSSegmentedControl     *_historyButtons;
    IBOutlet NSButton               *_newFolderButton;
    IBOutlet NSSegmentedControl     *_homeButton;
    
    IBOutlet NSTextField            *_messageLabel;
    IBOutlet NSBox                  *_accessoryContainer;
    NSView                          *_initialAccessoryView;
    
    IBOutlet CK2OpenPanel                        *_openPanel;
    IBOutlet CK2OpenPanelColumnViewController    *_browserController;
    IBOutlet CK2OpenPanelListViewController      *_listViewController;
    IBOutlet CK2OpenPanelIconViewController      *_iconViewController;
    
    NSURL                           *_directoryURL;
    NSArray                         *_urls;
    NSURL                           *_homeURL;
    
    NSMutableDictionary             *_urlCache;
    NSMutableDictionary             *_runningOperations;
    CK2FileManager                  *_fileManager;
    
    NSUndoManager                   *_historyManager;
    NSTabViewItem                   *_lastTab;
    
    CK2FileOperation                *_currentLoadingOperation;
    
    CK2PathFieldWindowController    *_pathFieldController;
}

@property (readonly, assign) CK2OpenPanel       *openPanel;
@property (readonly, retain) NSURL              *directoryURL;
@property (readwrite, retain) NSURL             *URL;
@property (readwrite, copy, nonatomic) NSArray  *URLs;
@property (readwrite, retain, nonatomic) NSURL  *homeURL;
@property (readwrite, retain) NSView            *accessoryView;

@property (readonly, retain) CK2FileManager     *fileManager;

- (id)initWithPanel:(CK2OpenPanel *)panel;
- (void)close;  // Open panel MUST call this to clear out weak reference to itself, otherwise BOOM dangling pointer!

- (void)changeDirectory:(NSURL *)directoryURL completionHandler:(void (^)(NSError *error))block;

- (IBAction)pathControlItemSelected:(id)sender;

- (void)resetSession;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)refresh:(id)sender;
- (IBAction)newFolder:(id)sender;
- (IBAction)changeHistory:(id)sender;
- (IBAction)back:(id)sender;
- (IBAction)forward:(id)sender;

- (IBAction)home:(id)sender;
- (void)goToSelectedItem:(id)sender;

- (void)showPathFieldWithString:(NSString *)string;

- (void)setURLs:(NSArray *)urls updateDirectory:(BOOL)updateDir sender:(id)sender;
- (void)setURLs:(NSArray *)urls updateDirectory:(BOOL)updateDir updateRoot:(BOOL)updateRoot sender:(id)sender;
- (BOOL)isURLValid:(NSURL *)url;
- (BOOL)URLCanHazChildren:(NSURL *)url;
- (NSArray *)childrenForURL:(NSURL *)url;
- (void)addToHistory;
- (void)reload;

- (void)validateVisibleColumns;

@end

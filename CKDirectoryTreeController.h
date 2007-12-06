/*
 Copyright (c) 2007, Ubermind, Inc
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Ubermind, Inc nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 Authored by Greg Hulands <ghulands@mac.com>
 */

#import <Cocoa/Cocoa.h>

@class CKDirectoryNode, CKTableBasedBrowser, CKTriStateMenuButton;

typedef enum {
	CKBrowserStyle = 0,
	CKOutlineViewStyle,
	CKIconViewStyle, // not implemented
	CKCoverFlowStyle // not implemented
} CKDirectoryViewStyle;

@interface CKDirectoryTreeController : NSObject 
{
	IBOutlet NSView *oView;
	IBOutlet NSOutlineView *oOutlineView;
	IBOutlet CKTableBasedBrowser *oBrowser;
	IBOutlet NSBrowser *oStandardBrowser;
	IBOutlet NSPopUpButton *oPopup;
	IBOutlet NSSegmentedControl *oStyle;
	IBOutlet NSSegmentedControl *oHistory;
	IBOutlet NSSearchField *oSearch;
	IBOutlet NSTabView *oStyles;
	IBOutlet NSPopUpButton *oActionGear;
	
	// Inspector panel
	IBOutlet NSView *oInspectorView;
	IBOutlet NSImageView *oIcon;
	IBOutlet NSTextField *oName;
	IBOutlet NSTextField *oSize;
	IBOutlet NSTextField *oKind;
	IBOutlet NSTextField *oModified;
	IBOutlet NSTextField *oPermissions;
	
	NSMutableDictionary *myOutlineViewColumns;
	
	CKDirectoryNode *myRootNode;
	NSString *myRootDirectory;
	NSString *myRelativeRootPath;
	NSString *mySelectedDirectory;
	CKDirectoryNode *mySelectedNode; // not retained
	NSMutableSet *mySelection;
	NSMutableArray *myHistory;
	int myHistoryIndex;
	NSString *myFilter;
	unsigned myDirectoriesLoading;
	unsigned long long myCachedContentsThresholdSize;
	NSString *mySearchString;
	NSMutableSet *myExpandedOutlineItems;
	
	id myDelegate;
	id myTarget;
	SEL myAction;
	
	struct __ckdtc_flags {
		unsigned isRemote: 1;
		unsigned allowsDrags: 1;
		unsigned allowsDrops: 1;
		unsigned isEnabled: 1;
		unsigned showsHiddenFiles: 1;
		unsigned outlineViewDoubleCallback: 1;
		unsigned isNavigatingToPath: 1;
		unsigned filePackages: 1;
		unsigned showsFilePackageExtensions: 1;
		unsigned canCreateFolders: 1;
		unsigned isReloading: 1;
		unsigned firstTimeWithOutlineView: 1;
		unsigned outlineViewFullReload: 1;
		unsigned wasHistoryOperation: 1;
		unsigned unused: 18;
	} myFlags;
}

- (void)setDelegate:(id)delegate;
- (id)delegate;

- (void)setTarget:(id)target;
- (id)target;
- (void)setAction:(SEL)action;
- (SEL)action;

- (void)setContentIsRemote:(BOOL)flag;
- (BOOL)contentIsRemote;
- (void)setAllowsDrags:(BOOL)flag;
- (BOOL)allowsDrags;
- (void)setAllowsDrops:(BOOL)flag;
- (BOOL)allowsDrops;
- (void)setEnabled:(BOOL)flag;
- (BOOL)isEnabled;
- (void)setShowHiddenFiles:(BOOL)flag;
- (BOOL)showsHiddenFiles;
- (void)setTreatsFilePackagesAsDirectories:(BOOL)flag;
- (BOOL)treatsFilePackagesAsDirectories;
- (void)setShowsFilePackageExtensions:(BOOL)flag;
- (BOOL)showsFilePackageExtensions;

- (void)setCanCreateDirectories:(BOOL)flag;
- (BOOL)canCreateDirectories;

- (void)setBaseViewDirectory:(NSString *)dir;
- (NSString *)baseViewDirectory;

- (NSArray *)selectedPaths;
- (NSString *)selectedPath;
- (NSString *)selectedFolderPath; // if selectedPath is a file, it will return the containing folder path of the file

- (NSArray *)contentsOfSelectedFolder; // contains dictionaries with NSFileManager keys

- (void)setContents:(NSArray *)contents forPath:(NSString *)path;
- (void)setContents:(NSData *)contents forFile:(NSString *)file;

- (NSView *)view;

- (IBAction)viewStyleChanged:(id)sender;
- (IBAction)popupChanged:(id)sender;
- (IBAction)outlineViewSelected:(id)sender;
- (IBAction)browserSelected:(id)sender;
- (IBAction)filterChanged:(id)sender;
- (IBAction)historyChanged:(id)sender;
- (IBAction)newFolder:(id)sender;

- (void)setCachedContentsThresholdSize:(unsigned long long)bytes;
- (unsigned long long)cachedContentsThresholdSize;

@end

@interface NSObject (CKDirectoryTreeControllerDelegate)

- (void)directoryTree:(CKDirectoryTreeController *)controller needsContentsForPath:(NSString *)path;
- (void)directoryTree:(CKDirectoryTreeController *)controller needsContentsOfFile:(NSString *)file; 
- (void)directoryTreeStartedLoadingContents:(CKDirectoryTreeController *)controller;
- (void)directoryTreeFinishedLoadingContents:(CKDirectoryTreeController *)controller;
- (void)directoryTreeWantsNewFolderCreated:(CKDirectoryTreeController *)controller;
- (void)directoryTreeController:(CKDirectoryTreeController *)controller willDisplayActionGearMenu:(NSMenu *)menu; // allow custom items to be added

@end

@interface CKDirectoryTableBrowserCell : NSBrowserCell
{
	NSString *myTitle;
}

@end

@interface CKDirectoryNodeFormatter : NSFormatter
{
	id myDelegate;
}

- (void)setDelegate:(id)delegate;

@end

@interface NSObject (CKDirectoryNodeFormatterDelegate) 

- (NSString *)directoryNodeFormatter:(CKDirectoryNodeFormatter *)formatter stringRepresentationWithNode:(CKDirectoryNode *)node;

@end

@interface CKDirectoryCell : NSCell
{
	NSImage *myIcon;
}

@end

@interface CKFileSizeFormatter : NSFormatter
{
	
}

@end

@interface CKDynamicDateFormattingCell : NSTextFieldCell
{
}

- (void)setFormat:(NSString *)format;

@end

@interface CKTableHeaderView : NSTableHeaderView
{
	
}

@end

@interface CKDirectoryOutlineView : NSOutlineView
{
	NSMutableString *myQuickSearchString;
	BOOL myIsReloading;
}

@end

@interface CKTriStateButton : NSButton
{
	NSImage *myNormalImage;
    NSImage *myDisabledImage;
}

- (void)setNormalImage:(NSImage *)image;
- (void)setDisabledImage:(NSImage *)image;

@end

@interface CKTriStateMenuButton : CKTriStateButton
{
	id myDelegate;
}

- (void)setDelegate:(id)delegate;

@end

@interface NSObject (CKTriStateMenuDelegate)
- (NSMenu *)triStateMenuButtonNeedsMenu:(CKTriStateMenuButton *)button;
@end

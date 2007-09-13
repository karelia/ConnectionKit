//
//  CKDirectoryTreeController.h
//  Connection
//
//  Created by Greg Hulands on 27/08/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class CKDirectoryNode, CKTableBasedBrowser;

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
	IBOutlet NSPopUpButton *oPopup;
	IBOutlet NSSegmentedControl *oStyle;
	IBOutlet NSSegmentedControl *oHistory;
	IBOutlet NSSearchField *oSearch;
	IBOutlet NSTabView *oStyles;
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
	NSMutableArray *myHistory;
	unsigned myHistoryIndex;
	NSString *myFilter;
	unsigned myDirectoriesLoading;
	unsigned long long myCachedContentsThresholdSize;
	
	id myDelegate;
	
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
		unsigned unused: 23;
	} myFlags;
}

- (void)setDelegate:(id)delegate;
- (id)delegate;

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

- (void)setRootDirectory:(NSString *)dir;
- (NSString *)rootDirectory;

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

- (void)setCachedContentsThresholdSize:(unsigned long long)bytes;
- (unsigned long long)cachedContentsThresholdSize;

@end

@interface NSObject (CKDirectoryTreeControllerDelegate)

- (void)directoryTree:(CKDirectoryTreeController *)controller needsContentsForPath:(NSString *)path;
- (void)directoryTree:(CKDirectoryTreeController *)controller needsContentsOfFile:(NSString *)file; 
- (void)directoryTreeStartedLoadingContents:(CKDirectoryTreeController *)controller;
- (void)directoryTreeFinishedLoadingContents:(CKDirectoryTreeController *)controller;

@end

// these cells are passed an NSDictionary with keys name and icon to the objectValue of the cell
@interface CKDirectoryBrowserCell : NSBrowserCell
{
	CKDirectoryNode *myNode;
	BOOL myMakingDragImage;
}

- (void)setMakeDragImage:(BOOL)flag;
- (NSString *)path;

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
}

@end


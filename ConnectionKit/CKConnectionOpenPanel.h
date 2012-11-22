/*
 Copyright (c) 2006, Olivier Destrebecq <olivier@umich.edu>
 All rights reserved.
 
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Olivier Destrebecq nor the names of its contributors may be used to 
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
 
 */


#import <Cocoa/Cocoa.h>

@protocol CKConnection;

#import <Cocoa/Cocoa.h>
#import "CK2FileManager.h"


enum {
	connectionBadPasswordUserName = -1
};


@interface CKConnectionOpenPanel : NSWindowController 
{
	IBOutlet NSArrayController *directoryContents;
    IBOutlet NSPathControl  *pathControl;
	IBOutlet NSTableView *tableView;
    IBOutlet NSButton *openButton;
    IBOutlet NSButton *openCancelButton;

	IBOutlet NSWindow       *createFolder;
    IBOutlet NSButton       *createFolderButton;
    IBOutlet NSTextField    *folderNameField;
    
  @private
	CK2FileManager  *_session;
    NSURL                   *_directory;
    
    // Basic settings
	BOOL        _canChooseDirectories;
	BOOL        _canChooseFiles;
	BOOL        _canCreateDirectories;
    BOOL        _shouldDisplayOpenButton;
    BOOL        _shouldDisplayOpenCancelButton;
	BOOL        _allowsMultipleSelection;
	NSString    *_prompt;
	NSArray     *_allowedFileTypes;
    
	BOOL isLoading;
	BOOL isSelectionValid;
	NSModalSession myModalSession;
	BOOL myKeepRunning;
}

- (id)initWithFileTransferSession:(CK2FileManager *)session directoryURL:(NSURL *)url;

- (IBAction) closePanel: (id) sender;
- (IBAction) newFolder: (id) sender;
- (IBAction)goToFolder:(NSPathControl *)sender;
- (IBAction)createNewFolder:(NSButton *)sender;

@property(nonatomic, readonly) CK2FileManager *session;
@property(nonatomic, copy) NSURL *directoryURL;

@property(nonatomic) BOOL canChooseDirectories;
@property(nonatomic) BOOL canChooseFiles;
@property(nonatomic) BOOL canCreateDirectories;
@property(nonatomic) BOOL shouldDisplayOpenButton;
@property(nonatomic) BOOL shouldDisplayOpenCancelButton;
@property(nonatomic) BOOL allowsMultipleSelection;
@property(nonatomic, copy) NSString *prompt;
@property(nonatomic, copy) NSArray *allowedFileTypes;

- (BOOL)isLoading;

- (NSArray *)URLs;
- (BOOL)isSelectionValid;
- (void)setIsSelectionValid:(BOOL)flag;

- (void)beginSheetModalForWindow:(NSWindow *)docWindow completionHandler:(void (^)(NSInteger))handler;
- (NSInteger)runModal;

@end


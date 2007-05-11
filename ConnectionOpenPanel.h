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

@protocol AbstractConnectionProtocol;

#import <Cocoa/Cocoa.h>
#import "AbstractConnection.h"

enum {
	connectionBadPasswordUserName = -1
};


@interface ConnectionOpenPanel : NSWindowController 
{
	id <AbstractConnectionProtocol> connection;
	BOOL canChooseDirectories;
	BOOL canChooseFiles;
	BOOL canCreateDirectories;
    BOOL shouldDisplayOpenButton;
    BOOL shouldDisplayOpenCancelButton;
	BOOL allowsMultipleSelection;
	BOOL isLoading;
	NSString *prompt;
	NSString *newFolderName;
	NSMutableArray *allowedFileTypes;
	NSString *initialDirectory;
	IBOutlet NSArrayController *directoryContents;
	IBOutlet NSArrayController *parentDirectories;
	IBOutlet NSWindow *createFolder;
	IBOutlet NSTableView *tableView;
    IBOutlet NSButton *openButton;
    IBOutlet NSButton *openCancelButton;
	id delegate;
	SEL delegateSelector;
	BOOL isSelectionValid;
	NSTimeInterval timeout;
	NSTimer *timer;
	NSString *createdDirectory;
	NSModalSession myModalSession;
	BOOL myKeepRunning;
	NSString *lastDirectory;
}

- (id)initWithConnection:(id <AbstractConnectionProtocol>) inConnection;
+ (ConnectionOpenPanel*)connectionOpenPanel:(id <AbstractConnectionProtocol>) inConnection;

- (IBAction) closePanel: (id) sender;
- (IBAction) newFolder: (id) sender;
- (IBAction) goToFolder: (id) sender;
- (IBAction) createNewFolder: (id) sender;

- (id <AbstractConnectionProtocol>)connection;
- (void)setConnection:(id <AbstractConnectionProtocol>)aConnection;
- (BOOL)canChooseDirectories;
- (void)setCanChooseDirectories:(BOOL)flag;
- (BOOL)canChooseFiles;
- (void)setCanChooseFiles:(BOOL)flag;
- (BOOL)canCreateDirectories;
- (void)setCanCreateDirectories:(BOOL)flag;
- (BOOL)shouldDisplayOpenButton;
- (void)setShouldDisplayOpenButton:(BOOL)flag;
- (BOOL)shouldDisplayOpenCancelButton;
- (void)setShouldDisplayOpenCancelButton:(BOOL)flag;
- (BOOL)allowsMultipleSelection;
- (void)setAllowsMultipleSelection:(BOOL)flag;
- (BOOL)isLoading;
- (void)setIsLoading:(BOOL)flag;
- (NSArray *)URLs;
- (NSArray *)filenames;
- (NSString *)prompt;
- (void)setPrompt:(NSString *)aPrompt;
- (NSMutableArray *)allowedFileTypes;
- (void)setAllowedFileTypes:(NSMutableArray *)anAllowedFileTypes;
- (NSString *)initialDirectory;
- (void)setInitialDirectory:(NSString *)anInitialDirectory;
- (NSString *)newFolderName;
- (void)setNewFolderName:(NSString *)aNewFolderName;
- (id)delegate;
- (void)setDelegate:(id)aDelegate;
- (SEL)delegateSelector;
- (void)setDelegateSelector:(SEL)aDelegateSelector;
- (BOOL)isSelectionValid;
- (void)setIsSelectionValid:(BOOL)flag;

- (void)setTimeout:(NSTimeInterval)to;
- (NSTimeInterval)timeout;

- (void)beginSheetForDirectory:(NSString *)path 
						  file:(NSString *)name 
				modalForWindow:(NSWindow *)docWindow 
				 modalDelegate:(id)modalDelegate 
				didEndSelector:(SEL)didEndSelector 
                   contextInfo:(void *)contextInfo;
- (int)runModalForDirectory:(NSString *)directory file:(NSString *)filename types:(NSArray *)fileTypes;

@end

@interface NSObject (ConnectionOpenPanelDelegate)
- (void)connectionOpenPanel:(ConnectionOpenPanel *)panel didSendBadPasswordToHost:(NSString *)host;
- (void)connectionOpenPanel:(ConnectionOpenPanel *)panel didReceiveError:(NSError *)error;
@end


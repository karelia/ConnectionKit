/*
 Copyright (c) 2006, Greg Hulands <ghulands@mac.com>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
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
#import "AbstractConnectionProtocol.h"

extern NSString *ControllerDomain; // used for logging
extern NSString *CKTransferControllerDomain; // used for errors

enum {
	CKFailedVerificationError = 54321,
	CKPasswordError,
	CKTooManyErrorsError
};

typedef enum {
	CKUnknownStatus = 0,
	CKSuccessStatus,
	CKFatalErrorStatus,
	CKAbortStatus
} CKTransferControllerStatus;

typedef enum {
	CKNotConnectedStatus = 0,
	CKConnectedStatus = 1,
	CKDisconnectedStatus = -1
} CKTransferConnectionStatus;


typedef enum {
	CKInitialPhase,
	CKKickoffPhase,
	CKContentGenerationPhase,
	CKFinishedContentGenerationPhase,
	CKDonePhase
} CKTransferPhase;

@class RunLoopForwarder;

@interface CKTransferController : NSWindowController 
{
	id <AbstractConnectionProtocol>		myConnection;		// may not be retained
	id <AbstractConnectionProtocol>		myVerificationConnection;
	
	CKTransferControllerStatus			myReturnStatus;
	CKTransferConnectionStatus			myConnectionStatus;
	CKTransferPhase						myPhase;
	
	NSMutableArray						*myTransfers;
	NSMutableSet						*myPathsToVerify;
	NSMutableArray						*myRootedTransfers;
	NSString							*myRootPath;
	
	NSString							*myUploadingPrefix;
	
	NSError								*myFatalError;
	
	IBOutlet NSTextField				*oTitle;
	IBOutlet NSProgressIndicator		*oProgress;
	IBOutlet NSImageView				*oIcon;
	IBOutlet NSTextField				*oStatus;
	IBOutlet NSTextField				*oShowHideFilesTitle;
	IBOutlet NSButton					*oShowFiles;
	IBOutlet NSOutlineView				*oFiles;
	IBOutlet NSButton					*oDefaultButton;
	IBOutlet NSButton					*oAlternateButton;
	
	// password panel
	IBOutlet NSTextField				*oPassword;
    IBOutlet NSPanel					*oPasswordPanel;
    IBOutlet NSTextField				*oPasswordText;
	
	RunLoopForwarder					*myForwarder;
	id									myDelegate;
	
	struct __cktransfercontroller_flags {
		unsigned delegateProvidesConnection: 1; 
		unsigned delegateProvidesContent: 1;
		unsigned delegateHandlesDefaultButton: 1;
		unsigned delegateHandlesAlternateButton: 1;
		unsigned delegateFinishedContentGeneration: 1;
		unsigned delegateDidFinish: 1;
		unsigned useThread: 1;
		unsigned waitForConnection:1;
		unsigned verifyTransfers: 1;
		unsigned stopTransfer: 1;
		unsigned unused: 21;
	} myFlags;
}

- (id)init;

- (void)setConnection:(id <AbstractConnectionProtocol>)connection;
- (id <AbstractConnectionProtocol>)connection;

- (void)setRootPath:(NSString *)path;

- (void)createDirectory:(NSString *)directory;
- (void)createDirectory:(NSString *)directory permissions:(unsigned long)permissions;
- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath;
- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath;
- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)remotePath;
- (void)deleteFile:(NSString *)remotePath;

- (void)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath;

- (void)setContentGeneratedInSeparateThread:(BOOL)flag;
- (BOOL)contentGeneratedInSeparateThread;

- (void)setVerifyTransfers:(BOOL)flag;
- (BOOL)verifyTransfers;

- (void)setWaitForConnection:(BOOL)flag;
- (BOOL)waitForConnection;

- (void)setDelegate:(id)delegate;
- (id)delegate;

- (void)setTitle:(NSString *)title;
- (void)setIcon:(NSImage *)icon;
- (void)setStatusMessage:(NSString *)message;
- (void)setProgress:(double)progress; // use < 0 for indeterminate
- (void)setFinished; // set progress to 100%
- (void)setDefaultButtonTitle:(NSString *)title;
- (void)setAlternateButtonTitle:(NSString *)title;
- (void)setUploadingStatusPrefix:(NSString *)prefix;

- (void)beginSheetModalForWindow:(NSWindow *)window;
- (void)runModal;

- (void)requestStopTransfer;
- (void) stopTransfer;


- (IBAction)defaultButtonPressed:(id)sender;
- (IBAction)alternateButtonPressed:(id)sender;
- (IBAction)showHideFiles:(id)sender;

- (IBAction)cancelPassword:(id)sender;
- (IBAction)connectPassword:(id)sender;

- (BOOL)problemsTransferringCountingErrors:(int *)outErrors successes:(int *)outSuccesses;

- (NSError *)fatalError;
- (void)setFatalError:(NSError *)aFatalError;

- (void)forceDisconnectAll;

- (BOOL)hadErrorsTransferring;

@end

@interface NSObject (CKTransferControllerDelegate)

- (id <AbstractConnectionProtocol>)transferControllerNeedsConnection:(CKTransferController *)controller createIfNeeded:(BOOL)aCreate;
- (BOOL)transferControllerNeedsContent:(CKTransferController *)controller; // this will be called on a new thread if you setContentGeneratedInSeparateThread:YES
- (void)transferControllerFinishedContentGeneration:(CKTransferController *)controller completed:(BOOL)aFlag; // called on the main thread
// return YES if you want the controllers default action to also be invoked
- (BOOL)transferControllerDefaultButtonAction:(CKTransferController *)controller;
- (BOOL)transferControllerAlternateButtonAction:(CKTransferController *)controller;
- (void)transferControllerDidFinish:(CKTransferController *)controller returnCode:(CKTransferControllerStatus)code;

@end
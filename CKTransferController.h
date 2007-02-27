//
//  CKTransferController.h
//  Connection
//
//  Created by Greg Hulands on 28/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Connection/AbstractConnectionProtocol.h>

extern NSString *ControllerDomain; // used for logging
extern NSString *CKTransferControllerDomain; // used for errors

enum {
	CKFailedVerificationError = 54321,
	CKPasswordError
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

- (void)stopTransfer:(id)sender;

- (IBAction)defaultButtonPressed:(id)sender;
- (IBAction)alternateButtonPressed:(id)sender;
- (IBAction)showHideFiles:(id)sender;

- (IBAction)cancelPassword:(id)sender;
- (IBAction)connectPassword:(id)sender;

- (BOOL)hadErrorsTransferring;

- (NSError *)fatalError;
- (void)setFatalError:(NSError *)aFatalError;

- (void)forceDisconnectAll;

@end

@interface NSObject (CKTransferControllerDelegate)

- (id <AbstractConnectionProtocol>)transferControllerNeedsConnection:(CKTransferController *)controller;
- (BOOL)transferControllerNeedsContent:(CKTransferController *)controller; // this will be called on a new thread if you setContentGeneratedInSeparateThread:YES
- (void)transferControllerFinishedContentGeneration:(CKTransferController *)controller completed:(BOOL)aFlag; // called on the main thread
// return YES if you want the controllers default action to also be invoked
- (BOOL)transferControllerDefaultButtonAction:(CKTransferController *)controller;
- (BOOL)transferControllerAlternateButtonAction:(CKTransferController *)controller;
- (void)transferControllerDidFinish:(CKTransferController *)controller returnCode:(CKTransferControllerStatus)code;

@end
//
//  CKController.h
//  Connection
//
//  Created by Greg Hulands on 20/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class CKHost;
@protocol AbstractConnectionProtocol;

@interface CKController : NSObject 
{
	IBOutlet NSPopUpButton	*oLocalDirectory;
	IBOutlet NSPopUpButton	*oRemoteDirectory;
	IBOutlet NSTableView	*oLocalFiles;
	IBOutlet NSTableView	*oRemoteFiles;
	IBOutlet NSOutlineView	*oTransfers;
	IBOutlet NSTextField	*oStatus;
	IBOutlet NSTextView		*oTranscript;
	
	@private
// UNUSED:	NSString				*myLocalDirectory;
// UNUSED:	NSString				*myRemoteDirectory;
// UNUSED:	CKHost					*myHost;
// UNUSED:	id <AbstractConnectionProtocol> myConnection;
// UNUSED:	id <AbstractConnectionProtocol> myLocalConnection;
	
// UNUSED:	NSMutableArray			*myTransfers;
	
// UNUSED:	struct __ckcontroller_flags {
//		unsigned canUpload: 1;
//		unsigned canDownload: 1;
//		unsigned canDeleteFiles: 1;
//		unsigned canDeleteFolders: 1;
//		unsigned unsued: 28;
//	} myFlags;
}

- (id)init;

- (void)setHost:(CKHost *)host;
- (CKHost *)host;

- (id <AbstractConnectionProtocol>)connection;

- (void)setCanUpload:(BOOL)flag;
- (void)setCanDownload:(BOOL)flag;
- (void)setCanDeleteFiles:(BOOL)flag;
- (void)setCancelDeleteDirectories:(BOOL)flag;

- (BOOL)canConnect;
- (BOOL)canDisconnect;
- (BOOL)canRefresh;
- (BOOL)hasSelection;
- (BOOL)canEdit;

- (IBAction)connect:(id)sender;
- (IBAction)disconnect:(id)sender;
- (IBAction)refresh:(id)sender;
- (IBAction)newRemoteFolder:(id)sender;
- (IBAction)newLocalFolder:(id)sender;
- (IBAction)editRemoteFile:(id)sender;
- (IBAction)editLocalFile:(id)sender;

- (IBAction)localFileSelected:(id)sender;
- (IBAction)localFileDoubleClicked:(id)sender;
- (IBAction)localDirectoryChanged:(id)sender;

- (IBAction)remoteFileSelected:(id)sender;
- (IBAction)remoteFileDoubleClicked:(id)sender;
- (IBAction)remoteDirectoryChanged:(id)sender;

- (IBAction)transferSelected:(id)sender;
- (IBAction)cancelTransfer:(id)sender;

- (IBAction)editPermissions:(id)sender;

@end

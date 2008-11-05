//
//  CKController.m
//  Connection
//
//  Created by Greg Hulands on 20/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKController.h"


@implementation CKController

- (id)init
{
	[super init];
	return self;
}

- (void)setHost:(CKHost *)host
{
	;
}
- (CKHost *)host
{
	return nil;
}

- (id <AbstractConnectionProtocol>)connection
{
	return nil;
}

- (void)setCanUpload:(BOOL)flag
{
	;
}
- (void)setCanDownload:(BOOL)flag
{
	;
}
- (void)setCanDeleteFiles:(BOOL)flag
{
	;
}
- (void)setCancelDeleteDirectories:(BOOL)flag
{
	;
}

- (BOOL)canConnect
{
	return NO;
}
- (BOOL)canDisconnect
{
	return NO;
}
- (BOOL)canRefresh
{
	return NO;
}
- (BOOL)hasSelection
{
	return NO;
}
- (BOOL)canEdit
{
	return NO;
}

- (IBAction)connect:(id)sender
{
	;
}
- (IBAction)disconnect:(id)sender
{
	;
}
- (IBAction)refresh:(id)sender
{
	;
}
- (IBAction)newRemoteFolder:(id)sender
{
	;
}
- (IBAction)newLocalFolder:(id)sender
{
	;
}
- (IBAction)editRemoteFile:(id)sender
{
	;
}
- (IBAction)editLocalFile:(id)sender
{
	;
}

- (IBAction)localFileSelected:(id)sender
{
	;
}
- (IBAction)localFileDoubleClicked:(id)sender
{
	;
}
- (IBAction)localDirectoryChanged:(id)sender
{
	;
}

- (IBAction)remoteFileSelected:(id)sender
{
	;
}
- (IBAction)remoteFileDoubleClicked:(id)sender
{
	;
}
- (IBAction)remoteDirectoryChanged:(id)sender
{
	;
}

- (IBAction)transferSelected:(id)sender
{
	;
}
- (IBAction)cancelTransfer:(id)sender
{
	;
}

- (IBAction)editPermissions:(id)sender
{
	;
}

@end

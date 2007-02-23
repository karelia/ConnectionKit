//
//  CKTransferController.m
//  Connection
//
//  Created by Greg Hulands on 28/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKTransferController.h"
#import "CKTransferProgressCell.h"
#import "KTLog.h"
#import "NSObject+Connection.h"
#import "NSString+Connection.h"
#import "CKTransferRecord.h"
#import "FileConnection.h"
#import "RunLoopForwarder.h" 
#import "SFTPConnection.h"

NSString *ControllerDomain = @"Controller";
NSString *CKTransferControllerDomain = @"CKTransferControllerDomain";

@interface CKTransferController (Private)
- (CKTransferRecord *)recordWithPath:(NSString *)path root:(CKTransferRecord *)root;
@end

@implementation CKTransferController

- (id)init
{
	if ((self = [super init]))
	{
		myTransfers = [[NSMutableArray alloc] initWithCapacity:8];
		myRootedTransfers = [[NSMutableArray alloc] initWithCapacity:8];
		myPathsToVerify = [[NSMutableSet alloc] init];
		[NSBundle loadNibNamed:@"CKTransferController" owner:self];
		myForwarder = [[RunLoopForwarder alloc] init];
		myFlags.finishedContentGeneration = NO;
	}
	return self;
}

- (void)dealloc
{
	if ([myConnection delegate] == self) [myConnection setDelegate:nil];
	[myConnection release];
	[myVerificationConnection forceDisconnect]; 
	[myVerificationConnection release];
	[myTransfers release];
	[myForwarder setDelegate:nil];
	[myForwarder release];
	[myRootPath release];
	[myRootedTransfers release];
	[myPathsToVerify release];
	
	[super dealloc];
}

- (void)awakeFromNib
{
	CKTransferProgressCell *cell = [[CKTransferProgressCell alloc] init];
	[[oFiles tableColumnWithIdentifier:@"progress"] setDataCell:cell];
	[cell release];
	[oFiles setIndentationMarkerFollowsCell:YES];
	[oFiles setDataSource:self];
	[oFiles setDelegate:self];
	
	[oTitle setStringValue:@""];
	
	[oStatus setStringValue:@""];
	[oProgress setIndeterminate:YES];
	[oProgress setUsesThreadedAnimation:YES];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(progressChanged:)
												 name:CKTransferRecordProgressChangedNotification
											   object:nil];
	
}

- (void)progressChanged:(NSNotification *)n
{	
	if ([oShowFiles state] == NSOnState)
	{
		[oFiles performSelectorOnMainThread:@selector(reloadData)
								 withObject:nil
							  waitUntilDone:NO];
	}
	unsigned long long totalBytes = 0;
	unsigned long long totalTransferred = 0;
	NSEnumerator *e = [myTransfers objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		totalBytes += [cur size];
		totalTransferred += [cur transferred];
	}
	
	double prog = ((double)totalTransferred * 1.0) / ((double)totalBytes * 1.0);
	[oProgress setDoubleValue:prog];
	
	if (myFlags.verifyTransfers)
	{
		CKTransferRecord *enclosedFolder = [(CKTransferRecord *)[n object] parent];
		if ([[enclosedFolder progress] intValue] == 100 && nil != [enclosedFolder error])
		{
			KTLog(ControllerDomain, KTLogDebug, @"Verifying directory %@", [enclosedFolder path]);
			[myVerificationConnection contentsOfDirectory:[enclosedFolder path]];
		}
	}
}

- (void)setConnection:(id <AbstractConnectionProtocol>)connection
{
	if ([myConnection delegate] == self) [myConnection setDelegate:nil];
	[myConnection autorelease];
	myConnection = [connection retain];
}

- (id <AbstractConnectionProtocol>)connection
{
	if (!myConnection && myFlags.delegateProvidesConnection)
	{
		id <AbstractConnectionProtocol> con = [myDelegate transferControllerNeedsConnection:self];
		[con setDelegate:self];
		[self setConnection:con];		// cache for next time
		return con;
	}
	return myConnection;
}

- (void)setRootPath:(NSString *)path
{
	if (myRootPath != path)
	{
		[myRootPath autorelease];
		myRootPath = [path copy];
	}
}

- (CKTransferRecord *)recursiveRootRecordWithPath:(NSString *)path root:(CKTransferRecord *)root
{
	NSString *first = [path firstPathComponent];
	
	if ([[root name] isEqualToString:first])
	{
		NSEnumerator *e = [[root contents] objectEnumerator];
		CKTransferRecord *cur;
		path = [path stringByDeletingFirstPathComponent];
		
		if ([path isEqualToString:@"/"])
			return root;
		
		while ((cur = [e nextObject]))
		{
			CKTransferRecord *child = [self recursiveRootRecordWithPath:path root:cur];
			if (child)
				return root;
		}
		
		// if we get here it doesn't exist so create it
		cur = [CKTransferRecord recordWithName:[path firstPathComponent] size:0];
		[root addContent:cur];
		[self recursiveRootRecordWithPath:path root:cur];
		return root;
	}
	return nil;
}

- (CKTransferRecord *)rootRecordWithPath:(NSString *)path
{
	NSEnumerator *e = [myTransfers objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		if ([[cur name] isEqualToString:[path firstPathComponent]])
		{
			// walk the tree to make sure all folders are created
			return [self recursiveRootRecordWithPath:path root:cur];
		}
	}
	if (!cur)
	{
		cur = [CKTransferRecord recordWithName:[path firstPathComponent] size:0];
		path = [path stringByDeletingFirstPathComponent];
		CKTransferRecord *thisNode, *subNode = cur;
		
		while ((![path isEqualToString:@"/"]))
		{
			thisNode = [CKTransferRecord recordWithName:[path firstPathComponent] size:0];
			path = [path stringByDeletingFirstPathComponent];
			[subNode addContent:thisNode];
			subNode = thisNode;
		}
		[self willChangeValueForKey:@"transfers"];
		[myTransfers addObject:cur];
		[self didChangeValueForKey:@"transfers"];
		if (myRootPath)
		{
			[myRootedTransfers addObject:[self recordWithPath:myRootPath root:cur]];
		}
		else
		{
			[myRootedTransfers addObject:cur];
		}
		[self performSelectorOnMainThread:@selector(mainThreadTableReload:) withObject:nil waitUntilDone:NO];
	}
	return cur;
}

- (CKTransferRecord *)recursiveRecordWithPath:(NSString *)path root:(CKTransferRecord *)root
{
	NSString *first = [path firstPathComponent];
	
	if ([[root name] isEqualToString:first])
	{
		CKTransferRecord *child = nil;
		NSEnumerator *e = [[root contents] objectEnumerator];
		CKTransferRecord *cur;
		path = [path stringByDeletingFirstPathComponent];
		
		if ([path isEqualToString:@"/"])
			return root;
		
		while ((cur = [e nextObject]))
		{
			child = [self recursiveRecordWithPath:path root:cur];
			if (child)
				return child;
		}
	}
	return nil;
}

- (CKTransferRecord *)recordWithPath:(NSString *)path root:(CKTransferRecord *)root
{
	return [self recursiveRecordWithPath:path root:root];
}

- (CKTransferRecord *)recordWithPath:(NSString *)path
{
	NSEnumerator *e = [myTransfers objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		CKTransferRecord *child = [self recordWithPath:path root:cur];
		if (child)
		{
			return child;
		}
	}
	return nil;
}

- (void)createDirectory:(NSString *)directory
{
	KTLog(ControllerDomain, KTLogDebug, @"Queuing create remote directory: %@", directory);
	[[self connection] createDirectory:directory];
}

- (void)createDirectory:(NSString *)directory permissions:(unsigned long)permissions
{
	KTLog(ControllerDomain, KTLogDebug, @"Queuing create remote directory: %@ (%lo)", directory, permissions);
	[[self connection] createDirectory:directory permissions:permissions];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	KTLog(ControllerDomain, KTLogDebug, @"Queuing upload of file: %@ to %@", localPath, remotePath);
	CKTransferRecord *root = [self rootRecordWithPath:[remotePath stringByDeletingLastPathComponent]];
	CKTransferRecord *upload = [[self connection] uploadFile:localPath toFile:remotePath checkRemoteExistence:NO delegate:nil];
	
	[upload setName:[remotePath lastPathComponent]];
	[[self recordWithPath:[remotePath stringByDeletingLastPathComponent] root:root] addContent:upload];
	[myPathsToVerify addObject:remotePath];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	KTLog(ControllerDomain, KTLogDebug, @"Queuing upload of data to %@", remotePath);
	CKTransferRecord *root = [self rootRecordWithPath:[remotePath stringByDeletingLastPathComponent]];
	CKTransferRecord *upload = [[self connection] uploadFromData:data toFile:remotePath checkRemoteExistence:NO delegate:nil];
	
	[upload setName:[remotePath lastPathComponent]];
	[[self recordWithPath:[remotePath stringByDeletingLastPathComponent] root:root] addContent:upload];
	[myPathsToVerify addObject:remotePath];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)remotePath
{
	KTLog(ControllerDomain, KTLogDebug, @"Queuing permissions %lo to %@", permissions, remotePath);
	[[self connection] setPermissions:permissions forFile:remotePath];
}

- (void)deleteFile:(NSString *)remotePath
{
	KTLog(ControllerDomain, KTLogDebug, @"Queuing delete of %@", remotePath); 
	[[self connection] deleteFile:remotePath];
}

- (void)setContentGeneratedInSeparateThread:(BOOL)flag
{
	myFlags.useThread = flag;
}

- (BOOL)contentGeneratedInSeparateThread
{
	return myFlags.useThread;
}

- (void)setVerifyTransfers:(BOOL)flag
{
	myFlags.verifyTransfers = flag;
}

- (BOOL)verifyTransfers
{
	return myFlags.verifyTransfers;
}

- (void)setDelegate:(id)delegate
{
	myDelegate = delegate;
	[myForwarder setDelegate:myDelegate];
	
	myFlags.delegateProvidesConnection = [delegate respondsToSelector:@selector(transferControllerNeedsConnection:)];
	myFlags.delegateProvidesContent = [delegate respondsToSelector:@selector(transferControllerNeedsContent:)];
	myFlags.delegateFinishedContentGeneration = [delegate respondsToSelector:@selector(transferControllerFinishedContentGeneration:)];
	myFlags.delegateHandlesDefaultButton = [delegate respondsToSelector:@selector(transferControllerDefaultButtonAction:)];
	myFlags.delegateHandlesAlternateButton = [delegate respondsToSelector:@selector(transferControllerAlternateButtonAction:)];
	myFlags.delegateDidFinish = [delegate respondsToSelector:@selector(transferControllerDidFinish:returnCode:)];
}

- (id)delegate
{
	return myDelegate;
}

- (void)setTitle:(NSString *)title
{
	[oTitle performSelectorOnMainThread:@selector(setStringValue:) 
							 withObject:title
						  waitUntilDone:NO];
	[[self window] setTitle:title];
}

- (void)setIcon:(NSImage *)icon
{
	[oIcon setImage:icon];
}

- (void)mainThreadSetStatus:(NSString *)message
{
	[oStatus setStringValue:message];
}

- (void)setStatusMessage:(NSString *)message
{
	[self performSelectorOnMainThread:@selector(mainThreadSetStatus:) 
						   withObject:message
						waitUntilDone:NO];
}

- (void)setProgress:(double)progress
{
	if (progress > 0)
	{
		[oProgress setIndeterminate:NO];
		[oProgress setDoubleValue:progress];
	}
	else
	{
		[oProgress setIndeterminate:YES];
		[oProgress startAnimation:self];
	}
}

- (void)setFinished
{
	[self setProgress:[oProgress maxValue]];
}

- (void)setDefaultButtonTitle:(NSString *)title
{
	[oDefaultButton setTitle:title];
	if (!title || [title isEqualToString:@""])
	{
		[oDefaultButton setHidden:YES];
	}
	else
	{
		[oDefaultButton setImagePosition:NSImageRight];
		[oDefaultButton setKeyEquivalent:@"\r"];
		[oDefaultButton setHidden:NO];
	}
}

- (void)setAlternateButtonTitle:(NSString *)title
{
	[oAlternateButton setTitle:title];
	if (!title || [title isEqualToString:@""])
	{
		[oAlternateButton setHidden:YES];
	}
	else
	{
		[oAlternateButton setHidden:NO];
	}
}

- (void)setUploadingStatusPrefix:(NSString *)prefix
{
	if (prefix != myUploadingPrefix)
	{
		[myUploadingPrefix autorelease];
		myUploadingPrefix = [prefix copy];
	}
}

- (void)kickoff:(id)unused
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	myFlags.stopTransfer = NO;
	
	[self setStatusMessage:LocalizedStringInThisBundle(@"Generating Content...", @"message")];
	
	if (myFlags.delegateProvidesContent)
	{
		// don't use the forwarder as we want to be called on the current thread
		@try {
			[myDelegate transferControllerNeedsContent:self];
		}
		@catch (NSException *ex) {
			KTLog(ControllerDomain, KTLogDebug, @"Exception caught in kickoff: %@", ex);
		}
	}
	
	myFlags.finishedContentGeneration = YES;
		
	[self performSelectorOnMainThread:@selector(finishedKickOff:) withObject:nil waitUntilDone:NO];
	
	if (myFlags.stopTransfer)
	{
		[[self connection] setDelegate:nil];
		[[self connection] forceDisconnect];
	}
	else
	{
		if (myFlags.delegateFinishedContentGeneration)
		{
			[myForwarder transferControllerFinishedContentGeneration:self];
		}
		myStatus = CKSuccessStatus;		// We have all the content, so we should be OK to set success now. 
		[[self connection] disconnect];
		
		// let the runloop run incase anyone is using it... like FileConnection. 
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantPast]];
	}
	if (myFlags.useThread)
	{
		KTLog(ControllerDomain, KTLogDebug, @"kickoff: thread finishing up");
	}
	[pool release];
}

- (void)finishedKickOff:(id)sender
{
	[oProgress setMinValue:0];
	[oProgress setMaxValue:1.0];
	[oProgress setDoubleValue:0];
	[oProgress setIndeterminate:NO];
	[oShowHideFilesTitle setHidden:NO];
	[oShowFiles setHidden:NO];
	KTLog(ControllerDomain, KTLogDebug, @"Set progress bar to determinate");
}

- (void)beginSheetModalForWindow:(NSWindow *)window
{
	KTLog(ControllerDomain, KTLogDebug, @"Beginning modal sheet");
	[myTransfers removeAllObjects];
	[myPathsToVerify removeAllObjects];
	[myRootedTransfers removeAllObjects];
	[oFiles reloadData];
	myStatus = CKErrorStatus;	// assume an error if we didn't get far, like immediate disconnect.

	//make sure sheet is collapsed
	if ([oShowFiles state] != NSOffState)
	{
		[oShowFiles setState:NSOffState];
		[self showHideFiles:oShowFiles];
	}
	[oShowHideFilesTitle setHidden:YES];
	[oShowFiles setHidden:YES];
	
	myFlags.finishedContentGeneration = NO;
	[oStatus setStringValue:@""];
	[oProgress setIndeterminate:YES];
	[oProgress setUsesThreadedAnimation:YES];
	
	[NSApp beginSheet:[self window]
	   modalForWindow:window
		modalDelegate:nil
	   didEndSelector:nil
		  contextInfo:nil];
	
	[oProgress startAnimation:self];
	
	[[self connection] setName:@"main uploader"];
	[[self connection] connect];
	
#warning GREG -- can we make sure to not kick off and gather contents, upload, etc. until we have a verified working connection?

	// temporarily turn off verification for sftp until I can sort out the double connection problem
	if ([[self connection] isKindOfClass:[SFTPConnection class]]) myFlags.verifyTransfers = NO;
	if (!myVerificationConnection && ![[self connection] isKindOfClass:[SFTPConnection class]])
	{
		myVerificationConnection = [[self connection] copy];
		[myVerificationConnection setName:@"verification"];
		[myVerificationConnection setDelegate:self];
		[myVerificationConnection connect];
	}
	
	if (myFlags.useThread)
	{
		[NSThread detachNewThreadSelector:@selector(kickoff:) toTarget:self withObject:nil];
	}
	else
	{
		[self kickoff:nil];
	}
}

- (IBAction)defaultButtonPressed:(id)sender
{
	if (myFlags.delegateHandlesDefaultButton)
	{
		if (![myDelegate transferControllerDefaultButtonAction:self])
			return;
	}
	[myVerificationConnection setDelegate:nil];
	[myVerificationConnection forceDisconnect];
	[myVerificationConnection release]; myVerificationConnection = nil;
	[[self connection] setDelegate:nil];
	[[self connection] forceDisconnect];
	[[NSApplication sharedApplication] endSheet:[self window]];
	[[self window] orderOut:self];
	[myTransfers removeAllObjects];
	[myPathsToVerify removeAllObjects];
	[myRootedTransfers removeAllObjects];
	[oFiles reloadData];
}

- (IBAction)alternateButtonPressed:(id)sender
{
	if (myFlags.delegateHandlesAlternateButton)
	{
		if (![myDelegate transferControllerAlternateButtonAction:self])
			return;
	}
	[myVerificationConnection setDelegate:nil];
	[myVerificationConnection forceDisconnect];
	[myVerificationConnection release]; myVerificationConnection = nil;
	[[self connection] setDelegate:nil];
	[[self connection] forceDisconnect];
	[[NSApplication sharedApplication] endSheet:[self window]];
	[[self window] orderOut:self];
	[myTransfers removeAllObjects];
	[myPathsToVerify removeAllObjects];
	[myRootedTransfers removeAllObjects];
	[oFiles reloadData];
}

static NSSize openedSize = { 452, 489 };
static NSSize closedSize = { 452, 152 };

- (IBAction)showHideFiles:(id)sender
{
	NSRect r = [[self window] frame];
	NSSize newSize = [sender state] == NSOnState ? openedSize : closedSize;
	NSString *name = [sender state] == NSOnState ? LocalizedStringInThisBundle(@"Hide Files", @"transfer controller") : LocalizedStringInThisBundle(@"Show Files", @"transfer controller");
	r.origin.y -= newSize.height - r.size.height;
	r.size = newSize;
	
	[oFiles reloadData];
	[oShowHideFilesTitle setStringValue:name];
	[[self window] setFrame:r display:YES animate:YES];
}

- (IBAction)cancelPassword:(id)sender
{
	
}

- (IBAction)connectPassword:(id)sender
{
	
}

- (NSArray *)transfers
{
	return myTransfers;
}

- (void)mainThreadTableReload:(id)unused
{
	[oFiles reloadData];
}

- (void)stopTransfer:(id)sender
{
	myFlags.stopTransfer = YES;
	myStatus = CKAbortStatus;
}

- (BOOL)hadErrorsTransferring
{
	BOOL ret = NO;
	NSEnumerator *e = [myTransfers objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		if ([cur hasError])
		{
			ret = YES;
			break;
		}
	}
	
	return ret;
}

#pragma mark -
#pragma mark Outline View Data Source

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (item == nil)
	{
		return [myRootedTransfers count];
	}
	return [[item contents] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(int)index ofItem:(id)item
{
	if (item == nil)
	{
		return [myRootedTransfers objectAtIndex:index];
	}
	return [[item contents] objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [item isDirectory];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	NSString *ident = [tableColumn identifier];
	if ([ident isEqualToString:@"progress"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:[item progress], @"progress", [item name], @"name", nil];
	}
	else if ([ident isEqualToString:@"file"])
	{
		return [item name];
	}
	else if ([ident isEqualToString:@"speed"])
	{
		return [NSString formattedSpeed:[item speed]];
	}
	
	return nil;
}

#pragma mark -
#pragma mark Outline View Delegate Methods

- (NSString *)outlineView:(NSOutlineView *)ov 
		   toolTipForCell:(NSCell *)cell 
					 rect:(NSRectPointer)rect 
			  tableColumn:(NSTableColumn *)tc 
					 item:(id)item 
			mouseLocation:(NSPoint)mouseLocation
{
	if ([item error])
	{
		return [[[item error] userInfo] objectForKey:NSLocalizedDescriptionKey];
	}
	return nil;
}

#pragma mark -
#pragma mark Connection Delegate Methods

- (void)connection:(id <AbstractConnectionProtocol>)con didConnectToHost:(NSString *)host
{
	if (con == [self connection])
	{
		[self setStatusMessage:[NSString stringWithFormat:LocalizedStringInThisBundle(@"Connected to %@", @"transfer controller"), host]];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host
{
	if (myFlags.verifyTransfers)
	{
		if (con == [self connection]) 
		{
			// we know if the uploader has disconnected, that the final verification dir would have been queued
			[myVerificationConnection disconnect];
			return;
		}
	}
	else
	{
		if (con != [self connection])
		{
			return;
		}
	}
	[self setStatusMessage:[NSString stringWithFormat:LocalizedStringInThisBundle(@"Disconnected from %@", @"transfer controller"), host]];

	if (CKErrorStatus == myStatus)	// we might have gotten an unexpected disconnect -- bad password for example
	{
		[self setTitle:LocalizedStringInThisBundle(@"Publishing Failed", @"Transfer Controller")];
		[self setStatusMessage:LocalizedStringInThisBundle(@"An error occured.", @"Transfer Controller")];
	}				
	if (myFlags.delegateDidFinish)
	{
		[myForwarder transferControllerDidFinish:self returnCode:myStatus];
	}
} 

- (BOOL)connection:(id <AbstractConnectionProtocol>)con authorizeConnectionToHost:(NSString *)host message:(NSString *)message
{
	NSAlert *alert = [NSAlert alertWithMessageText:LocalizedStringInThisBundle(@"Authorize Connection?", @"authorise")
									 defaultButton:LocalizedStringInThisBundle(@"Authorize", @"authorise")
								   alternateButton:LocalizedStringInThisBundle(@"Cancel", @"authorise")
									   otherButton:nil
						 informativeTextWithFormat:LocalizedStringInThisBundle(@"%@\nWhat would you like to do?", @"authorise"), message];
	
	if ([alert runModal] == NSOKButton)
	{
		return YES;
	}
	return NO;
}

- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveError:(NSError *)error
{
	if ([error code] == ConnectionErrorUploading) 
	{
		NSString *remotePath = [[error userInfo] objectForKey:@"upload"];
		CKTransferRecord *rec = [CKTransferRecord recordForFullPath:remotePath withRoot:[self rootRecordWithPath:remotePath]];
		if (rec != nil) 
		{
			[rec setError:error];
		}
	}
	else if ([[error userInfo] objectForKey:ConnectionDirectoryExistsKey]) 
	{
		return; //don't alert users to the fact it already exists, silently fail
	}
	else if ([error code] == 550 || [[[error userInfo] objectForKey:@"protocol"] isEqualToString:@"createDirectory:"] )
	{
		return;
	}
	else if ([con isKindOfClass:NSClassFromString(@"WebDAVConnection")] && 
			 ([[[error userInfo] objectForKey:@"directory"] isEqualToString:@"/"] || [error code] == 409 || [error code] == 204 || [error code] == 404))
	{
		// web dav returns a 409 if we try to create / .... which is fair enough!
		// web dav returns a 204 if a file to delete is missing.
		// 404 if the file to delete doesn't exist
		
		return;
	}
	else if ([error code] == kSetPermissions) // File connection set permissions failed
	{
		return;
	}
	else
	{
		KTLog(ControllerDomain, KTLogDebug, @"%@ %@", NSStringFromSelector(_cmd), error);
		[[self connection] setDelegate:nil];
		[[self connection] forceDisconnect];
		
		myStatus = CKErrorStatus;
		
		[self setTitle:LocalizedStringInThisBundle(@"Publishing Failed", @"Transfer Controller")];
		[self setStatusMessage:LocalizedStringInThisBundle(@"An error occured.", @"Transfer Controller")];
		
		[oProgress setIndeterminate:NO];
		[oProgress setDoubleValue:0.0];
		[oProgress displayIfNeeded];
		[oAlternateButton setHidden:YES];
		[oDefaultButton setTitle:LocalizedStringInThisBundle(@"Close", @"Close")];
		[oDefaultButton setImagePosition:NSImageRight];
		[oDefaultButton setKeyEquivalent:@"\r"];
		[oDefaultButton setHidden:NO];
		
		[myForwarder transferControllerDidFinish:self returnCode:myStatus];
		
		NSAlert *a = [NSAlert alertWithError:error];
		[a runModal];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidBegin:(NSString *)remotePath
{
	NSMutableString *msg = [NSMutableString string];
	if (myUploadingPrefix)
	{
		[msg appendString:myUploadingPrefix];
	}
	else
	{
		[msg appendString:LocalizedStringInThisBundle(@"Uploading", @"status message")];
	}
	[msg appendFormat:@" %@", [remotePath lastPathComponent]];
	[self setStatusMessage:msg];
}

- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath
{
	CKTransferRecord *folder = [self recordWithPath:dirPath];
	NSEnumerator *e = [[folder contents] objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		if (![cur isDirectory])
		{
			NSEnumerator *g = [contents objectEnumerator];
			NSDictionary *file;
			BOOL didFind = NO;
			while ((file = [g nextObject]))
			{
				NSString *filename = [file objectForKey:cxFilenameKey];
				if ([filename isEqualToString:[cur name]])
				{
					[myPathsToVerify removeObject:[cur path]];
					didFind = YES;
					
					if ([[file objectForKey:NSFileSize] unsignedLongLongValue] > 0)
					{
						KTLog(ControllerDomain, KTLogDebug, @"Verified file transferred %@", [cur path]);
						break;
					}
					else
					{
						KTLog(ControllerDomain, KTLogDebug, @"ERROR 0 file size %@", [cur path]);
						NSString *msg = [NSString stringWithFormat:LocalizedStringInThisBundle(@"The transferred file has a size of 0.", @"error transferring"), [cur path]]; 
						NSError *error = [NSError errorWithDomain:CKTransferControllerDomain
															 code:CKFailedVerificationError
														 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:msg, NSLocalizedDescriptionKey, nil]];
						[cur setError:error];
					}
				}
			}
			if (!didFind)
			{
				KTLog(ControllerDomain, KTLogDebug, @"Failed to verify file transferred %@", [cur path]);
				NSString *msg = [NSString stringWithFormat:LocalizedStringInThisBundle(@"Failed to verify file transferred successfully", @"error transferring")]; 
				NSError *error = [NSError errorWithDomain:CKTransferControllerDomain
													 code:CKFailedVerificationError
												 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:msg, NSLocalizedDescriptionKey, nil]];
				[cur setError:error];
			}
		}
	}
}

@end

@interface CKOutlineView : NSOutlineView
{
	NSLock *myLock;
}
@end

@implementation CKOutlineView

- (id)initWithFrame:(NSRect)frame
{
	if ((self != [super initWithFrame:frame]))
	{
		[self release];
		return nil;
	}
	myLock = [[NSLock alloc] init];
	return self;
}

- (void)release
{
	[myLock release];
	[super dealloc];
}

- (void)reloadData
{
	if (![myLock tryLock])
	{
		[self performSelector:@selector(reloadData) withObject:nil afterDelay:0.0];
		return;
	}
	[super reloadData];
	[myLock unlock];
}

@end


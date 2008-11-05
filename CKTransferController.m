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


#import "CKTransferController.h"
#import "CKTransferProgressCell.h"
#import "KTLog.h"
#import "NSObject+Connection.h"
#import "NSString+Connection.h"
#import "CKTransferRecord.h"
#import "FileConnection.h"
#import "RunLoopForwarder.h"
#import "FTPConnection.h"
#import "SFTPConnection.h"
#import "InterThreadMessaging.h"

NSString *ControllerDomain = @"Controller";
NSString *CKTransferControllerDomain = @"CKTransferControllerDomain";

@interface CKTransferController (Private)
- (CKTransferRecord *)recordWithPath:(NSString *)path root:(CKTransferRecord *)root;
- (CKTransferRecord *)rootRecordWithPath:(NSString *)path;
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
	}
	return self;
}

- (void)dealloc
{
	[myTransfers release];
	[myForwarder setDelegate:nil];
	[myForwarder release];
	[myRootPath release];
	[myRootedTransfers release];
	[myPathsToVerify release];
	[self forceDisconnectAll];	// won't send delegate message
	
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

#pragma mark -
#pragma mark Operations

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
	NSAssert(remotePath && ![remotePath isEqualToString:@""], @"no file/path specified");
	[[self connection] setPermissions:permissions forFile:remotePath];
}

- (void)deleteFile:(NSString *)remotePath
{
	KTLog(ControllerDomain, KTLogDebug, @"Queuing delete of %@", remotePath); 
	[[self connection] deleteFile:remotePath];
}

- (void)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath
{
	CKTransferRecord *root = [self rootRecordWithPath:[remotePath stringByDeletingLastPathComponent]];
	CKTransferRecord *upload = [[self connection] recursivelyUpload:localPath to:remotePath];
	
	[upload setName:[remotePath lastPathComponent]];
	[[self recordWithPath:[remotePath stringByDeletingLastPathComponent] root:root] addContent:upload];
	[myPathsToVerify addObject:remotePath];
}

#pragma mark -
#pragma mark UI

- (void)setTitle:(NSString *)title
{
	[[self window] setTitle:title];
	[oTitle performSelectorOnMainThread:@selector(setStringValue:) 
							 withObject:title
						  waitUntilDone:YES];
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

#pragma mark -
#pragma mark Control Flow

- (void)kickoff:(id)unused
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[NSThread prepareForConnectionInterThreadMessages]; //make sure we have a runloop on this thread
	
	myPhase = CKKickoffPhase;
	myFlags.stopTransfer = NO;
	
	BOOL contentGenerationSuccessful = YES;	// will be set to NO if provider had error or abort
	if (myFlags.delegateProvidesContent)
	{
		// don't use the forwarder as we want to be called on the current thread
		@try {
			myPhase = CKContentGenerationPhase;
			contentGenerationSuccessful = [myDelegate transferControllerNeedsContent:self];
		}
		@catch (NSException *ex) {
			KTLog(ControllerDomain, KTLogDebug, @"Exception caught in kickoff: %@", ex);
		}
	}
	
	myPhase = CKFinishedContentGenerationPhase;
	
	// adjust UI on main thread
	[self performSelectorOnMainThread:@selector(finishedKickOff:) withObject:nil waitUntilDone:NO];
	
	if (myFlags.stopTransfer || CKFatalErrorStatus == myReturnStatus)
	{
		[self forceDisconnectAll];
		
		// Tell client that it should finish
		if (myFlags.delegateFinishedContentGeneration)
		{
			[myForwarder transferControllerFinishedContentGeneration:self completed:NO];
		}
			
		if (myFlags.delegateDidFinish)
		{
			[myForwarder transferControllerDidFinish:self returnCode:myReturnStatus];
		}
		[self forceDisconnectAll];
	}
	else
	{
		if (myFlags.delegateFinishedContentGeneration)
		{
			[myForwarder transferControllerFinishedContentGeneration:self completed:contentGenerationSuccessful];
		}
		myReturnStatus = CKSuccessStatus;		// We have all the content, so we should be OK to set success now. 
		[[self connection] disconnect];
		
		// let the runloop run incase anyone is using it... like FileConnection. 
		//
		// No longer needed, greg says...  Need to test to make sure
		// [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantPast]];
	}
	if (myFlags.useThread)
	{
		KTLog(ControllerDomain, KTLogDebug, @"kickoff: thread finishing up");
	}
	[pool release];
}

- (void)finishedKickOff:(id)sender
{
	if (myReturnStatus != CKFatalErrorStatus)
	{
		[oShowHideFilesTitle setHidden:NO];
		[oShowFiles setHidden:NO];
	}
	[oProgress setMinValue:0];
	[oProgress setMaxValue:1.0];
	[oProgress setDoubleValue:0];
	[oProgress setIndeterminate:NO];
	
	KTLog(ControllerDomain, KTLogDebug, @"Set progress bar to determinate");
}

- (void)setupForDisplay
{
	myPhase = CKInitialPhase;
	myReturnStatus = CKUnknownStatus;	// assume an error if we didn't get far, like immediate disconnect.
	myConnectionStatus = CKNotConnectedStatus;

	KTLog(ControllerDomain, KTLogDebug, @"Beginning modal sheet");
	[myTransfers removeAllObjects];
	[myPathsToVerify removeAllObjects];
	[myRootedTransfers removeAllObjects];
	[oFiles reloadData];

	//make sure sheet is collapsed
	if ([oShowFiles state] != NSOffState)
	{
		[oShowFiles setState:NSOffState];
		[self showHideFiles:oShowFiles];
	}
	[oShowHideFilesTitle setHidden:YES];
	[oShowFiles setHidden:YES];
	
	[oStatus setStringValue:@""];
	[oProgress setIndeterminate:YES];
	[oProgress setUsesThreadedAnimation:YES];
}

- (void)finishSetupForDisplay
{
	[oProgress startAnimation:self];
	
	[[self connection] setName:@"main uploader"];
	[[self connection] connect];
	
	if (myFlags.waitForConnection)
	{
		// Run some runloops for a while, waiting for a change in state.  Is this a good way to do it?
		// I can't figure out what the return value of runMode:beforeDate: is and how to use it.
		// Should the give-up date be an absolute time like it is now, or n seconds relative to each
		// run loop invocation?
		
		NSDate *giveUp = [NSDate dateWithTimeIntervalSinceNow:5.0];
		while (CKNotConnectedStatus == myConnectionStatus)
		{
			// let the runloop run incase anyone is using it... like FileConnection. 
			(void) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:giveUp];
			NSDate *now = [NSDate date];
			if (NSOrderedDescending == [now compare:giveUp])
			{
				break;	// give up, keep going, hopefully we are OK if we missed a message.
			}
		}
	}
	if (CKDisconnectedStatus != myConnectionStatus)	// don't proceed if we already had an error connecting
	{
		// temporarily turn off verification for sftp until I can sort out the double connection problem
		if ([[self connection] isKindOfClass:[SFTPConnection class]]) myFlags.verifyTransfers = NO;
		
		/// temporarily turn off FTP verification too  just for simplification
		if ([[self connection] isKindOfClass:[FTPConnection class]]) myFlags.verifyTransfers = NO;

		if (!myVerificationConnection && myFlags.verifyTransfers)
		{
			myVerificationConnection = [[self connection] copyWithZone:[self zone]];
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
}

- (void)runModal
{
	[self setupForDisplay];
	[NSApp runModalForWindow:[self window]];
	[self finishSetupForDisplay];
}

- (void)beginSheetModalForWindow:(NSWindow *)window
{
	[self setupForDisplay];
	
	[NSApp beginSheet:[self window]
	   modalForWindow:window
		modalDelegate:nil
	   didEndSelector:nil
		  contextInfo:nil];
	
	[self finishSetupForDisplay];
}

- (void) postABogusEvent
{
	// Post an event to help the runloop waiting for a connection
	NSEvent *theEvent = [NSEvent otherEventWithType:NSApplicationDefined
										   location:NSZeroPoint
									  modifierFlags:0
										  timestamp:0.0
									   windowNumber:0
											context:[NSApp context]
											subtype:0
											  data1:0
											  data2:0];
	[NSApp postEvent:theEvent atStart:YES];
}	

#pragma mark -
#pragma mark Actions

- (IBAction)defaultButtonPressed:(id)sender
{
	if (myFlags.delegateHandlesDefaultButton)
	{
		if (![myDelegate transferControllerDefaultButtonAction:self])
			return;
	}
	
	// Treat as stop/done?  Or will it be different when we are done?
	[self stopTransfer];
	
	[[NSApplication sharedApplication] stopModal];
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
	
	NSBeep();	// second button really isn't defined without delegate
}

static NSSize openedSize = { 452, 489 };
static NSSize closedSize = { 452, 152 };

- (IBAction)showHideFiles:(id)sender
{
	NSRect r = [[self window] frame];
	BOOL showing = [sender state] == NSOnState;
	NSSize newSize = showing ? openedSize : closedSize;
	NSString *name = showing ? LocalizedStringInConnectionKitBundle(@"Hide Files", @"transfer controller") : LocalizedStringInConnectionKitBundle(@"Show Files", @"transfer controller");
	r.origin.y -= newSize.height - r.size.height;
	r.size = newSize;
	
	[oFiles reloadData];
	if (showing)		// initially expand the first level
	{
		NSEnumerator *e = [myRootedTransfers objectEnumerator];
		CKTransferRecord *cur;
		
		while ((cur = [e nextObject]))
		{
			[oFiles expandItem:cur expandChildren:NO];
		}
	}
	[oShowHideFilesTitle setStringValue:name];
	[[self window] setFrame:r display:YES animate:YES];
}

- (IBAction)cancelPassword:(id)sender
{
	// Is this just not implemented yet?
}

- (IBAction)connectPassword:(id)sender
{
	// Is this just not implemented yet?
}

#pragma mark -
#pragma mark Accessors

// set a connection.  Generally called when this class maintains its collection.
// If delegate provides collection, then we do not deal with retaining.

- (void)setConnection:(id <AbstractConnectionProtocol>)connection
{
	if ([myConnection delegate] == self) [myConnection setDelegate:nil];
	if (!myFlags.delegateProvidesConnection)
	{
		[myConnection autorelease];
		myConnection = [connection retain];
	}
	else	// weak reference
	{
		myConnection = connection;
	}
}

- (id <AbstractConnectionProtocol>)connection
{
	if (!myConnection && myFlags.delegateProvidesConnection)
	{
		// delegate returns a connection; we do not retain it.
		id <AbstractConnectionProtocol> con = [myDelegate transferControllerNeedsConnection:self createIfNeeded:YES];
		[con setDelegate:self];
		return con;
	}
	return myConnection;
}

- (id <AbstractConnectionProtocol>)connectionIfAleadyCreated
{
	if (!myConnection && myFlags.delegateProvidesConnection)
	{
		id <AbstractConnectionProtocol> con = [myDelegate transferControllerNeedsConnection:self createIfNeeded:NO];
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

- (void)setContentGeneratedInSeparateThread:(BOOL)flag
{
	myFlags.useThread = flag;
}

- (BOOL)contentGeneratedInSeparateThread
{
	return myFlags.useThread;
}

- (void)setWaitForConnection:(BOOL)flag
{
	myFlags.waitForConnection = flag;
}

- (BOOL)waitForConnection
{
	return myFlags.waitForConnection;
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
	
	myFlags.delegateProvidesConnection			= [delegate respondsToSelector:@selector(transferControllerNeedsConnection:createIfNeeded:)];
	myFlags.delegateProvidesContent				= [delegate respondsToSelector:@selector(transferControllerNeedsContent:)];
	myFlags.delegateFinishedContentGeneration	= [delegate respondsToSelector:@selector(transferControllerFinishedContentGeneration:completed:)];
	myFlags.delegateHandlesDefaultButton		= [delegate respondsToSelector:@selector(transferControllerDefaultButtonAction:)];
	myFlags.delegateHandlesAlternateButton		= [delegate respondsToSelector:@selector(transferControllerAlternateButtonAction:)];
	myFlags.delegateDidFinish					= [delegate respondsToSelector:@selector(transferControllerDidFinish:returnCode:)];
}

- (id)delegate
{
	return myDelegate;
}



- (NSError *)fatalError
{
    return myFatalError; 
}

- (void)setFatalError:(NSError *)aFatalError
{
    [aFatalError retain];
    [myFatalError release];
    myFatalError = aFatalError;
}

- (NSArray *)transfers
{
	return myTransfers;
}


#pragma mark -
#pragma mark Notification

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
		if ([enclosedFolder progress] == 100 && nil != [enclosedFolder error])
		{
			KTLog(ControllerDomain, KTLogDebug, @"Verifying directory %@", [enclosedFolder path]);
			[myVerificationConnection contentsOfDirectory:[enclosedFolder path]];
		}
	}
}

#pragma mark -
#pragma mark Misc

- (void)mainThreadTableReload:(id)unused
{
	[oFiles reloadData];
}

- (void)requestStopTransfer;
{
	myFlags.stopTransfer = YES;
	myReturnStatus = CKAbortStatus;
}

- (void) stopTransfer
{
	[self requestStopTransfer];
	[self forceDisconnectAll];
	if (myFlags.delegateDidFinish)
	{
		[myForwarder transferControllerDidFinish:self returnCode:myReturnStatus];
	}
}


// Return YES if there were problems, collecting stats into the supplied variables
- (BOOL)problemsTransferringCountingErrors:(int *)outErrors successes:(int *)outSuccesses;
{
	NSEnumerator *e = [myTransfers objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		(void) [cur problemsTransferringCountingErrors:outErrors successes:outSuccesses];
	}
	return (*outErrors > 0);
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
		/// TJT: changed conditional here: we have to not process 0 length strings, too!
		if ( (nil != myRootPath) && ([myRootPath length] > 0) )
		{
			CKTransferRecord *record = [self recordWithPath:myRootPath root:cur];
			if ( nil == record )
			{
				/// TJT: this seems to the source of the infamous "attempt to add nil object" exception
				/// TJT: myRootPath is a 0 length string
				NSLog(@"error: recordWithPath:root: returned nil myRootPath=%@ cur=%@", myRootPath, cur);
			}
			else
			{
				[myRootedTransfers addObject:record];
			}
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
	/// TJT: passing in a path of / is going to return nil
	/// so let's not do that, returning nil is a bad idea
	if ([path isEqualToString:@"/"])
		return root;

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
	
	/// TJT: returning nil here seems to be a really bad idea
	/// (we get "attempt to add nil object" exception downstream)
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

- (void)forceDisconnectAll	// possibly called from backgrond thread, can't use myForwarder
{
	// don't use [self connection] because we don't want to create a connection if we've already cleared it
	if ([myConnection delegate] == self)				[myConnection setDelegate:nil];
	
	[[self connectionIfAleadyCreated] setDelegate:nil];
	[[self connectionIfAleadyCreated] forceDisconnect];	// what if we have multiple connections provided by the delegate?

	[myVerificationConnection setDelegate:nil];
	[myVerificationConnection forceDisconnect];
	
	// Release connections
	[self setConnection:nil];	// will only deallocate if it's not a weak ref
	[myVerificationConnection release]; myVerificationConnection = nil;
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
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:[item progress]], @"progress", [item name], @"name", nil];
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
					 item:(id)item	// CKTransferRecord
			mouseLocation:(NSPoint)mouseLocation
{
	if ([item error])
	{
		return [[[item error] userInfo] objectForKey:NSLocalizedDescriptionKey];
	}
	else if (nil != item)
	{
		return [NSString formattedFileSize:(double)[((CKTransferRecord *)item) size]];
	}
	return nil;
}

#pragma mark -
#pragma mark Connection Delegate Methods

- (void)connectionDidSendBadPassword:(id <AbstractConnectionProtocol>)con
{
	if (con == [self connection])
	{
		KTLog(ControllerDomain, KTLogDebug, @"Bad Password for main connection");
		[oProgress setIndeterminate:NO];
		[oProgress setDoubleValue:0.0];
		[oProgress displayIfNeeded];
		
		NSError *error = [NSError errorWithDomain:CKTransferControllerDomain
											 code:CKPasswordError
										 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
											 LocalizedStringInConnectionKitBundle(@"Bad Password.", @"Transfer Controller"), NSLocalizedDescriptionKey, nil]];
		[self setFatalError:error];
		myReturnStatus = CKFatalErrorStatus;
		[self setStatusMessage:LocalizedStringInConnectionKitBundle(@"Password was not accepted.", @"")];
		
		myConnectionStatus = CKDisconnectedStatus;	// so that we know connection didn't happen
		[self forceDisconnectAll];
		if (myFlags.delegateDidFinish)
		{
			[myForwarder transferControllerDidFinish:self returnCode:myReturnStatus];
		}
		[self postABogusEvent];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didConnectToHost:(NSString *)host
{
	if (con == [self connection])
	{
		KTLog(ControllerDomain, KTLogDebug, @"Did Connect to Host");
		myConnectionStatus = CKConnectedStatus;
		[self postABogusEvent];
		
		[self setStatusMessage:[NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Connected to %@", @"transfer controller"), host]];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host
{
	if (con == [self connection])
	{
		myConnectionStatus = CKDisconnectedStatus;
		[self postABogusEvent];
	}

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
	[self setStatusMessage:[NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Disconnected from %@", @"transfer controller"), host]];

	if (myFlags.delegateDidFinish)
	{
		myPhase = CKDonePhase;
		
		// Before sending the callback, check to see if we actually uploaded most of the files.  If not,
		// then consider it a fatal error.
		if (CKSuccessStatus == myReturnStatus)
		{
			int countErrorUploads = 0;
			int countSuccessUploads = 0;
			BOOL hadErrors = [self problemsTransferringCountingErrors:&countErrorUploads successes:&countSuccessUploads];
// if this fraction (or more) of files had an error, consider it a problem uploading.
#define ERROR_THRESHOLD 0.20
			if (hadErrors && (float)countErrorUploads >= (ERROR_THRESHOLD * (float)countSuccessUploads) )
			{
				NSError *error = [NSError errorWithDomain:CKTransferControllerDomain
													 code:CKTooManyErrorsError
												 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
LocalizedStringInConnectionKitBundle(@"Too many files had transfer problems", @"Transfer Controller"), NSLocalizedDescriptionKey, nil]];
			
				[self setFatalError:error];
				myReturnStatus = CKFatalErrorStatus;
				
				[oProgress setIndeterminate:NO];
				[oProgress setDoubleValue:0.0];
				[oProgress displayIfNeeded];
			}
		}
		[myForwarder transferControllerDidFinish:self returnCode:myReturnStatus];
	}
} 

- (BOOL)connection:(id <AbstractConnectionProtocol>)con authorizeConnectionToHost:(NSString *)host message:(NSString *)message
{
	NSAlert *alert = [NSAlert alertWithMessageText:LocalizedStringInConnectionKitBundle(@"Authorize Connection?", @"authorise")
									 defaultButton:LocalizedStringInConnectionKitBundle(@"Authorize", @"authorise")
								   alternateButton:LocalizedStringInConnectionKitBundle(@"Cancel", @"authorise")
									   otherButton:nil
						 informativeTextWithFormat:LocalizedStringInConnectionKitBundle(@"%@\nWhat would you like to do?", @"authorise"), message];
	
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
	else if ([error code] == kSetPermissions) // File connection set permissions failed ... ignore this (why?)
	{
		return;
	}
	else
	{
		KTLog(ControllerDomain, KTLogDebug, @"%@ %@", NSStringFromSelector(_cmd), error);
		
		[self setFatalError:error];
		myReturnStatus = CKFatalErrorStatus;
		
		[oProgress setIndeterminate:NO];
		[oProgress setDoubleValue:0.0];
		[oProgress displayIfNeeded];
		
		[self forceDisconnectAll];
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
		[msg appendString:LocalizedStringInConnectionKitBundle(@"Uploading", @"status message")];
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
						NSString *msg = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"The transferred file has a size of 0.", @"error transferring"), [cur path]]; 
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
				NSString *msg = [NSString stringWithFormat:LocalizedStringInConnectionKitBundle(@"Failed to verify file transferred successfully", @"error transferring")]; 
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


#import "DropletController.h"

@interface DropletController (Private)
- (void)startUpload;
@end

static NSSize sFilesExpandedSize = {375, 400};
static NSSize sFilesCollapsedSize = {375, 105};

@implementation DropletController

- (void)dealloc
{
	[myConnection release];
	[myFilesDropped release];
	[myHost release];
	[myTransfers release];
	
	[super dealloc];
}

- (void)awakeFromNib
{
	NSString *str = [[NSUserDefaults standardUserDefaults] objectForKey:[oWindow frameAutosaveName]];
	if (str)
	{
		[oWindow setFrame:NSRectFromString(str) display:NO];
	}
	NSNumber *state = [[NSUserDefaults standardUserDefaults] objectForKey:@"DisplayFiles"];
	if ([state boolValue])
	{
		[oToggleFiles setState:NSOnState];
	}
	myTransfers = [[NSMutableArray array] retain];
	[oFiles setDelegate:self];
	[oFiles setDataSource:self];
	CKTransferProgressCell *cell = [[CKTransferProgressCell alloc] init];
	[[[oFiles tableColumns] objectAtIndex:0] setDataCell:cell];
	[cell release];

	NSArray *args = [[NSProcessInfo processInfo] arguments];
	if ([args count] < 2)
	{
		NSRunAlertPanel(NSLocalizedString(@"Bad Configuration", @"config"),
						NSLocalizedString(@"No configuration file specified", @"config"),
						NSLocalizedString(@"Quit", @"config"),
						nil,
						nil);
		[NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
		return;
	}
	NSString *configurationFile = [args objectAtIndex:1];
	myFilesDropped = [[args subarrayWithRange:NSMakeRange(2,[args count] - 2)] retain];
	
	if (![[NSFileManager defaultManager] fileExistsAtPath:configurationFile])
	{
		NSRunAlertPanel(NSLocalizedString(@"Bad Configuration", @"config"),
						NSLocalizedString(@"Couldn't find configuration file specified\n %@", @"config"),
						NSLocalizedString(@"Quit", @"config"),
						nil,
						nil, configurationFile);
		[NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
		return;
	}
	myHost = [[NSKeyedUnarchiver unarchiveObjectWithFile:configurationFile] retain];
	if (![myHost password])
	{
		NSString *str = [NSString stringWithFormat:[oPasswordText stringValue], [myHost host], [myHost connectionType]];
		[oPasswordText setStringValue:str];
		[oPasswordPanel center];
		[NSApp activateIgnoringOtherApps:YES];
		[oPasswordPanel makeKeyAndOrderFront:self];
	}
	else
	{
		[self startUpload];
	}
}

- (void)startUpload
{
	[oProgressBar setIndeterminate:YES];
	[oProgressBar setUsesThreadedAnimation:YES];
	[oStatus setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Connecting to %@", @"connection string"), [myHost host]]];
	[NSApp activateIgnoringOtherApps:YES];
	[oWindow makeKeyAndOrderFront:self];
	[oProgressBar startAnimation:self];
	myConnection = [[myHost connection] retain];
	[myConnection setDelegate:self];
	[myConnection connect];
	
	// queue up the transfers
	NSEnumerator *e = [myFilesDropped objectEnumerator];
	NSString *cur;
	
	while ((cur = [e nextObject]))
	{
		CKTransferRecord *root = [myConnection recursivelyUpload:cur to:[myHost initialPath]];
		CKTransferRecord *record = [CKTransferRecord recursiveRecord:root forFullPath:[[myHost initialPath] stringByAppendingPathComponent:[cur lastPathComponent]]];
		[myTransfers addObject:record];
	}
	[oFiles reloadData];
	
	// expand the root items
	e = [myTransfers objectEnumerator];
	CKTransferRecord *rec;
	
	while ((rec = [e nextObject]))
	{
		[oFiles expandItem:rec expandChildren:YES];
	}
	
	// disconnect
	[myConnection disconnect];
}

- (IBAction)cancelPassword:(id)sender
{
	[oPasswordPanel orderOut:self];
	[NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
}

- (IBAction)cancelUpload:(id)sender
{
	[oWindow orderOut:self];
	[NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
}

- (IBAction)connectPassword:(id)sender
{
	[myHost setPassword:[oPassword stringValue]];
	[oPasswordPanel orderOut:self];
	[self startUpload];
}

- (IBAction)toggleFiles:(id)sender
{
	NSRect frame = [oWindow frame];
	NSRect contentRect = [oWindow contentRectForFrameRect:frame];
	float titlebarHeight = NSHeight(frame) - NSHeight(contentRect);
	NSSize newSize = [sender state] == NSOnState ? sFilesExpandedSize : sFilesCollapsedSize;
	frame.origin.y -= newSize.height - contentRect.size.height;
	frame.size = newSize;
	frame.size.height += titlebarHeight;
	
	[oWindow setFrame:frame display:YES animate:YES];
	
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:[sender state] == NSOnState]
											  forKey:@"DisplayFiles"];
}

- (void)notifyGrowlOfSuccessfulUpload
{
	NSString *dropletName = [[NSProcessInfo processInfo] processName];
	NSString *scriptSource = [NSString stringWithFormat:@"tell application \"System Events\"\n"
		"set growlIsRunning to count of (every process whose name is \"GrowlHelperApp\") > 0\n"
		"end tell\n"
		"if growlIsRunning\n"
		"tell application \"GrowlHelperApp\"\n"
		"set the allNotificationsList to {\"Upload Complete\"}\n"
		"set the enabledNotificationsList to {\"Upload Complete\"}\n"
		"register as application \"Connection Droplet\" all notifications allNotificationsList default notifications enabledNotificationsList icon of application \"%@\"\n"
		"notify with name \"Upload Complete\" title \"Upload Complete\" description \"The items have been uploaded successfully.\" application name \"Connection Droplet\"\n"
		"end tell\n"		
		"end if\n", dropletName];
	NSDictionary *errorDictionary;
	NSAppleEventDescriptor *returnDescriptor = nil;
	
	NSAppleScript *applescript = [[NSAppleScript alloc] initWithSource:scriptSource];
	returnDescriptor = [applescript executeAndReturnError:&errorDictionary];
	if (!returnDescriptor)
	{
		//error
		NSLog(@"Applescript Error for Droplet Growl Notification: %@", errorDictionary);
	}
	[applescript release];
}

#pragma mark -
#pragma mark NSWindow Delegate Methods

- (BOOL)windowShouldClose:(id)sender
{
	if (NSRunAlertPanel(NSLocalizedString(@"Stop Upload?", @"close window"),
						NSLocalizedString(@"Are you sure you want to stop the upload?", @"close window"),
						NSLocalizedString(@"Continue Upload", @"close window"),
						NSLocalizedString(@"Stop Upload", @"close window"),
						nil) != NSOKButton)
	{
		[myConnection setDelegate:nil];
		[myConnection forceDisconnect];
		return YES;
	}
	return NO;
}

- (void)windowWillClose:(NSNotification *)aNotification
{
	[NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
}

- (void)windowDidMove:(NSNotification *)aNotification
{
	[[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect([oWindow frame])
											  forKey:[oWindow frameAutosaveName]];
}

#pragma mark -
#pragma mark Connection Delegate Methods

- (BOOL)connection:(id <AbstractConnectionProtocol>)con authorizeConnectionToHost:(NSString *)host message:(NSString *)message
{
	NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Authorize Connection?", @"authorise")
									 defaultButton:NSLocalizedString(@"Authorize", @"authorise")
								   alternateButton:NSLocalizedString(@"Cancel", @"authorise")
									   otherButton:nil
						 informativeTextWithFormat:NSLocalizedString(@"%@\nWhat would you like to do?", @"authorise"), message];
	
	if ([alert runModal] == NSOKButton)
	{
		return YES;
	}
	return NO;
}

- (void)connection:(id <AbstractConnectionProtocol>)con didConnectToHost:(NSString *)host
{
	[oStatus setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Connected to %@", @"connected message"), [myHost host]]];
	
	[oProgressBar setIndeterminate:NO];
	[oProgressBar setMinValue:0];
	[oProgressBar setMaxValue:1.0];
	[oProgressBar setDoubleValue:0.0];
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host
{
	[oStatus setStringValue:NSLocalizedString(@"Disconnected", @"status")];
	[self notifyGrowlOfSuccessfulUpload];
	[NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.5];
}

- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveError:(NSError *)error
{
	if ([[error userInfo] objectForKey:ConnectionDirectoryExistsKey]) 
	{
		return;
	}
	NSLog(@"%@", error);
	NSAlert *a = [NSAlert alertWithError:error];
	[a runModal];
}

//- (NSString *)connection:(id <AbstractConnectionProtocol>)con needsAccountForUsername:(NSString *)username
//{
//	
//}

- (CKTransferRecord *)recordWithPath:(NSString *)path
{
	NSString *chompedPath = [path substringFromIndex:[[myHost initialPath] length]];
	CKTransferRecord *record = nil;
	NSEnumerator *e = [myTransfers objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		record = [CKTransferRecord recursiveRecord:cur forPath:chompedPath];
		if (record)
		{
			return record;
		}
	}
	return nil;
}

- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath progressedTo:(NSNumber *)aPercent
{
	CKTransferRecord *record = [self recordWithPath:remotePath];
	int oldValue = [[record progress] intValue];
	int percent = [aPercent intValue];
	
	if (oldValue == 1 && percent == 100)
	{
		int i;
		for (i = 1; i <= 10; i++) {
			[record setProgress:i*10];
			if ([oToggleFiles state] == NSOnState)
			{
				[oFiles reloadData];
				[oWindow display];
				[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.0125]];
			}
		}
	}
	else if (percent > 0)
	{
		[record setProgress:percent];
		[oFiles reloadData];
	}
	
	// update progress bar
	unsigned long long totalBytes = 0;
	unsigned long long totalTransferred = 0;
	NSEnumerator *e = [myTransfers objectEnumerator];
	CKTransferRecord *cur;
	
	while ((cur = [e nextObject]))
	{
		totalBytes += [cur size];
		totalTransferred += [cur transferred];
	}
	[oProgressBar setDoubleValue:(totalTransferred * 1.0) / (totalBytes * 1.0)];
}

- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidBegin:(NSString *)remotePath
{
	CKTransferRecord *record = [self recordWithPath:remotePath];
	[record setProgress:1];
	
	[oFiles reloadData];
	
	[oStatus setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Uploading %@", @"status"), [record name]]];
}

- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidFinish:(NSString *)remotePath
{
	CKTransferRecord *record = [self recordWithPath:remotePath];
	[record setProgress:100];
	
	[oFiles reloadData];
}

- (void)connectionDidSendBadPassword:(id <AbstractConnectionProtocol>)con
{
	NSLog(@"Bad Password");
}

#pragma mark -
#pragma mark Outline View Data Source Methods

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (item == nil)
	{
		return [myTransfers count];
	}
	return [[item contents] count];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [item isDirectory];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(int)index ofItem:(id)item
{

	if (item == nil)
	{
		return [myTransfers objectAtIndex:index];
	}
	return [[item contents] objectAtIndex:index];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	return [NSDictionary dictionaryWithObjectsAndKeys:[item progress], @"progress", [item name], @"name", nil];
}

#pragma mark -
#pragma mark Outline View Delegate Methods

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	return NO;
}

@end

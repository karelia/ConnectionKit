#import "Controller.h"
#import "ProgressCell.h"
#import "InputDialog.h"
#import "PermissionsController.h"
#import "FileTransfer.h"
#import <Connection/Connection.h>

static NSString *AutoSelect = @"Auto Select";

NSString *TransferTypeKey = @"Type";
NSString *TransferLocalFileKey = @"LocalFile";
NSString *TransferRemoteFileKey = @"RemoteFile";
NSString *TransferControllerKey = @"Controller";
NSString *TransferProgressKey = @"Progress";

int TransferTypeDown = 0;
int TransferTypeUp = 1;

NSString *cxRemoteFilePBoardType = @"cxRemoteFilePBoardType";
NSString *cxLocalFilePBoardType = @"cxLocalFilePBoardType";


//Storing to NSUser Defaults
NSString *HostsKey = @"Hosts";
NSString *HostKey = @"Host";
NSString *PortKey = @"Port";
NSString *UsernameKey = @"Username";
NSString *ConnectionTypeKey = @"Connection";
NSString *URLKey = @"URL";
NSString *InitialDirectoryKey = @"InitialDirectory";
NSString *ProtocolKey = @"Protocol";

@interface Controller(PRivate)
- (void)refreshLocal;
- (void)refreshHosts;
- (void)downloadFile:(NSString *)remote toFolder:(NSString *)local;
- (void)uploadFile:(NSString *)local to:(NSString *)remote;
@end
@interface NSString (FileSizeFormatting)

+ (NSString *)formattedFileSizeWithBytes:(NSNumber *)filesize;
@end

@implementation NSString (FileSizeFormatting)

+ (NSString *)formattedFileSizeWithBytes:(NSNumber *)filesize
{
	static NSString *suffix[] = {
		@"B", @"KB", @"MB", @"GB", @"TB", @"PB", @"EB"
	};
	int i, c = 7;
	long size = [filesize longValue];
	
	for (i = 0; i < c && size >= 1024; i++) {
		size = size / 1024;
	}
	return [NSString stringWithFormat:@"%ld %@", size, suffix[i]];
}

@end

@implementation Controller

- (void)awakeFromNib
{
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	NSString *savedWindowRect = [ud objectForKey:[window frameAutosaveName]];
	if (savedWindowRect)
		[window setFrame:NSRectFromString(savedWindowRect) display:YES];
	BOOL showLog = [ud boolForKey:@"showLog"];
	if (showLog) {
		[logDrawer open:self];
	}
	
	remoteFiles = [[NSMutableArray array] retain];
	localFiles = [[NSMutableArray array] retain];
	transfers = [[NSMutableArray array] retain];
	
	NSArray *conTypes = [AbstractConnection registeredConnectionTypes];
	[cTypePopup removeAllItems];
	[cTypePopup addItemWithTitle:AutoSelect];
	[[cTypePopup menu] addItem:[NSMenuItem separatorItem]];
	[cTypePopup addItemsWithTitles:conTypes];
	
	[localTable setDataSource:self];
	[remoteTable setDataSource:self];
	[transferTable setDataSource:self];
	
	CKTransferProgressCell *cell = [[CKTransferProgressCell alloc] init];
	[[transferTable tableColumnWithIdentifier:@"progress"] setDataCell:cell];
	[cell release];
	
	currentLocalPath = [[NSString stringWithFormat:@"%@", NSHomeDirectory()] copy];
	[self refreshLocal];
	[remotePopup removeAllItems];
	
	[remoteTable setDoubleAction:@selector(remoteDoubleClick:)];
	[localTable setDoubleAction:@selector(localDoubleClick:)];
	
	//drag and drop
	[localTable registerForDraggedTypes:[NSArray arrayWithObject:cxRemoteFilePBoardType]]; //
	[remoteTable registerForDraggedTypes:[NSArray arrayWithObjects:cxLocalFilePBoardType, NSFilenamesPboardType, nil]]; //
	
	[remoteTable setHidden:YES];
	
	[cUser setStringValue:NSUserName()];
	
	//Get saved hosts
	_savedHosts = [[NSMutableArray array] retain];
	
	[_savedHosts addObject:[[[CKBonjourCategory alloc] init] autorelease]];
	
	id hosts = [ud objectForKey:HostsKey];
	if (hosts)
	{
		if ([hosts isKindOfClass:[NSArray class]])
		{
			CKHostCategory *cat = [[CKHostCategory alloc] initWithName:NSLocalizedString(@"Saved Hosts", @"category name")];
			NSEnumerator *e = [hosts objectEnumerator];
			NSDictionary *cur;
			CKHost *h;
			
			while ((cur = [e nextObject]))
			{
				h = [[CKHost alloc] init];
				[h setHost:[cur objectForKey:HostKey]];
				[h setPort:[cur objectForKey:PortKey]];
				[h setUsername:[cur objectForKey:UsernameKey]];
				[h setInitialPath:[cur objectForKey:InitialDirectoryKey]];
				if ([cur objectForKey:URLKey] && ![[cur objectForKey:URLKey] isEqualToString:@""])
				{
					[h setURL:[NSURL URLWithString:[cur objectForKey:URLKey]]];
				}
				[h setConnectionType:[cur objectForKey:ProtocolKey]];
				[cat addHost:h];
				[h release];
			}
			[[ConnectionRegistry sharedRegistry] addCategory:cat];
			[_savedHosts addObject:cat];
			[cat release];
		}
	}
	[ud removeObjectForKey:HostsKey];
	[savedHosts setDataSource:[ConnectionRegistry sharedRegistry]];
	[savedHosts setDelegate:self];
	
	
	CKHostCell *acell = [[CKHostCell alloc] initImageCell:nil];
	[[[savedHosts tableColumns] objectAtIndex:0] setDataCell:acell];
	[acell release];
	
	[self refreshHosts];
	
	NSEnumerator *e = [[[ConnectionRegistry sharedRegistry] connections] objectEnumerator];
	id cur;
	
	while ((cur = [e nextObject]))
	{
		if ([cur isKindOfClass:[CKHostCategory class]])
		{
			[savedHosts expandItem:cur];
		}
	}
	
	//have a timer to remove completed transfers
	[NSTimer scheduledTimerWithTimeInterval:10
									 target:self
								   selector:@selector(cleanTransferTable:)
								   userInfo:nil
									repeats:YES];
	
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(registryChanged:) 
												 name:CKRegistryChangedNotification 
											   object:nil];
	
	[oConMenu setMenu:[[ConnectionRegistry sharedRegistry] menu]];
	//[self runAutomatedScript];
	
	[[ConnectionRegistry sharedRegistry] handleFilterableOutlineView:savedHosts];
}

- (void)hostnameChanged:(id)sender
{
	[[savedHosts itemAtRow:[savedHosts selectedRow]] setHost:[sender stringValue]];
}

- (void)portChanged:(id)sender
{
	[[savedHosts itemAtRow:[savedHosts selectedRow]] setPort:[sender stringValue]];
}

- (void)usernameChanged:(id)sender
{
	[[savedHosts itemAtRow:[savedHosts selectedRow]] setUsername:[sender stringValue]];
}

- (void)passwordChanged:(id)sender
{
	[[savedHosts itemAtRow:[savedHosts selectedRow]] setPassword:[sender stringValue]];
}

- (void)initialDirectoryChanged:(id)sender
{
	[[savedHosts itemAtRow:[savedHosts selectedRow]] setInitialPath:[sender stringValue]];
}

- (void)urlChanged:(id)sender
{
	[[savedHosts itemAtRow:[savedHosts selectedRow]] setURL:[NSURL URLWithString:[sender stringValue]]];
}

- (void)registryChanged:(NSNotification *)n
{
	[savedHosts reloadData];
	[oConMenu setMenu:[[ConnectionRegistry sharedRegistry] menu]];
}

- (void)newCategory:(id)sender
{
	id parent = [savedHosts itemAtRow:[savedHosts selectedRow]];
	if ([parent isKindOfClass:[CKHost class]])
	{
		parent = [parent category];
	}

	CKHostCategory *cat = [[CKHostCategory alloc] initWithName:NSLocalizedString(@"New Category", @"new cat name")];
	if (parent)
	{
		[parent addChildCategory:cat];
	}
	else
	{
		[[ConnectionRegistry sharedRegistry] addCategory:cat];
	}
	[cat release];
}

- (void)newHost:(id)sender
{
	id parent = [savedHosts itemAtRow:[savedHosts selectedRow]];
	if ([parent isKindOfClass:[CKHost class]])
	{
		parent = [parent category];
	}
	
	CKHost *h = [[CKHost alloc] init];
	if (parent)
	{
		[parent addHost:h];
	}
	else
	{
		[[ConnectionRegistry sharedRegistry] addHost:h];
	}
	[h release];
}

- (void)checkForFile:(id)sender
{
	if (!check)
	{
		check = [[InputDialog alloc] init];
		[check setDialogTitle:@"Find File"];
	}
	[check beginSheetModalForWindow:window delegate:self selector:@selector(fileCheck:receivedValue:)];
}

- (void)fileCheck:(InputDialog *)input receivedValue:(NSString *)val
{
	if (val)
	{
		[con checkExistenceOfPath:val];
	}
}

- (void)connectionTypeChanged:(id)sender
{
	[[savedHosts itemAtRow:[savedHosts selectedRow]] setConnectionType:[sender titleOfSelectedItem]];
}

- (void)cleanTransferTable:(NSTimer *)timer
{
//	NSMutableArray *completed = [NSMutableArray array];
//	NSEnumerator *e = [transfers objectEnumerator];
//	CKTransferRecord *cur;
//	
//	while (cur = [e nextObject]) {
//		if ([cur isCompleted]) 
//			[completed addObject:cur];
//	}
//	[transfers removeObjectsInArray:completed];
//	[transferTable reloadData];
}

- (void)disconnect:(id)sender
{
	[con disconnect];
}

- (void)refreshHosts
{
	[savedHosts reloadData];
}

- (void)savedHostsChanged:(id)sender
{
	id selected = [savedHosts itemAtRow:[savedHosts selectedRow]];
	
	if ([selected isKindOfClass:[CKHost class]])
	{
		CKHost *host = selected;
				
		[cHost setStringValue:[host host]];
		[cUser setStringValue:[host username]];
		[cPort setStringValue:[host port]];
		if ([host initialPath])
			[initialDirectory setStringValue:[host initialPath]];
		else
			[initialDirectory setStringValue:@""];
		
		if ([host connectionType])
			[cTypePopup selectItemWithTitle:[host connectionType]];
		
		NSString *pass = [host password];
		if (pass)
			[cPass setStringValue:pass];
		else
			[cPass setStringValue:@""];
		
		[connectWindow makeFirstResponder:cPass];
	}
	
}

- (IBAction)cancelConnect:(id)sender
{
	[connectWindow orderOut:self];
	[NSApp endSheet:connectWindow];
}

- (IBAction)connect:(id)sender
{
	NSError *err = nil;
	if ([[cTypePopup titleOfSelectedItem] isEqualToString:AutoSelect])
	{
		if ([[cURL stringValue] length] > 0)
			con = [[AbstractConnection connectionWithURL:[NSURL URLWithString:[cURL stringValue]] error:&err] retain];
		else
			con = [[AbstractConnection connectionToHost:[cHost stringValue]
												   port:[cPort stringValue]
											   username:[cUser stringValue]
											   password:[cPass stringValue]
												  error:&err] retain];
	}
	else
	{
		con = [[AbstractConnection connectionWithName:[cTypePopup titleOfSelectedItem]
												 host:[cHost stringValue]
												 port:[cPort stringValue]
											 username:[cUser stringValue]
											 password:[cPass stringValue]
												error:&err] retain];
	}
	
	if (!con)
	{
		if (err)
		{
			[NSApp presentError:err];
		}
		return;
	}
	
	NSTextStorage *textStorage = [log textStorage];
	[textStorage setDelegate:self];		// get notified when text changes
	[con setTranscript:textStorage];
	[[fileCheckLog textStorage] setDelegate:self];
	[con setProperty:[fileCheckLog textStorage] forKey:@"RecursiveDirectoryDeletionTranscript"];
	[con setProperty:[fileCheckLog textStorage] forKey:@"FileCheckingTranscript"];
	[con setProperty:[fileCheckLog textStorage] forKey:@"RecursiveDownloadTranscript"];
	
	
	[con setDelegate:self];
	[self cancelConnect:sender];
	
	if ([btnBrowseHost state] == NSOnState)
	{
		ConnectionOpenPanel *browse = [ConnectionOpenPanel connectionOpenPanel:con];
		[browse setCanCreateDirectories:YES];
		[browse setCanChooseDirectories:YES];
		[browse setCanChooseFiles:YES];
		[browse setAllowsMultipleSelection:YES];
		
		[browse beginSheetForDirectory:[initialDirectory stringValue]
								  file:nil
						modalForWindow:window
						 modalDelegate:self
						didEndSelector:@selector(browse:returnCode:contextInfo:)
						   contextInfo:nil];
		[con release];
    con = nil;  //we are not responsible for it, the open connection panel will release it.
	}
	else
	{
		[status setStringValue:[NSString stringWithFormat:@"Connecting to: %@", [cHost stringValue]]];
		[con connect];
	}
//	id <AbstractConnectionProtocol> copy = [con copy];
//	[copy setDelegate:self];
//	[copy connect];
}

- (void)browse:(ConnectionOpenPanel *)panel returnCode:(int)returnCode contextInfo:(id)ui
{
	if (returnCode == NSOKButton)
	{
		NSRunAlertPanel (@"Files Selected", [[panel filenames] description], @"OK", nil, nil);
	}
	else
	{
		NSRunAlertPanel(@"Open Panel Cancelled",@"The panel was cancelled by the user",@"OK",nil,nil);
	}
}

- (IBAction)deleteFile:(id)sender
{
	NSEnumerator *e = [remoteTable selectedRowEnumerator];
	NSNumber *cur;
	
	while (cur = [e nextObject])
	{
		int row = [cur intValue];
		
		NSDictionary *d = [remoteFiles objectAtIndex:row];
		if ([[d objectForKey:NSFileType] isEqualToString:NSFileTypeRegular] ||
			[[d objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink])
		{
			NSString *file = [[con currentDirectory] stringByAppendingPathComponent:[d objectForKey:cxFilenameKey]];
			[con deleteFile:file];
		}
		else
		{
			[con recursivelyDeleteDirectory:[[con currentDirectory] stringByAppendingPathComponent:[d objectForKey:cxFilenameKey]]];
		}
	}
}

- (IBAction)localFileSelected:(id)sender
{
}

- (void)localDoubleClick:(id)sender
{
	int row = [sender selectedRow];
	
	if (row >= 0 && row < [localFiles count])
	{
		BOOL isDir;
		if ([[NSFileManager defaultManager] fileExistsAtPath:[localFiles objectAtIndex:row] 
												 isDirectory:&isDir] && isDir)
		{
			[currentLocalPath autorelease];
			currentLocalPath = [[localFiles objectAtIndex:row] copy];
			[self refreshLocal];
		}
		else
		{
			NSString *file = [localFiles objectAtIndex:row];
			[self uploadFile:file to:[[con currentDirectory] stringByAppendingPathComponent:[file lastPathComponent]]];
			[transferTable reloadData];
		}
	}
}

- (IBAction)localPopupChanged:(id)sender
{
	NSString *str = [[sender selectedItem] representedObject];
	[currentLocalPath autorelease];
	if ([str length] > 1)
		currentLocalPath = [[str substringToIndex:[str length] - 1] copy];
	else
		currentLocalPath = [str copy];
	[self refreshLocal];
}

- (IBAction)newFolder:(id)sender
{
	InputDialog *input = [[InputDialog alloc] init];
	[input setDialogTitle:@"Enter New Folder Name"];
	[input beginSheetModalForWindow:window delegate:self selector:@selector(newFolderValue:)];
}

- (IBAction)logConfig:(id)sender
{
	[KTLogger configure:self];
}

- (void)newFolderValue:(NSString *)val
{
	if (val)
	{
		NSString *dir = [[con currentDirectory] stringByAppendingPathComponent:val];
		[con createDirectory:dir];
		[con contentsOfDirectory:[con currentDirectory]];
	}
}

- (IBAction)permissions:(id)sender
{
	NSMutableDictionary *file = [remoteFiles objectAtIndex:[remoteTable selectedRow]];
	[[PermissionsController sharedPermissions] displayFile:file
													 sheet:window
												connection:con];
}

- (IBAction)refresh:(id)sender
{
	[con contentsOfDirectory:[con currentDirectory]];
}

- (IBAction)remoteFileSelected:(id)sender
{
	int idx = [sender selectedRow];
	NSDictionary *file = [remoteFiles objectAtIndex:idx];
	
	if (idx >= 0 && idx < [remoteFiles count])
	{
		[btnDelete setEnabled:YES];
		[btnPermissions setEnabled:YES];
		
	}
	else
	{
		[btnDelete setEnabled:NO];
		[btnPermissions setEnabled:NO];
		
	}
	
	if (![[file objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
	{
		[btnEdit setEnabled:YES];
	}
	else
	{
		[btnEdit setEnabled:NO];
	}
}

- (void)remoteDoubleClick:(id)sender
{
	int row = [sender selectedRow];
	
	if (row >= 0 && row < [remoteFiles count])
	{
		NSDictionary *attribs = [remoteFiles objectAtIndex:row];
		
		if ([[attribs objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
		{
			NSString *path = [[con currentDirectory] stringByAppendingPathComponent:[attribs objectForKey:cxFilenameKey]];
			[con changeToDirectory:path];
			[con contentsOfDirectory:path];
			//[remoteFiles removeAllObjects];
			return;
		}
		else if ([[attribs objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink])
		{
			NSString *target = [attribs objectForKey:cxSymbolicLinkTargetKey];
			if ([target characterAtIndex:[target length] - 1] == '/' || [target characterAtIndex:[target length] - 1] == '\\')
			{
				[con changeToDirectory:[attribs objectForKey:cxFilenameKey]];
				[con contentsOfDirectory:[attribs objectForKey:cxFilenameKey]];
				return;
			}
		}
		
		if ([[attribs objectForKey:NSFileType] isEqualToString:NSFileTypeRegular]) {
			[self downloadFile:[[con currentDirectory] stringByAppendingPathComponent:[attribs objectForKey:cxFilenameKey]]
							toFolder:currentLocalPath];
		}
		else if ([[attribs objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink])
		{
			NSString *target = [attribs objectForKey:cxSymbolicLinkTargetKey];
			if ([target characterAtIndex:[target length] - 1] != '/'  && [target characterAtIndex:[target length] - 1] != '\\')
				[self downloadFile:[[con currentDirectory] stringByAppendingPathComponent:[attribs objectForKey:cxFilenameKey]]
								toFolder: currentLocalPath];
		}
		
		[transferTable reloadData];
	}
}

- (IBAction)remotePopupChanged:(id)sender
{
	NSString *path = [[sender selectedItem] representedObject];
	[con changeToDirectory:path];
	[con contentsOfDirectory:path];
}

- (IBAction)showConnect:(id)sender
{
	//[self savedHostsChanged:savedHosts];
	[NSApp beginSheet:connectWindow
	   modalForWindow:window
		modalDelegate:nil
	   didEndSelector:nil
		  contextInfo:nil];
}

- (IBAction)stopTransfer:(id)sender
{
	[con cancelTransfer];
}

- (IBAction)transferSelected:(id)sender
{
	int idx = [sender selectedRow];
	
	if (idx >= 0 && idx < [transfers count])
	{
		[btnStop setEnabled:YES];
	}
	else
	{
		[btnStop setEnabled:NO];
	}
}

static NSImage *_folder = nil;

- (void)refreshRemoteUI
{
	//create popup menu
	NSString *dir = [con currentDirectory];
	NSArray *folders = [dir componentsSeparatedByString:@"/"];
	if ([dir isEqualToString:@"/"])
		folders = [folders subarrayWithRange:NSMakeRange(1, [folders count] - 1)];
	NSEnumerator *e = [folders objectEnumerator];
	NSMutableString *buildup = [NSMutableString string];
	NSString *cur;
	
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"remote"];
	
	if (!_folder)
	{
		_folder = [[[NSWorkspace sharedWorkspace] iconForFile:@"/tmp"] retain];
		[_folder setSize:NSMakeSize(16,16)];
	}
	
	
	while (cur = [e nextObject])
	{
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:cur
													  action:nil
											   keyEquivalent:@""];
		[buildup appendFormat:@"/%@", cur];
		[item setRepresentedObject:[[buildup copy] autorelease]];
		[item setImage:_folder];
		[menu addItem:item];
	}
	
	[remotePopup setMenu:menu];
	[menu release];
	[remotePopup selectItem:[remotePopup lastItem]];
	
	[remoteTable reloadData];
}

- (void)refreshLocal
{
	[localPopup removeAllItems];
	
	//refresh file list
	NSArray *dir = [[NSFileManager defaultManager] directoryContentsAtPath:currentLocalPath];
	[localFiles removeAllObjects];
	NSEnumerator *e = [dir objectEnumerator];
	NSString *cur;
	
	while (cur = [e nextObject])
	{
		if ([cur characterAtIndex:0] != '.') //filter hidden files
			[localFiles addObject:[NSString stringWithFormat:@"%@/%@", currentLocalPath, cur]];
	}
	
	NSArray *pathComponents = [currentLocalPath componentsSeparatedByString:@"/"];
	
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"local"];
	
	e = [pathComponents objectEnumerator];
	NSWorkspace *ws = [NSWorkspace sharedWorkspace];
	
	NSMutableString *buildup = [NSMutableString string];
	NSMenuItem *item;
	
	if ([pathComponents count] > 1)
	{
		while (cur = [e nextObject])
		{
			item = [[NSMenuItem alloc] initWithTitle:cur
											  action:nil
									   keyEquivalent:@""];
			[buildup appendFormat:@"%@/", cur];
			[item setRepresentedObject:[[buildup copy] autorelease]];
			NSImage *img = [ws iconForFile:buildup];
			[img setSize:NSMakeSize(16,16)];
			[item setImage:img];
			[menu addItem:item];
			[item release];
		}		
	}
	
	[localPopup setMenu:menu];
	[menu release];
	[localPopup selectItem:[localPopup lastItem]];
	[localTable reloadData];
}

- (void)printQueueDescription:(id)sender
{
	if ([con isKindOfClass:[AbstractQueueConnection class]]) {
		NSLog(@"Queue Description:\n%@", [(AbstractQueueConnection *)con queueDescription]);
	}
}

- (void)editFile:(id)sender
{
	unsigned idx = [remoteTable selectedRow];
	NSDictionary *file = [remoteFiles objectAtIndex:idx];
	NSString *remotePath = [[con currentDirectory] stringByAppendingPathComponent:[file objectForKey:cxFilenameKey]];
	[con editFile:remotePath];
}

- (void)searchChanged:(id)sender
{
	[[ConnectionRegistry sharedRegistry] setFilterString:[sender stringValue]];
}

#pragma mark -
#pragma mark Connection Helper Methods

+ (NSString *)formattedSpeed:(long) spd
{
	if (spd == 0) return @"0 B/s";
	NSString *suffix[] = {
		@"B", @"KB", @"MB", @"GB", @"TB", @"PB", @"EB"
	};
	
	int i, c = 7;
	long size = spd;
	
	for (i = 0; i < c && size >= 1024; i++) {
		size = size / 1024;
	}
	float rem = 0;
	
	if (i != 0)
		rem = (spd - (i * 1024)) / (i * 1024);
	
	NSString *ext = suffix[i];
	return [NSString stringWithFormat:@"%4.2f %@/s", size+rem, ext];
}

- (FileTransfer *)uploadForLocalFile:(NSString *)file
{
	NSEnumerator *e = [transfers objectEnumerator];
	FileTransfer *cur;
	
	while (cur = [e nextObject])
	{
		if ([[cur localFile] isEqualToString:file] &&
			[cur type] == UploadType )
			return cur;
	}
	return nil;
}

- (FileTransfer *)downloadForLocalFile:(NSString *)file
{
	NSEnumerator *e = [transfers objectEnumerator];
	FileTransfer *cur;
	
	while (cur = [e nextObject])
	{
		if ([[cur localFile] isEqualToString:file] &&
			[cur type] == DownloadType)
			return cur;
	}
	return nil;
}

- (FileTransfer *)uploadForRemoteFile:(NSString *)file
{
	NSEnumerator *e = [transfers objectEnumerator];
	FileTransfer *cur;
	
	while (cur = [e nextObject])
	{
		if ([[cur remoteFile] isEqualToString:file] &&
			[cur type] == UploadType )
			return cur;
	}
	return nil;
}

- (FileTransfer *)downloadForRemoteFile:(NSString *)file
{
	NSEnumerator *e = [transfers objectEnumerator];
	FileTransfer *cur;
	
	while (cur = [e nextObject])
	{
		if ([[cur remoteFile] isEqualToString:file] &&
			[cur type] == DownloadType)
			return cur;
	}
	return nil;
}

- (void)downloadFile:(NSString *)remote toFolder:(NSString *)local
{
	CKTransferRecord *rec = [con downloadFile:remote toDirectory:local overwrite:YES delegate:nil];
	[transfers addObject:rec];
}

- (void)uploadFile:(NSString *)local to:(NSString *)remote
{
	CKTransferRecord *rec = [con uploadFile:local toFile:remote checkRemoteExistence:NO delegate:nil];
	[transfers addObject:rec];
}

- (void)recursivelyUploadContentsAtPath:(NSString *)aFolderPath serverPath:(NSString *)aServerPath
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
    NSEnumerator *directoryEnum = [[fileManager directoryContentsAtPath:aFolderPath] objectEnumerator];
    NSString *nextFile = nil;
	
	[con createDirectory:aServerPath];
	
    while (nextFile = [directoryEnum nextObject])
    {
        NSString *fullLocalPath = [aFolderPath stringByAppendingPathComponent:nextFile];
        NSString *fullServerPath = [aServerPath stringByAppendingPathComponent:nextFile];
        BOOL isDir;
		
        if ([nextFile hasPrefix:@"."])
        {
            continue;
        }
        
        if ([fileManager fileExistsAtPath:fullLocalPath isDirectory:&isDir] && isDir)
        {            
            [self recursivelyUploadContentsAtPath:fullLocalPath serverPath:fullServerPath];
        }
        else
        {
            [self uploadFile:fullLocalPath to:fullServerPath];
        }
    }
}

- (void)uploadFolderContentsAtPath:(NSString *)aFolderPath
{
	NSString *serverCurrentDirectory = [[con currentDirectory] stringByAppendingPathComponent:[aFolderPath lastPathComponent]];
	[self recursivelyUploadContentsAtPath:aFolderPath serverPath:serverCurrentDirectory];
	[transferTable reloadData];
}

#pragma mark -
#pragma mark Connection Delegate Methods

- (BOOL)connection:(id <AbstractConnectionProtocol>)con authorizeConnectionToHost:(NSString *)host message:(NSString *)message;
{
	if (NSRunAlertPanel(@"Authorize Connection?", @"%@\nHost: %@", @"Yes", @"No", nil, message, host) == NSOKButton)
		return YES;
	return NO;
}

- (void)connection:(AbstractConnection *)aConn didConnectToHost:(NSString *)host
{
	isConnected = YES;
	[status setStringValue:[NSString stringWithFormat:@"Connected to: %@", host]];
	[btnRefresh setEnabled:YES];
	[remotePopup setHidden:NO];
	[btnNewFolder setEnabled:YES];
	[remoteTable setHidden:NO];
	[btnDisconnect setEnabled:YES];
	NSString *dir = [[initialDirectory stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (dir && [dir length] > 0)
		[con changeToDirectory:[initialDirectory stringValue]];
	[con directoryContents];
}

- (void)connection:(AbstractConnection *)aConn didDisconnectFromHost:(NSString *)host
{
	isConnected = NO;
	[status setStringValue:[NSString stringWithFormat:@"Disconnected from: %@", host]];
	[btnRefresh setEnabled:NO];
	[btnDelete setEnabled:NO];
	[btnNewFolder setEnabled:NO];
	[btnPermissions setEnabled:NO];
	[btnStop setEnabled:NO];
	[btnDisconnect setEnabled:NO];
	[remotePopup setHidden:YES];
	[btnNewFolder setEnabled:NO];
	[remoteTable setHidden:YES];
	
	[con release];
	con = nil;
}

- (void)connection:(AbstractConnection *)aConn didReceiveError:(NSError *)error
{
	NSLog(@"%@: %@", NSStringFromSelector(_cmd), error);
	NSRunAlertPanel(@"Error",@"Connection returned an error: %@",@"OK",nil
					,nil, [error localizedDescription]);
}

- (void)connectionDidSendBadPassword:(AbstractConnection *)aConn
{
	NSRunAlertPanel(@"Bad Password",@"The Password you entered is no good. Please re-enter it and try again.",@"OK",nil, nil);
	[self showConnect:self];
}

- (NSString *)connection:(AbstractConnection *)aConn needsAccountForUsername:(NSString *)username
{
	[status setStringValue:[NSString stringWithFormat:@"Need Account for %@ not implemented", username]];
	return nil;
}

- (void)connection:(AbstractConnection *)aConn didCreateDirectory:(NSString *)dirPath
{
	[status setStringValue:[NSString stringWithFormat:@"Created Directory: %@", dirPath]];
}

- (void)connection:(AbstractConnection *)aConn didSetPermissionsForFile:(NSString *)path
{
	
}

- (void)connection:(AbstractConnection *)aConn didRenameFile:(NSString *)from to:(NSString *)toPath
{
	
}

- (void)connection:(AbstractConnection *)aConn didDeleteFile:(NSString *)path
{
	[con contentsOfDirectory:[con currentDirectory]];
}

- (void)connection:(AbstractConnection *)aConn didDeleteDirectory:(NSString *)path
{
	[con contentsOfDirectory:[con currentDirectory]];
}


- (void)connection:(AbstractConnection *)aConn didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath
{
	NSLog(@"%@ %@", NSStringFromSelector(_cmd), dirPath);
	[remoteFiles removeAllObjects];
	[remoteFiles addObjectsFromArray:[contents filteredArrayByRemovingHiddenFiles]];
	[self refreshRemoteUI];
}

- (void)connection:(id <AbstractConnectionProtocol>)con download:(NSString *)path receivedDataOfLength:(unsigned long long)length
{
	[transferTable reloadData];
}

- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath sentDataOfLength:(unsigned long long)length
{
	[transferTable reloadData];
}

- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidFinish:(NSString *)remotePath
{
	[self refreshRemoteUI];
	[transferTable reloadData];
}

- (void)connection:(id <AbstractConnectionProtocol>)con downloadDidFinish:(NSString *)remotePath error:(NSError *)error
{
	[self refreshLocal];
	[transferTable reloadData];
}

- (void)connection:(id <AbstractConnectionProtocol>)con checkedExistenceOfPath:(NSString *)path pathExists:(BOOL)exists
{
	if (exists)
	{
		NSRunAlertPanel(@"File Exists", @"Found path: %@", @"OK", nil, nil, path);
	}
	else
	{
		NSRunAlertPanel(@"File Not Found", @"Could not find path: %@", @"OK", nil, nil, path);
	}
}

#pragma mark -
#pragma mark NSTableView DataSource Methods

- (int)numberOfRowsInTableView:(NSTableView *)aTable
{
	if (aTable == remoteTable)
		return [remoteFiles count];
	else if (aTable == localTable)
		return [localFiles count];
	return 0;
}

static NSImage *folder = nil;
static NSImage *upload = nil;
static NSImage *download = nil;
static NSImage *symFolder = nil;
static NSImage *symFile = nil;
NSString *IconKey = @"Icon";

- (id)tableView:(NSTableView *)aTable objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	NSString *identifier = [aTableColumn identifier];
	
	if (aTable == remoteTable)
	{
		NSMutableDictionary *row = [remoteFiles objectAtIndex:rowIndex];
		
		if ([identifier isEqualToString:@"icon"])
		{
			NSImage *img = [row objectForKey:IconKey];
			if (!img)
			{
				if ([[row objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
				{
					if (!folder)
						folder = [[[NSWorkspace sharedWorkspace] iconForFile:@"/tmp"] retain];
					img = folder;
				}
				else if ([[row objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink])
				{
					if (!symFolder || !symFile)
					{
						symFolder = [[NSImage imageNamed:@"symlink_folder.tif"] retain];
						symFile = [[NSImage imageNamed:@"symlink_file.tif"] retain];
					}
					NSString *target = [row objectForKey:cxSymbolicLinkTargetKey];
					if ([target characterAtIndex:[target length] - 1] == '/' || [target characterAtIndex:[target length] - 1] == '\\')
						img = symFolder;
					else
					{
						NSImage *fileType = [[NSWorkspace sharedWorkspace] iconForFileType:[[row objectForKey:cxFilenameKey] pathExtension]];
						NSImage *comp = [[NSImage alloc] initWithSize:NSMakeSize(16,16)];
						[img setScalesWhenResized:YES];
						[img setSize:NSMakeSize(16,16)];
						[comp lockFocus];
						[fileType drawInRect:NSMakeRect(0,0,16,16) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
						[symFile drawInRect:NSMakeRect(0,0,16,16) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
						[comp unlockFocus];
						[comp autorelease];
						img = comp;
					}
				}
				else
				{
					img = [[NSWorkspace sharedWorkspace] iconForFileType:[[row objectForKey:cxFilenameKey] pathExtension]];
				}
				[img setSize:NSMakeSize(16,16)];
				[row setObject:img forKey:IconKey];
			}
			
			return img;
		}
		else if ([identifier isEqualToString:@"name"])
		{
			return [row objectForKey:cxFilenameKey];
		}
		else if ([identifier isEqualToString:@"size"])
		{
			//if ([[row objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
			//	return nil;
			return [NSString formattedFileSizeWithBytes:[row objectForKey:NSFileSize]];
		}
		else if ([identifier isEqualToString:@"modified"])
		{
			return [row objectForKey:NSFileModificationDate];
		}
	}
	else if (aTable == localTable)
	{
		NSString *file = [localFiles objectAtIndex:rowIndex];
		NSFileManager *fm = [NSFileManager defaultManager];
		NSDictionary *attribs = [fm fileAttributesAtPath:file traverseLink:YES];
		
		if ([identifier isEqualToString:@"icon"])
		{
			NSImage *img = [[NSWorkspace sharedWorkspace] iconForFile:file];
			[img setSize:NSMakeSize(16,16)];
			return img;
		}
		else if ([identifier isEqualToString:@"name"])
		{
			return [file lastPathComponent];
		}
		else if ([identifier isEqualToString:@"size"])
		{
			BOOL isDir;
			if ([fm fileExistsAtPath:file isDirectory:&isDir] && isDir)
				return nil;
			return [NSString formattedFileSizeWithBytes:[attribs objectForKey:NSFileSize]];
		}
		else if ([identifier isEqualToString:@"modified"])
		{
			return [attribs objectForKey:NSFileModificationDate];
		}
	}
	
	return nil;
}

- (NSView *) tableView:(NSTableView *) tableView viewForRow:(int) row
{
	return [[[transfers objectAtIndex:row] objectForKey:TransferControllerKey] view];
}

- (BOOL)tableView:(NSTableView *)tableView writeRows:(NSArray *)rows toPasteboard:(NSPasteboard *)pboard
{
	if (tableView == localTable)
	{
		NSMutableArray *files = [NSMutableArray array];
		NSEnumerator *e = [rows objectEnumerator];
		NSNumber *cur;
		NSFileManager *fm = [NSFileManager defaultManager];
		
		while (cur = [e nextObject])
		{
			NSString *name = [localFiles objectAtIndex:[cur intValue]];
			NSMutableDictionary *file = [[fm fileAttributesAtPath:name traverseLink:NO] mutableCopy];
			[file setObject:[name lastPathComponent] forKey:cxFilenameKey];
			[files addObject:file];
			[file release];
		}
		[pboard declareTypes:[NSArray arrayWithObject:cxLocalFilePBoardType] owner:nil];
		[pboard setPropertyList:files forType:cxLocalFilePBoardType]; //
		return YES;
	}
	else if (tableView == remoteTable)
	{
		NSMutableArray *f = [NSMutableArray array];
		NSEnumerator *e = [rows objectEnumerator];
		NSNumber *cur;
		while (cur = [e nextObject])
		{
			NSMutableDictionary *file = [[remoteFiles objectAtIndex:[cur intValue]] mutableCopy];
			[file removeObjectForKey:@"Icon"];
			[f addObject:file];
			[file release];
		}
		[pboard declareTypes:[NSArray arrayWithObject:cxRemoteFilePBoardType] owner:nil];
		[pboard setPropertyList:f forType:cxRemoteFilePBoardType];
		return YES;
	}
	return NO;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id <NSDraggingInfo>)info row:(int)row dropOperation:(NSTableViewDropOperation)operation
{
	NSPasteboard *pb = [info draggingPasteboard];
	if (tableView == localTable) //do a download
	{
		NSArray *files = [pb propertyListForType:cxRemoteFilePBoardType];
		NSEnumerator *e = [files objectEnumerator];
		NSDictionary *file;
		
		while (file = [e nextObject])
		{
			if ([[file objectForKey:NSFileType] isEqualToString:NSFileTypeRegular])
			{
				[self downloadFile:[[con currentDirectory] stringByAppendingPathComponent:[file objectForKey:cxFilenameKey]]
						  toFolder: currentLocalPath];
			}
			else if ([[file objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink])
			{
				NSString *target = [file objectForKey:cxSymbolicLinkTargetKey];
				if ([target characterAtIndex:[target length] - 1] != '/'  && [target characterAtIndex:[target length] - 1] != '\\')
				{
					[self downloadFile:[[con currentDirectory] stringByAppendingPathComponent:target]
							  toFolder: currentLocalPath];
				}
				else
				{
					CKTransferRecord *rec = [con recursivelyDownload:[[con currentDirectory] stringByAppendingPathComponent:target]
																  to:currentLocalPath
														   overwrite:YES];
					[transfers addObject:rec];
				}
			}
			else if ([[file objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
			{
				CKTransferRecord *rec = [con recursivelyDownload:[[con currentDirectory] stringByAppendingPathComponent:[file objectForKey:cxFilenameKey]]
															  to:currentLocalPath
													   overwrite:YES];
				[transfers addObject:rec];
			}
		}
		[transferTable reloadData];
		return YES;
	}
	else if (tableView == remoteTable) //do an upload
	{
		if ([[pb types] containsObject:cxLocalFilePBoardType])
		{
			NSArray *files = [pb propertyListForType:cxLocalFilePBoardType];
			NSEnumerator *e = [files objectEnumerator];
			NSDictionary *cur;
			
			while (cur = [e nextObject])
			{
				if ([[cur objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
				{
					CKTransferRecord *rec = [con recursivelyUpload:[currentLocalPath stringByAppendingPathComponent:[cur objectForKey:cxFilenameKey]]
																to:[con currentDirectory]];
					[transfers addObject:rec];
				}
				else if ([[cur objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink])
				{
					CKTransferRecord *rec = [con recursivelyUpload:[currentLocalPath stringByAppendingPathComponent:[cur objectForKey:cxSymbolicLinkTargetKey]]
																to:[con currentDirectory]];
					[transfers addObject:rec];
				}
				else
				{
					[self uploadFile:[currentLocalPath stringByAppendingPathComponent:[cur objectForKey:cxFilenameKey]]
								  to:[[con currentDirectory] stringByAppendingPathComponent:[cur objectForKey:cxFilenameKey]]];
				}
			}
			[transferTable reloadData];
			
			return YES;
		}
		else if ([[pb types] containsObject:NSFilenamesPboardType])
		{
			NSFileManager *fm = [NSFileManager defaultManager];
			NSArray *files = [pb propertyListForType:NSFilenamesPboardType];
			NSEnumerator *e = [files objectEnumerator];
			NSString *cur;
			BOOL isDir;
			
			NSString *curRemoteDir = [[con currentDirectory] copy];
			
			while (cur = [e nextObject])
			{
				CKTransferRecord *root = [con recursivelyUpload:cur to:[con currentDirectory]];
			}
			[curRemoteDir release];
			[transferTable reloadData];
			return YES;
		}
	}
	return NO;
}

- (NSDragOperation)tableView:(NSTableView *)tableView 
				validateDrop:(id <NSDraggingInfo>)info 
				 proposedRow:(int)row 
	   proposedDropOperation:(NSTableViewDropOperation)operation
{
	if (!isConnected)
		return NSDragOperationNone;
	if (tableView == localTable || tableView == remoteTable)
		return NSDragOperationCopy;
	return NSDragOperationNone;
}

#pragma mark -
#pragma mark Outline View Data Source

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (item == nil)
	{
		return [transfers count];
	}
	return [[item contents] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(int)index ofItem:(id)item
{
	if (item == nil)
	{
		return [transfers objectAtIndex:index];
	}
	return [[item contents] objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [item isDirectory];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	NSString *identifier = [tableColumn identifier];
	CKTransferRecord *transfer = (CKTransferRecord *)item;
	
	if ([identifier isEqualToString:@"progress"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:[transfer progress], @"progress", [transfer name], @"name", nil];
	}
	else if ([identifier isEqualToString:@"file"])
	{
		return [transfer name];
	}
	else if ([identifier isEqualToString:@"speed"])
	{
		return [NSString formattedSpeed:[transfer speed]];
	}
	if ([identifier isEqualToString:@"image"])
	{
		if (![transfer isUpload])
		{
			if (!download)
				download = [[NSImage imageNamed:@"download.tif"] retain];
			return download;
		}
		else
		{
			if (!upload)
				upload = [[NSImage imageNamed:@"upload.tif"] retain];
			return upload;
		}
	}
	else if ([identifier isEqualToString:@"icon"])
	{
		NSImage *img = [[NSWorkspace sharedWorkspace] iconForFileType:[[transfer path] pathExtension]];
		[img setSize:NSMakeSize(16,16)];
		return img;
	}
	
	return nil;
}

#pragma mark -
#pragma mark NSTextView Delegate Methods
/*!	Called as a delegate of the log's text storage, so we can update the scroll position
*/
- (void)textStorageDidProcessEditing:(NSNotification *)aNotification
{
	if ([aNotification object] == [log textStorage])
		[self performSelector:@selector(scrollToVisible:) withObject:log afterDelay:0.0];
	else
		[self performSelector:@selector(scrollToVisible:) withObject:fileCheckLog afterDelay:0.0];
	// Don't scroll now, do it in a moment. Doing it now causes error messgaes.
}

- (void) scrollToVisible:(id)whichLog
{
	[whichLog scrollRangeToVisible:NSMakeRange([[whichLog textStorage] length], 0)];
}

#pragma mark -
#pragma mark NSApplication Delegate Methods

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	if ([con numberOfTransfers] > 0) {
		if (NSRunAlertPanel(@"Transfers in Progress", @"Are you sure you want to quit while there are still file transfers in progress?", @"Yes Quit", @"No", nil) != NSOKButton)
			return NSTerminateCancel;
	}
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	[ud setObject:NSStringFromRect([window frame]) 
		   forKey:[window frameAutosaveName]];
	[ud setBool:[logDrawer state] == NSDrawerOpenState forKey:@"showLog"];
	return NSTerminateNow;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
	return YES;
}

@end

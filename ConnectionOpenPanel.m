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


#import "ConnectionOpenPanel.h"
#import "AbstractConnectionProtocol.h"

@implementation ConnectionOpenPanel

- (id) initWithConnection: (id <AbstractConnectionProtocol>) inConnection
{
	NSAssert (inConnection, @"no valid connection");
	self = [super initWithWindowNibName: @"ConnectionOpenPanel"];
	
	if (self)
	{
		shouldDisplayOpenButton = YES;
		shouldDisplayOpenCancelButton = YES;
		[self setTimeout:30];
		[self setConnection: inConnection];
		[self setAllowsMultipleSelection: NO];
		[self setCanChooseFiles: YES];
		[self setCanChooseDirectories: YES];
		[self setPrompt: [[NSBundle bundleForClass: [self class]] localizedStringForKey: @"open"
																				  value: @"Open"
																				  table: @"localizable"]];
		
	}
	
	return self;
}

+ (ConnectionOpenPanel *) connectionOpenPanel: (id <AbstractConnectionProtocol>) inConnection
{
	return [[[ConnectionOpenPanel alloc] initWithConnection: inConnection] autorelease];
}

- (void) awakeFromNib
{
	[openButton setHidden:!shouldDisplayOpenButton];
    [openCancelButton setHidden:!shouldDisplayOpenCancelButton];
    
    //observe the selection from the tree controller
	//
	[directoryContents addObserver: self
						forKeyPath: @"selection"
						   options: NSKeyValueObservingOptionNew
						   context: nil];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    [directoryContents removeObserver: self
                           forKeyPath: @"selection"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	//if something is selected, then it should say open, else it should say select
	//
		[self setIsSelectionValid: NO];
  
  if ([[directoryContents selectedObjects] count] == 1)
  {
    if ([[[[directoryContents selectedObjects] objectAtIndex: 0] valueForKey: @"isLeaf"] boolValue])  //file
      [self setIsSelectionValid: [self canChooseFiles]];
    else      //folder
      [self setIsSelectionValid: [self canChooseDirectories]];
    
		if ([self canChooseDirectories])
			[self setPrompt: [[NSBundle bundleForClass: [self class]] localizedStringForKey: @"select"
                                                                                value: @"Select"
                                                                                table: @"localizable"]];
		else
			[self setPrompt: [[NSBundle bundleForClass: [self class]] localizedStringForKey: @"open"
                                                                                value: @"Open"
                                                                                table: @"localizable"]];
  }
  else if ([[directoryContents selectedObjects] count] == 0)
  {
    [self setIsSelectionValid: [self canChooseDirectories]];
    
		if ([self canChooseDirectories])
			[self setPrompt: [[NSBundle bundleForClass: [self class]] localizedStringForKey: @"select"
                                                                                value: @"Select"
                                                                                table: @"localizable"]];
		else
			[self setPrompt: [[NSBundle bundleForClass: [self class]] localizedStringForKey: @"open"
                                                                                value: @"Open"
                                                                                table: @"localizable"]];
    
  }
  else //multiple items
  {
    //this can only happen if the table view was set to allow it, which means that we allow multiple selection
    //simply check that everyitems are selectable
    //
    NSEnumerator *theEnum = [[directoryContents selectedObjects] objectEnumerator];
    NSDictionary *currentItem;
    BOOL wholeSelectionIsValid = YES;
    while ((currentItem = [theEnum nextObject]) && wholeSelectionIsValid)
    {
      if ([[[[directoryContents selectedObjects] objectAtIndex: 0] valueForKey: @"isLeaf"] boolValue])
        wholeSelectionIsValid = [self canChooseFiles];
      else
        wholeSelectionIsValid = [self canChooseDirectories];        
    }
    [self setIsSelectionValid: wholeSelectionIsValid];
  }
}

#pragma mark ----=actions=----
- (IBAction) closePanel: (id) sender
{
  //invalidate the timer in case the user dismiss the panel before the connection happened
  //
	[timer invalidate];
	timer = nil;
  
	[[self connection] setDelegate:nil];
	[self setConnection:nil];
	
	if ([sender tag] && 
		([[directoryContents selectedObjects] count] == 1) && 
		![[[[directoryContents selectedObjects] objectAtIndex: 0] valueForKey: @"isLeaf"] boolValue] &&
		![self canChooseDirectories])
	{
		[[self connection] changeToDirectory: [[[directoryContents selectedObjects] objectAtIndex: 0] valueForKey: @"path"]];
		[[self connection] directoryContents];
	}
	else
	{
		if ([[self window] isSheet])
			[[NSApplication sharedApplication] endSheet:[self window] returnCode: [sender tag]];
		else
			[[NSApplication sharedApplication] stopModalWithCode: [sender tag]];
		
		[self close];
	}
	myKeepRunning = NO;
}

- (IBAction) newFolder: (id) sender
{
	[[NSApplication sharedApplication] runModalForWindow: createFolder];
}

- (IBAction) createNewFolder: (id) sender
{
	[[NSApplication sharedApplication] stopModal];
	[createFolder orderOut: sender];
	
	if ([sender tag] == NSOKButton)
	{
		//check that a folder with the same name does not exiss
		//
		BOOL containsObject = NO;
		
		NSEnumerator *theEnum = [[directoryContents arrangedObjects] objectEnumerator];
		id currentObject = nil;
		
		while ((currentObject = [theEnum nextObject]) && !containsObject)
			containsObject = [[currentObject objectForKey: @"fileName"] isEqualToString: [self newFolderName]];
		
		if (!containsObject)
		{
			NSString *dir = [[[self connection] currentDirectory] stringByAppendingPathComponent:[self newFolderName]];
			[[self connection] createDirectory: dir];
		}
		else
		{  
			[[self connection] changeToDirectory: [[[self connection] currentDirectory] stringByAppendingPathComponent: [self newFolderName]]];
			[[self connection] directoryContents];      
		}
		
		[self setIsLoading: YES];
	}
}

- (IBAction) goToFolder: (id) sender
{
	unsigned c = [[parentDirectories arrangedObjects] count];
	NSString *newPath = @"";
	if (c > 0)
	{
		newPath = [[[[[[self connection] currentDirectory] pathComponents] subarrayWithRange: NSMakeRange (0, ([[parentDirectories arrangedObjects] count] - [sender indexOfSelectedItem]))] componentsJoinedByString: @"/"] substringFromIndex: 1];
	}
	
	if ([newPath isEqualToString: @""])
		newPath = @"/";
  
	[self setIsLoading: YES];
	[[self connection] changeToDirectory: newPath];
	[[self connection] directoryContents];
}

- (IBAction) openFolder: (id) sender
{
	if ([sender count])
		if (![[[sender objectAtIndex: 0] valueForKey: @"isLeaf"] boolValue])
		{
			[self setIsLoading: YES];
			[[self connection] changeToDirectory: [[sender objectAtIndex: 0] valueForKey: @"path"]];
			[[self connection] directoryContents];
		}
}

#pragma mark ----=accessors=----
//=========================================================== 
//  connection 
//=========================================================== 
- (id <AbstractConnectionProtocol>)connection
{
	//NSLog(@"in -connection, returned connection = %@", connection);
	
	return [[connection retain] autorelease]; 
}

- (void)setConnection:(id <AbstractConnectionProtocol>)aConnection
{
	//NSLog(@"in -setConnection:, old value of connection: %@, changed to: %@", connection, aConnection);
	
	if (aConnection == nil)
	{
		//store last directory
		[lastDirectory autorelease];
		lastDirectory = [[connection currentDirectory] copy];
	}
	
	if (connection != aConnection) {
		[connection setDelegate: nil];
		[connection forceDisconnect];
		[connection cleanupConnection];
		[connection release];
		connection = [aConnection retain];
		[connection setDelegate: self];
	}
}

//=========================================================== 
//  canChooseDirectories 
//=========================================================== 
- (BOOL)canChooseDirectories
{
	//NSLog(@"in -canChooseDirectories, returned canChooseDirectories = %@", canChooseDirectories ? @"YES": @"NO" );
	
	return canChooseDirectories;
}

- (void)setCanChooseDirectories:(BOOL)flag
{
	//NSLog(@"in -setCanChooseDirectories, old value of canChooseDirectories: %@, changed to: %@", (canChooseDirectories ? @"YES": @"NO"), (flag ? @"YES": @"NO") );
	
	canChooseDirectories = flag;
}

//=========================================================== 
//  canChooseFiles 
//=========================================================== 
- (BOOL)canChooseFiles
{
	//NSLog(@"in -canChooseFiles, returned canChooseFiles = %@", canChooseFiles ? @"YES": @"NO" );
	
	return canChooseFiles;
}

- (void)setCanChooseFiles:(BOOL)flag
{
	//NSLog(@"in -setCanChooseFiles, old value of canChooseFiles: %@, changed to: %@", (canChooseFiles ? @"YES": @"NO"), (flag ? @"YES": @"NO") );
	
	canChooseFiles = flag;
}

//=========================================================== 
//  canCreateDirectories 
//=========================================================== 
- (BOOL)canCreateDirectories
{
	//NSLog(@"in -canCreateDirectories, returned canCreateDirectories = %@", canCreateDirectories ? @"YES": @"NO" );
	
	return canCreateDirectories;
}

- (void)setCanCreateDirectories:(BOOL)flag
{
	//NSLog(@"in -setCanCreateDirectories, old value of canCreateDirectories: %@, changed to: %@", (canCreateDirectories ? @"YES": @"NO"), (flag ? @"YES": @"NO") );
	
	canCreateDirectories = flag;
}

//=========================================================== 
//  shouldDisplayOpenButton 
//=========================================================== 
- (BOOL)shouldDisplayOpenButton
{
	//NSLog(@"in -shouldDisplayOpenButton, returned shouldDisplayOpenButton = %@", shouldDisplayOpenButton ? @"YES": @"NO" );
	
	return shouldDisplayOpenButton;
}

- (void)setShouldDisplayOpenButton:(BOOL)flag
{
	//NSLog(@"in -setShouldDisplayOpenButton, old value of shouldDisplayOpenButton: %@, changed to: %@", (shouldDisplayOpenButton ? @"YES": @"NO"), (flag ? @"YES": @"NO") );
	
	shouldDisplayOpenButton = flag;
}

//=========================================================== 
//  shouldDisplayOpenCancelButton 
//=========================================================== 
- (BOOL)shouldDisplayOpenCancelButton
{
	//NSLog(@"in -shouldDisplayOpenCancelButton, returned shouldDisplayOpenCancelButton = %@", shouldDisplayOpenCancelButton ? @"YES": @"NO" );
	
	return shouldDisplayOpenCancelButton;
}

- (void)setShouldDisplayOpenCancelButton:(BOOL)flag
{
	//NSLog(@"in -setShouldDisplayOpenCancelButton, old value of shouldDisplayOpenCancelButton: %@, changed to: %@", (shouldDisplayOpenCancelButton ? @"YES": @"NO"), (flag ? @"YES": @"NO") );
	
	shouldDisplayOpenCancelButton = flag;
}

//=========================================================== 
//  allowsMultipleSelection 
//=========================================================== 
- (BOOL)allowsMultipleSelection
{
	//NSLog(@"in -allowsMultipleSelection, returned allowsMultipleSelection = %@", allowsMultipleSelection ? @"YES": @"NO" );
	
	return allowsMultipleSelection;
}

- (void)setAllowsMultipleSelection:(BOOL)flag
{
	//NSLog(@"in -setAllowsMultipleSelection, old value of allowsMultipleSelection: %@, changed to: %@", (allowsMultipleSelection ? @"YES": @"NO"), (flag ? @"YES": @"NO") );
	
	allowsMultipleSelection = flag;
}

//=========================================================== 
//  isSelectionValid 
//=========================================================== 
- (BOOL)isSelectionValid
{
	//NSLog(@"in -isSelectionValid, returned isSelectionValid = %@", isSelectionValid ? @"YES": @"NO" );
	
	return isSelectionValid;
}

- (void)setIsSelectionValid:(BOOL)flag
{
	//NSLog(@"in -setIsSelectionValid, old value of isSelectionValid: %@, changed to: %@", (isSelectionValid ? @"YES": @"NO"), (flag ? @"YES": @"NO") );
	
	isSelectionValid = flag;
}

//=========================================================== 
//  isLoading 
//=========================================================== 
- (BOOL)isLoading
{
	//NSLog(@"in -isLoading, returned isLoading = %@", isLoading ? @"YES": @"NO" );
	
	return isLoading;
}

- (void)setIsLoading:(BOOL)flag
{
	//NSLog(@"in -setIsLoading, old value of isLoading: %@, changed to: %@", (isLoading ? @"YES": @"NO"), (flag ? @"YES": @"NO") );
	
	isLoading = flag;
}

//=========================================================== 
//  selectedURLs 
//=========================================================== 
- (NSArray *)URLs
{
	NSArray *selectedFiles = [directoryContents selectedObjects];
	
	if (![selectedFiles count])
		selectedFiles = [NSArray arrayWithObject: [NSDictionary dictionaryWithObject: [[self connection] currentDirectory]
																			  forKey: @"filePath"]];
	
	NSEnumerator *theEnum = [selectedFiles objectEnumerator];
	NSDictionary* currentItem;
	NSMutableArray *returnValue = [NSMutableArray array];
	
	while (currentItem = [theEnum nextObject])
	{ 
		NSString *pathToAdd = [currentItem objectForKey: @"filePath"];
		
		//check that we are past the root directory
		//
		if (([pathToAdd rangeOfString: [[self connection] rootDirectory]].location == 0) && 
			(![pathToAdd isEqualToString: [[self connection] rootDirectory]]))
			[returnValue addObject: [pathToAdd substringFromIndex: [[[self connection] rootDirectory] length] + 1]];  
		else if ([pathToAdd isEqualToString: [[self connection] rootDirectory]])
			[returnValue addObject: @""];
		else  //we have up back to before the root directory path needs ../ added
		{
			NSString *rootDirectory = [[self connection] rootDirectory];
			NSString *pathPrefix = @"";
			while ([pathToAdd rangeOfString: rootDirectory].location == NSNotFound)
			{
				pathPrefix = [pathPrefix stringByAppendingPathComponent: @"../"];
				rootDirectory = [rootDirectory stringByDeletingLastPathComponent];
			}
			pathToAdd = [pathPrefix stringByAppendingPathComponent: pathToAdd];
			
			[returnValue addObject: [NSURL URLWithString: pathToAdd
										   relativeToURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@://%@/", [[self connection] urlScheme], [[self connection] host]]]]];  
		}
	}
	
	return [[returnValue copy] autorelease]; 
}

//=========================================================== 
//  fileNames 
//=========================================================== 
- (NSArray *)filenames
{
	NSArray *selectedFiles = [directoryContents selectedObjects];
	
	if ([selectedFiles count] == 0)
	{
		if (!lastDirectory) lastDirectory = [[NSString alloc] initWithString:@""];
		selectedFiles = [NSArray arrayWithObject: [NSDictionary dictionaryWithObject: lastDirectory
																			  forKey: @"path"]];
	}
		
	NSEnumerator *theEnum = [selectedFiles objectEnumerator];
	NSDictionary* currentItem;
	NSMutableArray *returnValue = [NSMutableArray array];
	
	while (currentItem = [theEnum nextObject])
	{  
		if ([[self connection] rootDirectory] &&
			[[currentItem objectForKey: @"path"] rangeOfString: [[self connection] rootDirectory]].location == 0 &&
			![[currentItem objectForKey: @"path"] isEqualToString: [currentItem objectForKey: @"path"]])
		{
			[returnValue addObject: [[currentItem objectForKey: @"path"] substringFromIndex: [[[self connection] rootDirectory] length] + 1]];  
		}
		else
		{
			[returnValue addObject: [currentItem objectForKey: @"path"]];  
		}
	}
	
	return [[returnValue copy] autorelease]; 
}

//=========================================================== 
//  prompt 
//=========================================================== 
- (NSString *)prompt
{
	//NSLog(@"in -prompt, returned prompt = %@", prompt);
	
	return [[prompt retain] autorelease]; 
}

- (void)setPrompt:(NSString *)aPrompt
{
	//NSLog(@"in -setPrompt:, old value of prompt: %@, changed to: %@", prompt, aPrompt);
	
	if (prompt != aPrompt) {
		[prompt release];
		prompt = [aPrompt retain];
	}
}

//=========================================================== 
//  allowedFileTypes 
//=========================================================== 
- (NSMutableArray *)allowedFileTypes
{
	//NSLog(@"in -allowedFileTypes, returned allowedFileTypes = %@", allowedFileTypes);
	
	return [[allowedFileTypes retain] autorelease]; 
}

- (void)setAllowedFileTypes:(NSMutableArray *)anAllowedFileTypes
{
	//NSLog(@"in -setAllowedFileTypes:, old value of allowedFileTypes: %@, changed to: %@", allowedFileTypes, anAllowedFileTypes);
	
	if (allowedFileTypes != anAllowedFileTypes) {
		[allowedFileTypes release];
		allowedFileTypes = [anAllowedFileTypes retain];
	}
}


//=========================================================== 
//  initialDirectory 
//=========================================================== 
- (NSString *)initialDirectory
{
	//NSLog(@"in -initialDirectory, returned initialDirectory = %@", initialDirectory);
	
	return [[initialDirectory retain] autorelease]; 
}

- (void)setInitialDirectory:(NSString *)anInitialDirectory
{
	//NSLog(@"in -setInitialDirectory:, old value of initialDirectory: %@, changed to: %@", initialDirectory, anInitialDirectory);
	
	if (initialDirectory != anInitialDirectory) {
		[initialDirectory release];
		initialDirectory = [anInitialDirectory retain];
	}
}

//=========================================================== 
//  newFolderName 
//=========================================================== 
- (NSString *)newFolderName
{
	//NSLog(@"in -newFolderName, returned newFolderName = %@", newFolderName);
	
	return [[newFolderName retain] autorelease]; 
}

- (void)setNewFolderName:(NSString *)aNewFolderName
{
	//NSLog(@"in -setNewFolderName:, old value of newFolderName: %@, changed to: %@", newFolderName, aNewFolderName);
	
	if (newFolderName != aNewFolderName) {
		[newFolderName release];
		newFolderName = [aNewFolderName retain];
	}
}

//=========================================================== 
//  delegate 
//=========================================================== 
- (id)delegate
{
	//NSLog(@"in -delegate, returned delegate = %@", delegate);
	
	return [[delegate retain] autorelease]; 
}

- (void)setDelegate:(id)aDelegate
{
	//NSLog(@"in -setDelegate:, old value of delegate: %@, changed to: %@", delegate, aDelegate);
	
	if (delegate != aDelegate) {
		delegate = aDelegate;
	}
}

//=========================================================== 
//  delegateSelector 
//=========================================================== 
- (SEL)delegateSelector
{
	//NSLog(@"in -delegateSelector, returned delegateSelector = (null)", delegateSelector);
	
	return delegateSelector;
}

- (void)setDelegateSelector:(SEL)aDelegateSelector
{
	//NSLog(@"in -setDelegateSelector, old value of delegateSelector: (null), changed to: (null)", delegateSelector, aDelegateSelector);
	
	delegateSelector = aDelegateSelector;
}

- (void)setTimeout:(NSTimeInterval)to
{
	timeout = to;
}

- (NSTimeInterval)timeout
{
	return timeout;
}

- (void)timedOut:(NSTimer *)timer
{
	[self closePanel: nil];
}

//=========================================================== 
// dealloc
//=========================================================== 
- (void)dealloc
{
	[timer invalidate];
	timer = nil;
	[tableView setDelegate: nil];
	[self setDelegate:nil];
	[self setNewFolderName:nil];
	[self setInitialDirectory:nil];
	[self setPrompt:nil];
	[self setAllowedFileTypes:nil];
	[self setConnection:nil];
	[lastDirectory release];
	
	[super dealloc];
}

#pragma mark ----=running the dialog=----
- (void)beginSheetForDirectory:(NSString *)path file:(NSString *)name modalForWindow:(NSWindow *)docWindow modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo
{
  //force the window to be loaded, to be sure tableView is set
  //
  [self window];
  
	[directoryContents setAvoidsEmptySelection: ![self canChooseDirectories]];
	[tableView setAllowsMultipleSelection: [self allowsMultipleSelection]];
	
	[self setDelegate: modalDelegate];
	[self setDelegateSelector: didEndSelector];
	[self retain];
	
	[[NSApplication sharedApplication] beginSheet: [self window]
                                 modalForWindow: docWindow
                                  modalDelegate: self
                                 didEndSelector: @selector(directorySheetDidEnd:returnCode:contextInfo:)
                                    contextInfo: contextInfo];
	[self setInitialDirectory: path];
	
	[self setIsLoading: YES];
	timer = [NSTimer scheduledTimerWithTimeInterval:timeout
											 target:self
										   selector:@selector(timedOut:)
										   userInfo:nil
											repeats:NO];
	[[self connection] connect];
}

- (int)runModalForDirectory:(NSString *)directory file:(NSString *)filename types:(NSArray *)fileTypes
{
  //force the window to be loaded, to be sure tableView is set
  //
  [self window];
  
	[directoryContents setAvoidsEmptySelection: ![self canChooseDirectories]];
	[tableView setAllowsMultipleSelection: [self allowsMultipleSelection]];
	
	//int ret = [[NSApplication sharedApplication] runModalForWindow: [self window]];
	
	myKeepRunning = YES;
	myModalSession = [[NSApplication sharedApplication] beginModalSessionForWindow:[self window]];
	
	[self setInitialDirectory: directory];
	
	[self setIsLoading: YES];
	timer = [NSTimer scheduledTimerWithTimeInterval:timeout
											 target:self
										   selector:@selector(timedOut:)
										   userInfo:nil
											repeats:NO];
	[[self connection] connect];
	
	int ret;
	for (;;) {
		if (!myKeepRunning)
		{
			break;
		}
		ret = [NSApp runModalSession:myModalSession];
		CFRunLoopRunInMode(kCFRunLoopDefaultMode,1,TRUE);
	}
	
	[NSApp endModalSession:myModalSession];
	
	return ret;
}

- (void) directorySheetDidEnd:(NSWindow*) inSheet returnCode: (int)returnCode contextInfo:(void*) contextInfo
{
	if ([[self delegate] respondsToSelector: [self delegateSelector]])
	{    
		NSInvocation *callBackInvocation = [NSInvocation invocationWithMethodSignature: [[self delegate] methodSignatureForSelector: [self delegateSelector]]];
		
		[callBackInvocation setTarget: [self delegate]];
		[callBackInvocation setArgument: &self 
								atIndex: 2];
		[callBackInvocation setArgument: &returnCode 
								atIndex: 3];
		[callBackInvocation setArgument: &contextInfo 
								atIndex: 4];
		[callBackInvocation setSelector: [self delegateSelector]];
		
		[callBackInvocation retainArguments];
		[callBackInvocation performSelector:@selector(invoke) withObject:nil afterDelay:0.0];
	}
	[self autorelease];
}

#pragma mark ----=connection callback=----
- (BOOL)connection:(id <AbstractConnectionProtocol>)con authorizeConnectionToHost:(NSString *)host message:(NSString *)message;
{
	[timer invalidate];
	timer = nil;
	if (NSRunAlertPanel(@"Authorize Connection?", @"%@", @"Yes", @"No", nil, message) == NSOKButton)
		return YES;
	return NO;
}
	
- (void)connection:(AbstractConnection *)aConn didConnectToHost:(NSString *)host
{
	[timer invalidate];
	timer = nil;
	NSString *dir = [self initialDirectory];
	if (dir && [dir length] > 0) 
		[aConn changeToDirectory: dir];
	[aConn directoryContents];
}

- (void)connection:(AbstractConnection *)aConn didDisconnectFromHost:(NSString *)host
{
	NSLog (@"disconnect");
}

- (void)connection:(AbstractConnection *)aConn didReceiveError:(NSError *)error
{
	if ([delegate respondsToSelector:@selector(connectionOpenPanel:didReceiveError:)])
	{
		[delegate connectionOpenPanel:self didReceiveError:error];
	}
	else
	{
		
		NSString *informativeText = [error localizedDescription];
		
		NSAlert *a = [NSAlert alertWithMessageText:LocalizedStringInConnectionKitBundle(@"A Connection Error Occurred", @"ConnectionOpenPanel")
									 defaultButton:LocalizedStringInConnectionKitBundle(@"OK", @"OK")
								   alternateButton:nil
									   otherButton:nil
						 informativeTextWithFormat: informativeText];
		[a runModal];
	}
	
	if ([[self window] isSheet])
		[[NSApplication sharedApplication] endSheet:[self window] returnCode: [error code]];
	else
		[[NSApplication sharedApplication] stopModalWithCode: [error code]];
	
	[self closePanel: nil];
}

- (void)connectionDidSendBadPassword:(AbstractConnection *)aConn
{
	if ([[self window] isSheet])
		[[NSApplication sharedApplication] endSheet:[self window] returnCode: connectionBadPasswordUserName];
	else
		[[NSApplication sharedApplication] stopModalWithCode: connectionBadPasswordUserName];

	if ([delegate respondsToSelector:@selector(connectionOpenPanel:didSendBadPasswordToHost:)])
	{
		[delegate connectionOpenPanel:self didSendBadPasswordToHost:[aConn host]];
	}
	
	[self closePanel:nil];
}

/*- (NSString *)connection:(AbstractConnection *)aConn needsAccountForUsername:(NSString *)username
{
	//	[status setStringValue:[NSString stringWithFormat:@"Need Account for %@ not implemented", username]];
}*/

- (void)connection:(AbstractConnection *)aConn didCreateDirectory:(NSString *)dirPath
{
	[aConn changeToDirectory:dirPath];
	createdDirectory = [[dirPath lastPathComponent] retain]; 
	[aConn directoryContents];
}

- (void)connection:(AbstractConnection *)aConn didSetPermissionsForFile:(NSString *)path
{
	
}

static NSImage *folder = nil;
static NSImage *symFolder = nil;
static NSImage *symFile = nil;
- (void)connection:(AbstractConnection *)aConn didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath
{
	contents = [contents filteredArrayByRemovingHiddenFiles];
	//set the parent directory (in reverse order)
	//
  if ([dirPath hasSuffix:@"/"] && ([dirPath length] > 1))
	{
		dirPath = [dirPath substringToIndex:[dirPath length] - 1];
	}
	NSMutableArray *reverseArray = [NSMutableArray array];
	NSEnumerator *theEnum = [[dirPath pathComponents] reverseObjectEnumerator];
	id currentItem;
	
	while (currentItem = [theEnum nextObject])
	{
		[reverseArray addObject: currentItem];
	}
	
	[parentDirectories setContent: reverseArray];
	[parentDirectories setSelectionIndex: 0];
	
	NSEnumerator *e = [contents objectEnumerator];
	NSDictionary *cur;
	
	[directoryContents removeObjects: [directoryContents content]];
	NSDictionary *selected = nil;
	
	while (cur = [e nextObject])
	{
		if ([[cur objectForKey:cxFilenameKey] characterAtIndex:0] != '.')
		{
			NSMutableDictionary *currentItem = [NSMutableDictionary dictionary];
			[currentItem setObject: cur
							forKey: @"allProperties"];
			[currentItem setObject: [cur objectForKey:cxFilenameKey] 
							forKey: @"fileName"];
			[currentItem setObject: [NSMutableArray array] 
							forKey: @"subItems"];
			if (createdDirectory)
			{
				if ([[cur objectForKey:cxFilenameKey] isEqualToString:createdDirectory])
				{
					selected = currentItem;
				}
			}
			BOOL isLeaf = NO;
			if ([[cur objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink])
			{
				NSLog(@"%@: %@", NSStringFromSelector(_cmd), [cur objectForKey:cxSymbolicLinkTargetKey]);
			}
			if (![[cur objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory] || 
				([[cur objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink] && ![[cur objectForKey:cxSymbolicLinkTargetKey] hasSuffix:@"/"]))
			{
				isLeaf = YES;
			}
			[currentItem setObject: [NSNumber numberWithBool:isLeaf ]
							forKey: @"isLeaf"];
			[currentItem setObject: [dirPath stringByAppendingPathComponent: [cur objectForKey:cxFilenameKey]]
							forKey: @"path"];
			
			BOOL enabled = YES;
			if ([cur objectForKey:NSFileTypeDirectory])
				enabled = [self canChooseDirectories];
			else
			{
				enabled = [self canChooseFiles];
			}
			
			[currentItem setObject: [NSNumber numberWithBool: enabled]
							forKey: @"isEnabled"];
			
			//get the icon
			//
			NSImage *icon = nil;
			if ([[cur objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
			{
				if (!folder)
					folder = [[[NSWorkspace sharedWorkspace] iconForFile:@"/tmp"] retain];
				icon = folder;
			}
			else if ([[cur objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink])
			{
				if (!symFolder || !symFile)
				{
					symFolder = [[NSImage alloc] initWithContentsOfFile: [[NSBundle bundleForClass: [self class]] pathForResource: @"symlink_folder"
																														   ofType:@"tif"]];
					symFile = [[NSImage alloc] initWithContentsOfFile: [[NSBundle bundleForClass: [self class]] pathForResource: @"symlink_file"
																														 ofType:@"tif"]];
				}
				NSString *target = [cur objectForKey:cxSymbolicLinkTargetKey];
				if ([target characterAtIndex:[target length] - 1] == '/' || [target characterAtIndex:[target length] - 1] == '\\')
					icon = symFolder;
				else
				{
					NSImage *fileType = [[NSWorkspace sharedWorkspace] iconForFileType:[[cur objectForKey:cxFilenameKey] pathExtension]];
					NSImage *comp = [[NSImage alloc] initWithSize:NSMakeSize(16,16)];
					[icon setScalesWhenResized:YES];
					[icon setSize:NSMakeSize(16,16)];
					[comp lockFocus];
					[fileType drawInRect:NSMakeRect(0,0,16,16) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
					[symFile drawInRect:NSMakeRect(0,0,16,16) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
					[comp unlockFocus];
					[comp autorelease];
					icon = comp;
				}
			}
			else
			{
				icon = [[NSWorkspace sharedWorkspace] iconForFileType:[[cur objectForKey:cxFilenameKey] pathExtension]];
			}
			[icon setSize:NSMakeSize(16,16)];
			
			if (icon)
				[currentItem setObject: icon
								forKey: @"image"];
			
			
			[directoryContents addObject: currentItem];
		}
		if (selected)
		{
			[directoryContents setSelectedObjects:[NSArray arrayWithObject:selected]];
		}
	}
	
	[self setIsLoading: NO];
}

#pragma mark ----=NStableView delegate=----
- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(int)rowIndex
{
	BOOL returnValue = YES;
	
	if ([[[[directoryContents arrangedObjects] objectAtIndex: rowIndex] valueForKey: @"isLeaf"] boolValue])
	{
		returnValue = [self canChooseFiles];
	}
	else
		returnValue = [self canChooseDirectories];
	
	return returnValue;
}


- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	//disable the cell we can't select
	//
	
	BOOL enabled = YES;
	
	if ([[[[directoryContents arrangedObjects] objectAtIndex: rowIndex] valueForKey: @"isLeaf"] boolValue])
	{
		enabled = [self canChooseFiles];
	}
	else
	{
		enabled = [self canChooseDirectories];
	}
		
	
	[aCell setEnabled: enabled];
	if ([aCell isKindOfClass:[NSTextFieldCell class]])
	{
		NSMutableDictionary *attribs = [NSMutableDictionary dictionary];
		if (enabled)
		{
			[attribs setObject:[NSColor textColor] forKey:NSForegroundColorAttributeName];
		}
		else
		{
			[attribs setObject:[NSColor disabledControlTextColor] forKey:NSForegroundColorAttributeName];
		}
		NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithAttributedString:[aCell attributedStringValue]];
		[str addAttributes:attribs range:NSMakeRange(0,[str length])];
		[aCell setAttributedStringValue:str];
		[str release];
	}
}

@end



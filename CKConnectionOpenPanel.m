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


#import "CKConnectionOpenPanel.h"
#import "CKConnectionProtocol.h"
#import "CKConnectionRegistry.h"

#import "NSArray+Connection.h"


@implementation CKConnectionOpenPanel

- (id)initWithFileTransferSession:(CK2FileTransferSession *)session directoryURL:(NSURL *)url;
{
	NSParameterAssert(session);
    
    if ([super initWithWindowNibName: @"ConnectionOpenPanel"])
	{
		_session = [session retain];
        [self setDirectoryURL:url];
        
        shouldDisplayOpenButton = YES;
        shouldDisplayOpenCancelButton = YES;
        [self setAllowsMultipleSelection: NO];
        [self setCanChooseFiles: YES];
        [self setCanChooseDirectories: YES];
        
        [self setPrompt: [[NSBundle bundleForClass: [self class]] localizedStringForKey: @"open"
                                                                                  value: @"Open"
                                                                                  table: @"localizable"]];
	}
	
	return self;
}

- (void) awakeFromNib
{
	[openButton setHidden:!shouldDisplayOpenButton];
    [openCancelButton setHidden:!shouldDisplayOpenCancelButton];
    
    // Sort directories like the Finder
    if ([NSString instancesRespondToSelector:@selector(localizedStandardCompare:)])
    {
        NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"fileName"
                                                                       ascending:YES
                                                                        selector:@selector(localizedStandardCompare:)];
        
        [directoryContents setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
        [sortDescriptor release];
    }
    
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
	if ([sender tag] && 
		([[directoryContents selectedObjects] count] == 1) && 
		![[[[directoryContents selectedObjects] objectAtIndex: 0] valueForKey: @"isLeaf"] boolValue] &&
		![self canChooseDirectories])
	{
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
		
		NSURL *url = [[self directoryURL] URLByAppendingPathComponent:[self newFolderName] isDirectory:YES];
        
        NSEnumerator *theEnum = [[directoryContents arrangedObjects] objectEnumerator];
		id currentObject = nil;
		
		while ((currentObject = [theEnum nextObject]) && !containsObject)
			containsObject = [[currentObject objectForKey: @"fileName"] isEqualToString: [self newFolderName]];
		
		if (!containsObject)
		{
            [[self session] createDirectoryAtURL:url withIntermediateDirectories:NO completionHandler:^(NSError *error) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    if (error)
                    {
                        [self presentError:error];
                    }
                    else
                    {
                        [self setDirectoryURL:url selectFile:url completionHandler:nil];
                    }
                }];
            }];
		}
		else
		{  
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self setDirectoryURL:url selectFile:nil completionHandler:nil];
            }];
		}
	}
}

- (IBAction)goToFolder:(NSPathControl *)sender
{
    NSPathComponentCell *cell = [sender clickedPathComponentCell];
    [self setDirectoryURL:[cell URL] selectFile:nil completionHandler:nil];
}

- (IBAction) openFolder: (id) sender
{
	if ([sender count])
		if (![[[sender objectAtIndex: 0] valueForKey: @"isLeaf"] boolValue])
		{
            [self setDirectoryURL:[[sender objectAtIndex:0] valueForKey:@"URL"] selectFile:nil completionHandler:nil];
		}
}

#pragma mark ----=accessors=----

@synthesize session = _session;

@synthesize directoryURL = _directory;
- (void)setDirectoryURL:(NSURL *)url;
{
    NSParameterAssert(url);
    
    url = [url copy];
    [_directory release]; _directory = url;
    
    
    // Update UI
    // Need to add icons
    [pathControl setURL:url];
    
    NSMutableArray *componentCells = [[pathControl pathComponentCells] mutableCopy];
    
    // Add in cell for root/home
    NSPathComponentCell *rootCell = [[NSPathComponentCell alloc] initTextCell:[url host]];
    NSURL *rootURL = ([componentCells count] > 0 ? [[[componentCells objectAtIndex:0] URL] URLByDeletingLastPathComponent] : url);
    [rootCell setURL:rootURL];
    [componentCells insertObject:rootCell atIndex:0];
    [rootCell release];
    
    NSImage *folderIcon = [[NSWorkspace sharedWorkspace] iconForFileType:(NSString *)kUTTypeFolder];
    
    for (NSPathComponentCell *aCell in componentCells)
    {
        [aCell setImage:folderIcon];
    }
    
    [pathControl setPathComponentCells:componentCells];
    [componentCells release];
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
        id<CKPublishingConnection> connection = [self connection];
        NSString *rootDirectory = [connection rootDirectory];
		if (([pathToAdd rangeOfString: rootDirectory].location == 0) &&
			(![pathToAdd isEqualToString: rootDirectory]))
			[returnValue addObject: [pathToAdd substringFromIndex: [rootDirectory length] + 1]];
		else if ([pathToAdd isEqualToString: rootDirectory])
			[returnValue addObject: @""];
		else  //we have up back to before the root directory path needs ../ added
		{
			NSString *pathPrefix = @"";
			while ([pathToAdd rangeOfString: rootDirectory].location == NSNotFound)
			{
				pathPrefix = [pathPrefix stringByAppendingPathComponent: @"../"];
				rootDirectory = [rootDirectory stringByDeletingLastPathComponent];
			}
			pathToAdd = [pathPrefix stringByAppendingPathComponent: pathToAdd];
			
			[returnValue addObject:[NSURL URLWithString:pathToAdd relativeToURL:[[connection request] URL]]];
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

- (void)timedOut:(NSTimer *)timer
{
	[self closePanel: nil];
}

//=========================================================== 
// dealloc
//=========================================================== 
- (void)dealloc
{
	[tableView setDelegate: nil];
	[self setNewFolderName:nil];
	[self setPrompt:nil];
	[self setAllowedFileTypes:nil];
    
    [_session release];
    [_directory release];
	
	[super dealloc];
}

#pragma mark ----=running the dialog=----

- (void)beginSheetModalForWindow:(NSWindow *)docWindow completionHandler:(void (^)(NSInteger))handler;
{
    //force the window to be loaded, to be sure tableView is set
    //
    [self window];
    
	[directoryContents setAvoidsEmptySelection: ![self canChooseDirectories]];
	[tableView setAllowsMultipleSelection: [self allowsMultipleSelection]];
	
	[self retain];
	
	[[NSApplication sharedApplication] beginSheet:[self window]
                                   modalForWindow:docWindow
                                    modalDelegate:self
                                   didEndSelector:@selector(directorySheetDidEnd:returnCode:contextInfo:)
                                      contextInfo:[handler copy]];
    
	
	[self setIsLoading: YES];
    
    [self setDirectoryURL:[self directoryURL] selectFile:nil completionHandler:nil];
}

- (void)setDirectoryURL:(NSURL *)url selectFile:(NSURL *)file completionHandler:(void (^)(NSError *error))block;
{
    [self setIsLoading: YES];
    
    [[self session] contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles completionHandler:^(NSArray *contents, NSURL *dir, NSError *error) {
        
        // An error is most likely the folder not existing, so try loading up the home directory
        if ([contents count] == 0 && error && [[dir path] length] > 0)
        {
            [self setDirectoryURL:[NSURL URLWithString:@"/" relativeToURL:url] selectFile:nil completionHandler:block];
            return;
        }
        else if (error)
        {
            if (block) block(error);
            
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self presentError:error];
            }];
            
            return;
        }
        
        
        [self setDirectoryURL:dir];
        
        
        // Populate the file list
        [directoryContents setContent:nil];
        
        for (NSURL *aURL in contents)
        {
            NSMutableDictionary *currentItem = [NSMutableDictionary dictionary];
            [currentItem setObject:[NSMutableArray array] forKey:@"subItems"];
            
            NSString *filename = [aURL lastPathComponent];
            [currentItem setObject:filename forKey:@"fileName"];
            
            NSNumber *isSymlink;
            if ([aURL getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:NULL] && [isSymlink boolValue])
            {
                //NSLog(@"%@: %@", NSStringFromSelector(_cmd), [cur objectForKey:cxSymbolicLinkTargetKey]);
            }
            else
            {
                isSymlink = nil;
            }
            
            BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)aURL);   // TODO: use proper resource value
            
            [currentItem setObject:aURL forKey:@"URL"];
            
            BOOL enabled = (isDirectory ? [self canChooseDirectories] : [self canChooseFiles]);
            [currentItem setObject:[NSNumber numberWithBool:enabled] forKey:@"isEnabled"];
            
            //get the icon
            NSImage *icon;
            if (isDirectory)
            {
                static NSImage *folder;
                if (!folder)
                {
                    folder = [[[NSWorkspace sharedWorkspace] iconForFile:@"/tmp"] copy];
                    [folder setSize:NSMakeSize(16,16)];
                }
                
                icon = folder;
            }
            else if (isSymlink)
            {
                static NSImage *symFolder;
                if (!symFolder)
                {
                    NSBundle *bundle = [NSBundle bundleForClass:[CKConnectionOpenPanel class]]; // hardcode class incase app subclasses
                    symFolder = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"symlink_folder" ofType:@"tif"]];
                    [symFolder setSize:NSMakeSize(16,16)];
                }
                static NSImage *symFile;
                if (!symFile)
                {
                    NSBundle *bundle = [NSBundle bundleForClass:[CKConnectionOpenPanel class]]; // hardcode class incase app subclasses
                    symFile = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"symlink_file" ofType:@"tif"]];
                    [symFile setSize:NSMakeSize(16,16)];
                }
                
                NSString *target = nil;//[cur objectForKey:cxSymbolicLinkTargetKey];
                if ([target hasSuffix:@"/"] || [target hasSuffix:@"\\"])
                {
                    icon = symFolder;
                }
                else
                {
                    NSImage *fileType = [[NSWorkspace sharedWorkspace] iconForFileType:[filename pathExtension]];
                    NSImage *comp = [[NSImage alloc] initWithSize:NSMakeSize(16,16)];
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
                NSString *extension = [filename pathExtension];
                icon = [[[[NSWorkspace sharedWorkspace] iconForFileType:extension] copy] autorelease];  // copy so can mutate
                [icon setSize:NSMakeSize(16,16)];
            }
            
            if (icon) [currentItem setObject:icon forKey:@"image"];
            
            
            // Select the directory that was just created (if there is one)
            if ([filename isEqualToString:[file lastPathComponent]]) [directoryContents setSelectsInsertedObjects:YES];
            
            // Actually insert the listed item
            [directoryContents addObject:currentItem];
            [directoryContents setSelectsInsertedObjects:NO];
        }
        
        
        // Want the list sorted like the Finder does
        [directoryContents rearrangeObjects];
        
        [self setIsLoading: NO];
        
        
        // Callback
        if (block) block(error);
    }];
}

- (NSInteger)runModal
{
  //force the window to be loaded, to be sure tableView is set
  //
  [self window];
  
	[directoryContents setAvoidsEmptySelection: ![self canChooseDirectories]];
	[tableView setAllowsMultipleSelection: [self allowsMultipleSelection]];
	
	//int ret = [[NSApplication sharedApplication] runModalForWindow: [self window]];
	
	myKeepRunning = YES;
	myModalSession = [[NSApplication sharedApplication] beginModalSessionForWindow:[self window]];
		
	[self setIsLoading: YES];
	
	NSInteger ret;
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

- (void)directorySheetDidEnd:(NSWindow *)inSheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    void (^block)(NSInteger result) = contextInfo;
    
    if (block)
    {
        block(returnCode);
        [block release];
    }
    
	[self autorelease];
}

#pragma mark ----=NStableView delegate=----

- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
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


- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
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



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

- (id)initWithFileTransferSession:(CK2FileManager *)session directoryURL:(NSURL *)url;
{
	NSParameterAssert(session);
    
    if (self = [self initWithWindowNibName: @"ConnectionOpenPanel"])
	{
		_session = [session retain];
        [self setDirectoryURL:url];
        
        _shouldDisplayOpenButton = YES;
        _shouldDisplayOpenCancelButton = YES;
        [self setAllowsMultipleSelection: NO];
        [self setCanChooseFiles: YES];
        [self setCanChooseDirectories: YES];
        
        [self setPrompt: [[NSBundle bundleForClass: [self class]] localizedStringForKey: @"open"
                                                                                  value: @"Open"
                                                                                  table: @"localizable"]];
	}
	
	return self;
}

- (void)awakeFromNib
{
	[openButton setHidden:![self shouldDisplayOpenButton]];
    [openCancelButton setHidden:![self shouldDisplayOpenCancelButton]];
    
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
      NSURL *url = [[[directoryContents selectedObjects] objectAtIndex:0] valueForKey:@"URL"];
      if ([[self class] isDirectory:url])
      {
          [self setIsSelectionValid: [self canChooseDirectories]];
          
          if ([self canChooseDirectories])
          {
              [self setPrompt:[[NSBundle bundleForClass:[self class]] localizedStringForKey:@"select"
                                                                                      value:@"Select"
                                                                                      table:@"localizable"]];
          }
          else
          {
              [self setPrompt:[[NSBundle bundleForClass:[self class]] localizedStringForKey:@"open"
                                                                                      value:@"Open"
                                                                                      table:@"localizable"]];
          }
      }
      else
      {
          [self setIsSelectionValid:[self canChooseFiles]];
      }
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
        NSURL *url = [[[directoryContents selectedObjects] objectAtIndex:0] valueForKey:@"URL"];
        wholeSelectionIsValid = ([[self class] isDirectory:url] ? [self canChooseDirectories] : [self canChooseFiles]);
    }
    [self setIsSelectionValid:wholeSelectionIsValid];
  }
}

#pragma mark ----=actions=----

- (IBAction) closePanel: (id) sender
{
  //invalidate the timer in case the user dismiss the panel before the connection happened
  //
	if ([sender tag] && 
		([[directoryContents selectedObjects] count] == 1) && 
		[[self class] isDirectory:[[[directoryContents selectedObjects] objectAtIndex:0] valueForKey:@"URL"]] &&
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

- (IBAction)goToFolder:(NSPathControl *)sender
{
    NSPathComponentCell *cell = [sender clickedPathComponentCell];
    [self setDirectoryURL:[cell URL] selectFile:nil completionHandler:nil];
}

- (IBAction) openFolder: (id) sender
{
	if ([sender count])
    {
        NSURL *url = [[sender objectAtIndex: 0] valueForKey:@"URL"];
		if ([[self class] isDirectory:url])
		{
            [self setDirectoryURL:url selectFile:nil completionHandler:nil];
		}
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
    NSImage *folderIcon = [NSImage imageNamed:NSImageNameFolder];
    
    for (NSPathComponentCell *aCell in componentCells)
    {
        [aCell setImage:folderIcon];
    }
    
    
    // Add in cell for root/home
    NSString *path = [CK2FileManager pathOfURLRelativeToHomeDirectory:url];
    
    NSURL *rootURL = ([path isAbsolutePath] ?
                      [CK2FileManager URLWithPath:@"/" relativeToURL:url] :
                      [CK2FileManager URLWithPath:@"" relativeToURL:[NSURL URLWithString:@"/" relativeToURL:url]]);
    
    NSPathComponentCell *rootCell = [[NSPathComponentCell alloc] initTextCell:[url host]];
    [rootCell setURL:rootURL];
    
    NSString *type = NSFileTypeForHFSTypeCode([path isAbsolutePath] ? kGenericFileServerIcon : kUserFolderIcon);
    [rootCell setImage:[[NSWorkspace sharedWorkspace] iconForFileType:type]];
    
    [componentCells insertObject:rootCell atIndex:0];
    [rootCell release];
    
    [pathControl setPathComponentCells:componentCells];
    [componentCells release];
}

@synthesize canChooseDirectories = _canChooseDirectories;
@synthesize canChooseFiles = _canChooseFiles;
@synthesize canCreateDirectories = _canCreateDirectories;
@synthesize shouldDisplayOpenButton = _shouldDisplayOpenButton;
@synthesize shouldDisplayOpenCancelButton = _shouldDisplayOpenCancelButton;
@synthesize allowsMultipleSelection = _allowsMultipleSelection;
@synthesize prompt = _prompt;
@synthesize allowedFileTypes = _allowedFileTypes;


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
    
	if ([selectedFiles count])
    {
        return [selectedFiles valueForKey:@"URL"];
    }
    else
    {
        return [NSArray arrayWithObject:[self directoryURL]];
    }
}

//=========================================================== 
// dealloc
//=========================================================== 
- (void)dealloc
{
	[tableView setDelegate: nil];
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
    
    [self setDirectoryURL:[self directoryURL] selectFile:nil completionHandler:nil];
}

- (void)setDirectoryURL:(NSURL *)url selectFile:(NSURL *)file completionHandler:(void (^)(NSError *error))block;
{
    [self setIsLoading: YES];
    
    NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsHiddenFiles|NSDirectoryEnumerationSkipsSubdirectoryDescendants;
    NSMutableArray *contents = [[NSMutableArray alloc] init];
    
    [[self session] enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *url) {
        
        [contents addObject:url];
        
    } completionHandler:^(NSError *error) {
        
        // Quick faff to separate out directory URL and real contents
        NSURL *dir = nil;
        if ([contents count] > 0)
        {
            dir = [[[contents objectAtIndex:0] copy] autorelease];
            [contents removeObjectAtIndex:0];
        }
        
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
        
        
        // Populate the file list. Deals with array controller for UI so needs to run on main thread
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            
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
                
                [currentItem setObject:aURL forKey:@"URL"];
                
                BOOL isDirectory = [[self class] isDirectory:aURL];
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
                    static NSImage *symFile;
                    if (!symFile)
                    {
                        NSBundle *bundle = [NSBundle bundleForClass:[CKConnectionOpenPanel class]]; // hardcode class incase app subclasses
                        symFile = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"symlink_file" ofType:@"tif"]];
                        [symFile setSize:NSMakeSize(16,16)];
                    }
                    
                    NSURL *target;
                    if ([aURL getResourceValue:&target forKey:CK2URLSymbolicLinkDestinationKey error:NULL] &&
                        target &&
                        [[self class] isDirectory:target])
                    {
                        static NSImage *symFolder;
                        if (!symFolder)
                        {
                            NSBundle *bundle = [NSBundle bundleForClass:[CKConnectionOpenPanel class]]; // hardcode class incase app subclasses
                            symFolder = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"symlink_folder" ofType:@"tif"]];
                            [symFolder setSize:NSMakeSize(16,16)];
                        }
                        
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
    }];
}

+ (BOOL)isDirectory:(NSURL *)url;
{
    NSNumber *isDirectory;
    if ([url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL] && isDirectory)
    {
        return [isDirectory boolValue];
    }
    
    // Fallback to guessing from the URL
    return CFURLHasDirectoryPath((CFURLRef)url);
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
	
	NSInteger ret = NSRunContinuesResponse;
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

#pragma mark Creating a Folder

- (void)createNewFolder:(NSButton *)sender;
{
	[[NSApplication sharedApplication] stopModal];
	[createFolder orderOut:sender];
	
	if ([sender tag] == NSOKButton)
	{
		//check that a folder with the same name does not exiss
		//
		BOOL containsObject = NO;
		
        NSString *folderName = [folderNameField stringValue];
		NSURL *url = [[self directoryURL] URLByAppendingPathComponent:folderName isDirectory:YES];
        
        NSEnumerator *theEnum = [[directoryContents arrangedObjects] objectEnumerator];
		id currentObject = nil;
		
		while ((currentObject = [theEnum nextObject]) && !containsObject)
			containsObject = [[currentObject objectForKey:@"fileName"] isEqualToString:folderName];
		
		if (!containsObject)
		{
            [[self session] createDirectoryAtURL:url withIntermediateDirectories:NO openingAttributes:nil completionHandler:^(NSError *error) {
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

- (void)controlTextDidChange:(NSNotification *)notification;
{
    if ([notification object] == folderNameField)
    {
        [createFolderButton setEnabled:[[folderNameField stringValue] length] > 0];
    }
}

#pragma mark ----=NStableView delegate=----

- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
{
	NSURL *url = [[[directoryContents arrangedObjects] objectAtIndex:rowIndex] valueForKey:@"URL"];
	BOOL returnValue = ([[self class] isDirectory:url] ? [self canChooseDirectories] : [self canChooseFiles]);
	return returnValue;
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	//disable the cell we can't select
	//
	
	NSURL *url = [[[directoryContents arrangedObjects] objectAtIndex:rowIndex] valueForKey:@"URL"];
	BOOL enabled = ([[self class] isDirectory:url] ? [self canChooseDirectories] : [self canChooseFiles]);
    
	
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



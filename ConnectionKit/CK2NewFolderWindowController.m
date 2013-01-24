//
//  CK2NewFolderWindowWindowController.m
//  Connection
//
//  Created by Paul Kim on 1/22/13.
//
//

#import "CK2NewFolderWindowController.h"

@interface CK2NewFolderWindowController ()

@property (readwrite, copy) NSString        *folderName;

@end

@implementation CK2NewFolderWindowController

@synthesize folderName = _folderName;
@synthesize existingNames = _existingNames;

- (id)init
{
    if ((self = [super initWithWindowNibName:@"CK2NewFolderWindow"]) != nil)
    {
    }
    
    return self;
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    NSText      *fieldEditor;
    NSString    *string;
    BOOL        nameExists;
    
    fieldEditor = [[aNotification userInfo] objectForKey:@"NSFieldEditor"];
    
    string = [fieldEditor string];
    
    nameExists = [_existingNames containsObject:string];
    
    [_statusField setHidden:!nameExists];
    [_okButton setEnabled:([string length] != 0) && !nameExists];
    
    //PENDING:
    //Replace ':' with '-'
}

- (void)endWithCode:(NSInteger)code
{
    NSWindow    *window;
    
    window = [self window];
    [window close];
    
    if ([window isModalPanel])
    {
        [NSApp stopModalWithCode:code];
    }
}

- (IBAction)ok:(id)sender
{
    [self setFolderName:[_nameField stringValue]];
    [self endWithCode:NSOKButton];
}

- (IBAction)cancel:(id)sender
{
    [self endWithCode:NSCancelButton];
}

@end

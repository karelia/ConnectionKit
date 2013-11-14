//
//  CK2NewFolderWindowWindowController.m
//  Connection
//
//  Created by Paul Kim on 1/22/13.
//
//

#import "CK2NewFolderWindowController.h"
#import "CK2OpenPanelController.h"
#import <ConnectionKit/CK2FileManager.h>

#define DEFAULT_NAME        @"untitled folder"

@interface CK2NewFolderWindowController ()

@property (readwrite, retain) NSURL           *folderURL;
@property (readwrite, retain) NSError       *error;

@end

@implementation CK2NewFolderWindowController

@synthesize folderURL = _folderURL;
@synthesize error = _error;

- (id)initWithController:(CK2OpenPanelController *)controller
{
    if ((self = [super initWithWindowNibName:@"CK2NewFolderWindow"]) != nil)
    {
        _controller = controller;
    }
    
    return self;
}

- (void)dealloc
{
    [_operation cancel];
    [_operation release];
    [_folderURL release];
    [_error release];
    [_existingNames release];
    
    [super dealloc];
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

- (BOOL)runModalForURL:(NSURL *)url
{
    NSArray     *children;
    NSInteger   resultCode;
    NSString    *name;
    NSUInteger  i;
    
    [self setFolderURL:url];
    children = [_controller childrenForURL:url];
    _existingNames = [[children valueForKey:@"lastPathComponent"] retain];
    
    name = DEFAULT_NAME;
    i = 2;
    while ([_existingNames containsObject:name])
    {
        name = [NSString stringWithFormat:@"%@ %lu", DEFAULT_NAME, (unsigned long)i++];
    }
    // Window may not be loaded yet.
    [self window];
    
    [_nameField setStringValue:name];

    resultCode = [NSApp runModalForWindow:[self window]];

    return ((resultCode == NSOKButton) && (_error == nil));
}


- (void)endWithCode:(NSInteger)code
{
    NSWindow    *window;
    
    [_progressIndicator stopAnimation:self];

    window = [self window];
    [window close];
    [_operation release];
    _operation = nil;
    [_existingNames release];
    _existingNames = nil;

    if ([window isModalPanel])
    {
        [NSApp stopModalWithCode:code];
    }
}

- (void)doIt:sender
{
    [self endWithCode:NSOKButton];
}

- (IBAction)ok:(id)sender
{
    NSString    *folderName;
    NSURL       *url, *parentURL;
    
    folderName = [_nameField stringValue];
    parentURL = [self folderURL];
    url = [parentURL URLByAppendingPathComponent:folderName isDirectory:YES];
    // Need to set this since the url is not vended by CK2
    [CK2FileManager setTemporaryResourceValue:parentURL forKey:NSURLParentDirectoryURLKey inURL:url];
    
    [_okButton setEnabled:NO];
    
    _operation = [[[_controller fileManager] createDirectoryAtURL:url withIntermediateDirectories:NO openingAttributes:nil completionHandler:
     ^(NSError *blockError)
     {
         NSEvent     *event;
                  
             [self setError:blockError];
             [self setFolderURL:url];
             [self endWithCode:NSOKButton];
             
             [_okButton setEnabled:YES];
         
         // It seems that the run loop doesn't wake up after ending the modal session from a block (also happens with
         // -performSelectorOnMainThread:) so we create a fake event here to "jiggle its rat" (rdar://13079612)
         event = [NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:[[self window] windowNumber] context:NULL subtype:NSApplicationDefined data1:0 data2:0];
         [NSApp postEvent:event atStart:YES];

     }] retain];
    
    [_progressIndicator startAnimation:self];
}

- (IBAction)cancel:(id)sender
{
    [_operation cancel];
    [self endWithCode:NSCancelButton];
}

@end

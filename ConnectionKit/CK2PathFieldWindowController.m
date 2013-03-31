//
//  CK2PathFieldWindowController.m
//  Connection
//
//  Created by Paul Kim on 3/25/13.
//
//

#import "CK2PathFieldWindowController.h"

@interface CK2PathFieldWindowController ()

@end

@implementation CK2PathFieldWindowController

@synthesize stringValue = _stringValue;

- (id)init
{
    if ((self = [super initWithWindowNibName:@"CK2PathFieldWindow"]) != nil)
    {
    }
    
    return self;
}


- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSInteger result))handler
{
    NSWindow        *sheet;
    NSText          *fieldEditor;
    NSString        *string;
    
    sheet = [self window];
    string = [self stringValue];
    [_field setStringValue:string];
    [sheet makeFirstResponder:_field];
    
    fieldEditor = [sheet fieldEditor:YES forObject:_field];
    [fieldEditor setSelectedRange:NSMakeRange([string length], 0)];

    [NSApp beginSheet:sheet modalForWindow:window modalDelegate:self didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:[handler copy]];
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [sheet orderOut:self];
 
    if (returnCode == NSOKButton)
    {
        [self setStringValue:[_field stringValue]];
    }

    if (contextInfo != NULL)
    {
        void    (^block)(NSInteger);
        
        block = contextInfo;
        block(returnCode);
        [block release];
    }
}

- (IBAction)cancel:(id)sender
{
    [NSApp endSheet:[self window] returnCode:NSCancelButton];
}

- (IBAction)go:(id)sender
{
    [NSApp endSheet:[self window] returnCode:NSOKButton];
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    NSText      *fieldEditor;
    NSString    *string;
    
    fieldEditor = [[aNotification userInfo] objectForKey:@"NSFieldEditor"];
    
    string = [fieldEditor string];
    
    [_goButton setEnabled:([string length] != 0)];
}

@end

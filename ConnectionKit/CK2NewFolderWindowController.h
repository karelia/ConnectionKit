//
//  CK2NewFolderWindowWindowController.h
//  Connection
//
//  Created by Paul Kim on 1/22/13.
//
//

#import <Cocoa/Cocoa.h>

@interface CK2NewFolderWindowController : NSWindowController
{
    IBOutlet NSTextField    *_nameField;
    IBOutlet NSButton       *_okButton;
    IBOutlet NSTextField    *_statusField;
    NSString                *_folderName;
    NSArray                 *_existingNames;
}

@property (readwrite, copy) NSArray         *existingNames;
@property (readonly, copy) NSString        *folderName;


- (id)init;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;

@end

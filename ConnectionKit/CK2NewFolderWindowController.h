//
//  CK2NewFolderWindowWindowController.h
//  Connection
//
//  Created by Paul Kim on 1/22/13.
//
//

#import <ConnectionKit/ConnectionKit.h>

@class CK2OpenPanelController;

@interface CK2NewFolderWindowController : NSWindowController
{
    IBOutlet NSTextField                *_nameField;
    IBOutlet NSButton                   *_okButton;
    IBOutlet NSTextField                *_statusField;
    IBOutlet NSProgressIndicator        *_progressIndicator;
    
    CK2OpenPanelController              *_controller;
    NSURL                               *_folderURL;
    NSArray                             *_existingNames;
    CK2FileOperation                    *_operation;
    NSError                             *_error;
}

@property (readonly, retain) NSURL      *folderURL;
@property (readonly, retain) NSError    *error;

- (id)initWithController:(CK2OpenPanelController *)controller;;

- (BOOL)runModalForURL:(NSURL *)url;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;

@end

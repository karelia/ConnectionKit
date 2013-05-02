//
//  CK2PathFieldWindowController.h
//  Connection
//
//  Created by Paul Kim on 3/25/13.
//
//

#import <Cocoa/Cocoa.h>

@interface CK2PathFieldWindowController : NSWindowController
{
    IBOutlet NSTextField        *_field;
    IBOutlet NSButton           *_goButton;
    NSString                    *_stringValue;
}

@property (readwrite, copy) NSString    *stringValue;

- (id)init;

- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSInteger result))handler;

- (IBAction)go:(id)sender;
- (IBAction)cancel:(id)sender;

@end

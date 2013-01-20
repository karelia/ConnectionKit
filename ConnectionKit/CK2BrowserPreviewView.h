//
//  CK2BrowserPreviewView.h
//  Connection
//
//  Created by Paul Kim on 1/18/13.
//
//

#import <Cocoa/Cocoa.h>

@interface CK2BrowserPreviewView : NSView
{
    IBOutlet NSImageView        *_iconView;
    IBOutlet NSTextField        *_nameField;
    IBOutlet NSTextField        *_kindField;
    IBOutlet NSTextField        *_sizeField;
    IBOutlet NSTextField        *_dateModifiedField;
    IBOutlet NSTextField        *_nameLabel;
    IBOutlet NSTextField        *_kindLabel;
    IBOutlet NSTextField        *_sizeLabel;
    IBOutlet NSTextField        *_dateModifiedLabel;
    
    NSRect                      _separatorRect;
    NSGradient                  *_separatorGradient;
}

- (void)setURL:(NSURL *)url;

@end

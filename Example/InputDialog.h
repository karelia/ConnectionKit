/* InputDialog */

#import <Cocoa/Cocoa.h>

@interface InputDialog : NSObject
{
    IBOutlet id input;
    IBOutlet id panel;
    IBOutlet id title;
	
	id _del;
	SEL _sel;
}
- (id)init;

- (IBAction)cancel:(id)sender;
- (IBAction)ok:(id)sender;
- (void)setDialogTitle:(NSString *)str;

//must respond to input: receivedValue:
- (void)beginSheetModalForWindow:(NSWindow *)win delegate:(id)delegate selector:(SEL)sel;

@end

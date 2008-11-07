#import "InputDialog.h"

@implementation InputDialog

- (id)init
{
	[super init];
	[NSBundle loadNibNamed:@"InputDialog" owner:self];
	return self;
}

- (IBAction)cancel:(id)sender
{
	[panel orderOut:self];
	[NSApp endSheet:panel];
	[_del performSelector:_sel withObject:nil];
}

- (IBAction)ok:(id)sender
{
	[panel orderOut:self];
	[NSApp endSheet:panel];
	
	[_del performSelector:_sel withObject:[input stringValue]];
}

- (void)setDialogTitle:(NSString *)str
{
	[title setStringValue:str];
}

- (void)beginSheetModalForWindow:(NSWindow *)win delegate:(id)delegate selector:(SEL)sel
{
	_del = delegate;
	_sel = sel;
	[NSApp beginSheet:panel
	   modalForWindow:win
		modalDelegate:nil
	   didEndSelector:nil
		  contextInfo:nil];
}
@end

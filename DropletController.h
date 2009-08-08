/* DropletController */

#import <Cocoa/Cocoa.h>
#import <Connection/Connection.h>

@interface DropletController : NSObject
{
    IBOutlet NSButton *oCancel;
    IBOutlet NSTextField *oPassword;
    IBOutlet NSWindow *oPasswordPanel;
    IBOutlet NSTextField *oPasswordText;
    IBOutlet NSProgressIndicator *oProgressBar;
    IBOutlet NSTextField *oStatus;
    IBOutlet NSWindow *oWindow;
	IBOutlet NSOutlineView *oFiles;
	IBOutlet NSButton *oToggleFiles;
	
	CKHost *myHost;
	id <CKConnection>myConnection;
	NSArray *myFilesDropped;
	NSMutableArray *myTransfers;
}
- (IBAction)cancelPassword:(id)sender;
- (IBAction)cancelUpload:(id)sender;
- (IBAction)connectPassword:(id)sender;
- (IBAction)toggleFiles:(id)sender;
@end

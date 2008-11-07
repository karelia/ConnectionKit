/* Controller */

#import <Cocoa/Cocoa.h>

@class InputDialog;
@protocol AbstractConnectionProtocol;

@interface Controller : NSObject
{
    IBOutlet NSButton *btnConnect;
    IBOutlet NSButton *btnDelete;
    IBOutlet NSButton *btnNewFolder;
    IBOutlet NSButton *btnPermissions;
    IBOutlet NSButton *btnRefresh;
    IBOutlet NSButton *btnStop;
    IBOutlet NSButton *cBtnCancel;
    IBOutlet NSButton *cBtnConnect;
    IBOutlet NSTextField *cHost;
    IBOutlet NSPanel *connectWindow;
    IBOutlet NSTextField *cPass;
    IBOutlet NSTextField *cPort;
    IBOutlet NSPopUpButton *cTypePopup;
    IBOutlet NSTextField *cURL;
    IBOutlet NSTextField *cUser;
    IBOutlet NSPopUpButton *localPopup;
    IBOutlet NSTableView *localTable;
    IBOutlet NSPopUpButton *remotePopup;
    IBOutlet NSTableView *remoteTable;
    IBOutlet NSTextField *status;
    IBOutlet NSTableView *transferTable;
    IBOutlet NSWindow *window;
	IBOutlet NSDrawer *logDrawer;
	IBOutlet NSTextView *log;
	IBOutlet NSOutlineView *savedHosts;
	IBOutlet NSButton *btnDisconnect;
	IBOutlet NSTextField *initialDirectory;
	IBOutlet NSTextView *fileCheckLog;
	IBOutlet NSButton *btnBrowseHost;
	IBOutlet NSButton *btnEdit;
	IBOutlet NSPopUpButton *oConMenu;
	
	id <AbstractConnectionProtocol> con;
	NSMutableArray *remoteFiles;
	NSMutableArray *localFiles;
	NSMutableArray *transfers;
	NSString *currentLocalPath;
	NSString *currentRemotePath;
	
	int downloadCounter;
	int uploadCounter;
	BOOL isConnected;
	
	NSMutableArray *_savedHosts;
	id selectedItem;
	InputDialog *check;
}
- (IBAction)cancelConnect:(id)sender;
- (IBAction)connect:(id)sender;
- (IBAction)deleteFile:(id)sender;
- (IBAction)localFileSelected:(id)sender;
- (IBAction)localPopupChanged:(id)sender;
- (IBAction)newFolder:(id)sender;
- (IBAction)permissions:(id)sender;
- (IBAction)refresh:(id)sender;
- (IBAction)remoteFileSelected:(id)sender;
- (IBAction)remotePopupChanged:(id)sender;
- (IBAction)showConnect:(id)sender;
- (IBAction)stopTransfer:(id)sender;
- (IBAction)transferSelected:(id)sender;
@end

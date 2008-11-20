/* SSHPassphrase */

#import <Cocoa/Cocoa.h>

@interface CKSSHPassphrase : NSObject
{
    IBOutlet NSTextField *oKeyLocation;
    IBOutlet NSPanel *oPanel;
    IBOutlet NSSecureTextField *oPassword;
    IBOutlet NSButton *oSave;
	
	NSString *myFormat;
}

- (NSString *)passphraseForPublicKey:(NSString *)pkPath account:(NSString *)account;

@end

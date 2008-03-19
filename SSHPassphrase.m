#import "SSHPassphrase.h"
#import "EMKeychainProxy.h"

@implementation SSHPassphrase

- (id)init
{
	if (self = [super init])
	{
		[NSBundle loadNibNamed:@"Passphrase" owner:self];
	}
	return self;
}

- (void)dealloc
{
	[myFormat release];
	[super dealloc];
}

- (void)awakeFromNib
{
	myFormat = [[NSString alloc] initWithString:[oKeyLocation stringValue]];
}

- (NSString *)passphraseForPublicKey:(NSString *)pkPath account:(NSString *)username
{
	NSString *passphrase = nil;
	[oKeyLocation setStringValue:[NSString stringWithFormat:myFormat, pkPath]];
	[oPassword setStringValue:@""];
	[oSave setState:NSOnState];
	
	[oPanel center];
	[oPanel makeKeyAndOrderFront:self];
	int rc = [NSApp runModalForWindow:oPanel];
	[oPanel orderOut:self];
	
	if (rc == NSOKButton)
	{
		passphrase = [[[oPassword stringValue] copy] autorelease];
		if (!passphrase) passphrase = @"";
		
		if ([oSave state] == NSOnState)
		{
			//If it already exists, just update the password
			EMGenericKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] genericKeychainItemForService:@"SSH" withUsername:pkPath];
			if (keychainItem)
			{
				[keychainItem setPassword:passphrase];
			}
			else
			{
				//save to keychain
				[[EMKeychainProxy sharedProxy] addGenericKeychainItemForService:@"SSH" withUsername:pkPath password:passphrase];
			}
		}
	}

	return passphrase;
}

- (IBAction)cancel:(id)sender
{
	[NSApp stopModalWithCode:NSCancelButton];
}

- (IBAction)unlock:(id)sender
{
	[NSApp stopModalWithCode:NSOKButton];
}

@end

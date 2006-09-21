#import "SSHPassphrase.h"
#import <Carbon/Carbon.h>
#import <Security/Security.h>

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

- (NSString *)passphraseFromKeychainWithPublicKey:(NSString *)pkPath account:(NSString *)username
{
	SecKeychainSearchRef search = nil;
    SecKeychainItemRef item = nil;
    SecKeychainAttributeList list;
    SecKeychainAttribute attributes[4];
    OSErr result;
    char *desc = "SSH Public Key Password";
				
	attributes[0].tag = kSecAccountItemAttr;
	attributes[0].data = (void *)[username UTF8String];
	attributes[0].length = strlen(attributes[0].data);
				
	attributes[1].tag = kSecCommentItemAttr;
	attributes[1].data = (void *)[pkPath UTF8String];
	attributes[1].length = strlen(attributes[1].data);
				
	attributes[2].tag = kSecDescriptionItemAttr;
	attributes[2].data = (void *)desc;
	attributes[2].length = strlen(desc);
				
	NSString *label = [NSString stringWithFormat:@"%@ (%@)", username, [pkPath lastPathComponent]];
				
	attributes[3].tag = kSecLabelItemAttr;
	attributes[3].data = (void *)[label UTF8String];
	attributes[3].length = strlen(attributes[3].data);
	
    list.count = 4;
    list.attr = &attributes[0];
	
    result = SecKeychainSearchCreateFromAttributes(NULL, kSecGenericPasswordItemClass, &list, &search);
	
    if (result != noErr) {
        NSLog (@"status %d from SecKeychainSearchCreateFromAttributes\n", result);
    }
	
	NSString *password = nil;
    if (SecKeychainSearchCopyNext (search, &item) == noErr) {
		UInt32 length;
		char *pass;
		SecKeychainAttribute attributes[4];
		SecKeychainAttributeList list;
		OSStatus status;
		
		attributes[0].tag = kSecAccountItemAttr;
		attributes[1].tag = kSecDescriptionItemAttr;
		attributes[2].tag = kSecLabelItemAttr;
		attributes[3].tag = kSecModDateItemAttr;
		
		list.count = 4;
		list.attr = attributes;
		
		status = SecKeychainItemCopyContent (item, NULL, &list, &length, (void **)&pass);
		
		// length  may be zero, it just means a zero-length password
		password = [NSString stringWithCString:pass length:length];

	}
	if (item) CFRelease(item);
	if (search) CFRelease (search);
	
	return password;
}

- (NSString *)passphraseForPublicKey:(NSString *)pkPath account:(NSString *)username
{
	NSString *passphrase = nil;		// if passphrase not found or entered, we return nil to cancel the operation
	
	passphrase = [self passphraseFromKeychainWithPublicKey:pkPath account:username];
	
	if (!passphrase)
	{
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
				//save to keychain
				SecKeychainAttribute attributes[4];
				SecKeychainAttributeList list;
				SecKeychainItemRef item;
				OSStatus status;
				char *desc = "SSH Public Key Password";
				
				attributes[0].tag = kSecAccountItemAttr;
				attributes[0].data = (void *)[username UTF8String];
				attributes[0].length = strlen(attributes[0].data);
				
				attributes[1].tag = kSecCommentItemAttr;
				attributes[1].data = (void *)[pkPath UTF8String];
				attributes[1].length = strlen(attributes[1].data);
				
				attributes[2].tag = kSecDescriptionItemAttr;
				attributes[2].data = (void *)desc;
				attributes[2].length = strlen(desc);
				
				NSString *label = [NSString stringWithFormat:@"%@ (%@)", username, [pkPath lastPathComponent]];
				
				attributes[3].tag = kSecLabelItemAttr;
				attributes[3].data = (void *)[label UTF8String];
				attributes[3].length = strlen(attributes[3].data);
				
				list.count = 4;
				list.attr = attributes;
				
				char *passphraseUTF8 = (char *)[passphrase UTF8String];
				status = SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass, &list, strlen(passphraseUTF8), passphraseUTF8, NULL,NULL,&item);
				if (status != 0) {
					NSLog(@"Error creating new item: %d\n", (int)status);
				}
			}
		}
		
		// Cancel will result in a nil passphrase
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

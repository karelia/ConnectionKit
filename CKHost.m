//
//  CKHost.m
//  Connection
//
//  Created by Greg Hulands on 26/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKHost.h"
#import <Carbon/Carbon.h>
#import <Security/Security.h>
#import <Connection/Connection.h>

@implementation CKHost

+ (void)load
{
	[CKHost setVersion:1];
}

- (id)init
{
	if ((self = [super init]))
	{
		
	}
	return self;
}

- (void)dealloc
{
	[myHost release];
	[myPort release];
	[myUsername release];
	[myPassword release];
	[myConnectionType release];
	[myURL release];
	[myDescription release];
	[myInitialPath release];
	[myUserInfo release];
	
	[super dealloc];
}

- (id)initWithCoder:(NSCoder *)coder
{
	if ((self = [super init]))
	{
		int version = [coder decodeIntForKey:@"version"];
		myHost = [[coder decodeObjectForKey:@"host"] copy];
		myPort = [[coder decodeObjectForKey:@"port"] copy];
		myUsername = [[coder decodeObjectForKey:@"username"] copy];
		myConnectionType = [[coder decodeObjectForKey:@"type"] copy];
		myURL = [[coder decodeObjectForKey:@"url"] copy];
		myDescription = [[coder decodeObjectForKey:@"description"] copy];
		myInitialPath = [[coder decodeObjectForKey:@"initialPath"] copy];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeInt:[CKHost version] forKey:@"version"];
	[coder encodeObject:myHost forKey:@"host"];
	[coder encodeObject:myPort forKey:@"port"];
	[coder encodeObject:myUsername forKey:@"username"];
	[coder encodeObject:myConnectionType forKey:@"type"];
	[coder encodeObject:myURL forKey:@"url"];
	[coder encodeObject:myDescription forKey:@"description"];
	[coder encodeObject:myInitialPath forKey:@"initialPath"];
}

- (void)setHost:(NSString *)host
{
	[myHost autorelease];
	myHost = [host copy];
}

- (void)setPort:(NSString *)port
{
	[myPort autorelease];
	myPort = [port copy];
}

- (void)setUsername:(NSString *)username
{
	[myUsername autorelease];
	myUsername = [username copy];
}

- (void)setPassword:(NSString *)password
{
	[myPassword autorelease];
	myPassword = [password copy];
	
	//save to keychain
	@try {
		SecKeychainAttribute attributes[4];
		SecKeychainAttributeList list;
		SecKeychainItemRef item;
		OSStatus status;
		char *desc = "ConnectionKit Password";
		NSString *label = [NSString stringWithFormat:@"%@://%@@%@:%@/%@", [AbstractConnection urlSchemeForConnectionName:myConnectionType port:myPort], myUsername, myHost, myPort, myInitialPath ? myInitialPath : @""];
		
		attributes[0].tag = kSecAccountItemAttr;
		attributes[0].data = (void *)[myUsername UTF8String];
		attributes[0].length = strlen(attributes[0].data);
		
		attributes[1].tag = kSecCommentItemAttr;
		attributes[1].data = (void *)[label UTF8String];
		attributes[1].length = strlen(attributes[1].data);
		
		attributes[2].tag = kSecDescriptionItemAttr;
		attributes[2].data = (void *)desc;
		attributes[2].length = strlen(desc);
		
		attributes[3].tag = kSecLabelItemAttr;
		attributes[3].data = (void *)[label UTF8String];
		attributes[3].length = strlen(attributes[3].data);
		
		list.count = 4;
		list.attr = attributes;
		
		char *passphraseUTF8 = (char *)[myPassword UTF8String];
		status = SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass, &list, strlen(passphraseUTF8), passphraseUTF8, NULL,NULL,&item);
		if (status != 0) 
		{
			NSLog(@"Error creating new item: %d\n", (int)status);
		}
	}
	@catch (id error) {
		
	}
}

- (void)setConnectionType:(NSString *)type
{
	[myConnectionType autorelease];
	myConnectionType = [type copy];
}

- (void)setInitialPath:(NSString *)path
{
	[myInitialPath autorelease];
	myInitialPath = [path copy];
}

- (void)setURL:(NSURL *)url
{
	[myURL autorelease];
	myURL = [url copy];
}

- (void)setAnnotation:(NSString *)description
{
	[myDescription autorelease];
	myDescription = [description copy];
}

- (void)setUserInfo:(id)ui
{
	[myUserInfo autorelease];
	myUserInfo = [ui retain];
}

- (NSString *)host
{
	return myHost;
}

- (NSString *)port
{
	return myPort;
}

- (NSString *)username
{
	return myUsername;
}

- (NSString *)password
{
	if (!myPassword)
	{
		SecKeychainSearchRef search = nil;
		SecKeychainItemRef item = nil;
		SecKeychainAttributeList list;
		SecKeychainAttribute attributes[4];
		OSErr result;
		char *desc = "ConnectionKit Password";
		NSString *label = [NSString stringWithFormat:@"%@://%@@%@:%@/%@", [AbstractConnection urlSchemeForConnectionName:myConnectionType port:myPort], myUsername, myHost, myPort, myInitialPath ? myInitialPath : @""];

		
		attributes[0].tag = kSecAccountItemAttr;
		attributes[0].data = (void *)[myUsername UTF8String];
		attributes[0].length = strlen(attributes[0].data);
		
		attributes[1].tag = kSecCommentItemAttr;
		attributes[1].data = (void *)[label UTF8String];
		attributes[1].length = strlen(attributes[1].data);
		
		attributes[2].tag = kSecDescriptionItemAttr;
		attributes[2].data = (void *)desc;
		attributes[2].length = strlen(desc);
		
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
			myPassword = [[NSString stringWithCString:pass length:length] retain];
			
		}
		if (item) CFRelease(item);
		if (search) CFRelease (search);
	}
	if (!myPassword)
	{
		Str255 serverPString, accountPString;
		
		c2pstrcpy(serverPString, [myHost UTF8String]);
		c2pstrcpy(accountPString, [myUsername UTF8String]);
		
		char passwordBuffer[256];
		UInt32 actualLength;
		OSStatus theStatus;
		
		theStatus = KCFindInternetPassword (
											serverPString,			// StringPtr serverName,
											NULL,					// StringPtr securityDomain,
											accountPString,		// StringPtr accountName,
											kAnyPort,				// UInt16 port,
											kAnyProtocol,			// OSType protocol,
											kAnyAuthType,			// OSType authType,
											255,					// UInt32 maxLength,
											passwordBuffer,		// void * passwordData,
											&actualLength,			// UInt32 * actualLength,
											nil					// KCItemRef * item
											);
		if (noErr == theStatus)
		{
			passwordBuffer[actualLength] = 0;		// make it a legal C string by appending 0
			myPassword = [[NSString stringWithUTF8String:passwordBuffer] retain];
		}
	}
	return myPassword;
}

- (NSString *)connectionType
{
	return myConnectionType;
}

- (NSString *)initialPath
{
	return myInitialPath;
}

- (NSURL *)url
{
	return myURL;
}

- (NSString *)annotation
{
	return myDescription;
}

- (id)userInfo
{
	return myUserInfo;
}

- (id <AbstractConnectionProtocol>)connection
{
	id <AbstractConnectionProtocol> connection = nil;
	NSError *error = nil;
	
	if (myURL)
	{
		connection = [AbstractConnection connectionWithURL:myURL error:&error];
	}
	else if (myConnectionType && ![myConnectionType isEqualToString:@""] && ![myConnectionType isEqualToString:@"Auto Select"])
	{
		connection = [AbstractConnection connectionWithName:myConnectionType
													   host:myHost
													   port:myPort
												   username:myUsername
												   password:[self password]
													  error:&error];
	}
	else
	{
		connection = [AbstractConnection connectionToHost:myHost
													 port:myPort
												 username:myUsername
												 password:[self password]
													error:&error];
	}
	if (!connection && error)
	{
		NSLog(@"%@", error);
	}
	return connection;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@://%@:xxxx@%@:%@/%@", [AbstractConnection urlSchemeForConnectionName:myConnectionType port:myPort], myUsername, myHost, myPort, myInitialPath ? myInitialPath : @""];
}
@end

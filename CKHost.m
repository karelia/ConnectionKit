//
//  CKHost.m
//  Connection
//
//  Created by Greg Hulands on 26/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Connection/CKHost.h>
#import <Carbon/Carbon.h>
#import <Security/Security.h>
#import <Connection/Connection.h>

NSString *CKHostChanged = @"CKHostChanged";
static NSImage *sHostIcon = nil;

@interface CKHost (private)
- (NSString *)name;
@end

@implementation CKHost

+ (void)load
{
	[CKHost setVersion:1];
}

+ (void)initialize
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSBundle *b = [NSBundle bundleForClass:[self class]];
	NSString *p = [b pathForResource:@"bookmark" ofType:@"tif"];
	sHostIcon = [[NSImage alloc] initWithContentsOfFile:p];
	[sHostIcon setScalesWhenResized:YES];
	[sHostIcon setSize:NSMakeSize(16,16)];
	
	[pool release];
}

- (id)init
{
	if ((self = [super init]))
	{
		myConnectionType = @"FTP";
		myHost = @"";
		myUsername = [NSUserName() copy];
		myInitialPath = @"";
		myPort = @"";
		myIcon = [sHostIcon retain];
		myProperties = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[myProperties release];
	[myHost release];
	[myPort release];
	[myUsername release];
	[myPassword release];
	[myConnectionType release];
	[myURL release];
	[myDescription release];
	[myInitialPath release];
	[myUserInfo release];
	[myIcon release];
	
	[super dealloc];
}

- (id)initWithCoder:(NSCoder *)coder
{
	if ((self = [super init]))
	{
		int version = [coder decodeIntForKey:@"version"];
#pragma unused (version)
		myHost = [[coder decodeObjectForKey:@"host"] copy];
		myPort = [[coder decodeObjectForKey:@"port"] copy];
		myUsername = [[coder decodeObjectForKey:@"username"] copy];
		myConnectionType = [[coder decodeObjectForKey:@"type"] copy];
		@try {
			NSString *url = [coder decodeObjectForKey:@"url"];
			if (url && [url length] > 0)
			{
				myURL = [[NSURL URLWithString:url] retain];
			}
		}
		@catch (NSException *ex) {
			
		}
		myDescription = [[coder decodeObjectForKey:@"description"] copy];
		myInitialPath = [[coder decodeObjectForKey:@"initialPath"] copy];
		if (!myInitialPath)
		{
			myInitialPath = @"";
		}
		NSData *data = [coder decodeObjectForKey:@"icon"];
		if (data)
		{
			myIcon = [[NSImage alloc] initWithData:data];
		}
		else
		{
			myIcon = [sHostIcon retain];
		}
		NSDictionary *props = [coder decodeObjectForKey:@"properties"];
		myProperties = [[NSMutableDictionary alloc] init];
		if (props)
		{
			[myProperties addEntriesFromDictionary:props];
		}
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
	[coder encodeObject:[myURL absoluteString] forKey:@"url"];
	[coder encodeObject:myDescription forKey:@"description"];
	[coder encodeObject:myInitialPath forKey:@"initialPath"];
	if (myIcon)
	{
		[coder encodeObject:[myIcon TIFFRepresentation] forKey:@"icon"];
	}
	[coder encodeObject:myProperties forKey:@"properties"];
}

- (void)didChange
{
	[[NSNotificationCenter defaultCenter] postNotificationName:CKHostChanged object:self];
}

- (void)setHost:(NSString *)host
{
	if (host != myHost)
	{
		[self willChangeValueForKey:@"host"];
		[myHost autorelease];
		myHost = [host copy];
		[self didChangeValueForKey:@"host"];
		[self didChange];
	}
}

- (void)setPort:(NSString *)port
{
	if (port != myPort)
	{
		[self willChangeValueForKey:@"port"];
		[myPort autorelease];
		myPort = [port copy];
		[self didChangeValueForKey:@"port"];
		[self didChange];
	}
}

- (void)setUsername:(NSString *)username
{
	if (username != myUsername)
	{
		[self willChangeValueForKey:@"username"];
		[myUsername autorelease];
		myUsername = [username copy];
		[self didChangeValueForKey:@"username"];
		[self didChange];
	}
}

- (void)setPassword:(NSString *)password
{
	if (password != myPassword)
	{
		[self willChangeValueForKey:@"password"];
		[myPassword autorelease];
		myPassword = [password copy];
		[self didChangeValueForKey:@"password"];
		
		//save to keychain
		@try {
			SecKeychainAttribute attributes[4];
			SecKeychainAttributeList list;
			SecKeychainItemRef item = nil;
			OSStatus status;
			char *desc = "ConnectionKit Password";
			NSString *label = [self name];
			
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
			
			// see if it already exists
			SecKeychainSearchRef search = nil;
			status = SecKeychainSearchCreateFromAttributes(NULL, kSecInternetPasswordItemClass, &list, &search);
			
			if (status == noErr)
			{
				if ((status = SecKeychainSearchCopyNext (search, &item)) == noErr) 
				{
					status = SecKeychainItemDelete(item);
				}
				char *passphraseUTF8 = (char *)[myPassword UTF8String];
				status = SecKeychainItemCreateFromContent(kSecInternetPasswordItemClass, &list, strlen(passphraseUTF8), passphraseUTF8, NULL,NULL,&item);
				if (status != 0) 
				{
					NSLog(@"Error creating new item: %s (%s)\n", (int)status, GetMacOSStatusErrorString(status), GetMacOSStatusCommentString(status));
				}
			}
		}
		@catch (id error) {
			
		}
		@finally {
			[self didChange];
		}
	}
}

- (void)setConnectionType:(NSString *)type
{
	if (type != myConnectionType)
	{
		[self willChangeValueForKey:@"type"];
		[myConnectionType autorelease];
		myConnectionType = [type copy];
		[self didChangeValueForKey:@"type"];
		[self didChange];
	}
}

- (void)setInitialPath:(NSString *)path
{
	if (path != myInitialPath)
	{
		[self willChangeValueForKey:@"initialPath"];
		[myInitialPath autorelease];
		myInitialPath = [path copy];
		[self didChangeValueForKey:@"initialPath"];
		[self didChange];
	}
}

- (void)setURL:(NSURL *)url
{
	if (url != myURL)
	{
		[self willChangeValueForKey:@"url"];
		[myURL autorelease];
		myURL = [url copy];
		[self didChangeValueForKey:@"url"];
		[self didChange];
	}
}

- (void)setAnnotation:(NSString *)description
{
	if (description != myDescription)
	{
		[self willChangeValueForKey:@"annotation"];
		[myDescription autorelease];
		myDescription = [description copy];
		[self didChangeValueForKey:@"annotation"];
		[self didChange];
	}
}

- (void)setUserInfo:(id)ui
{
	if (ui != myUserInfo)
	{
		[self willChangeValueForKey:@"userInfo"];
		[myUserInfo autorelease];
		myUserInfo = [ui retain];
		[self didChangeValueForKey:@"userInfo"];
		[self didChange];
	}
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
		SecKeychainAttribute attributes[1];
		OSErr result;
		char *desc = "ConnectionKit Password";
		NSString *label = [self name];
		
		attributes[0].tag = kSecAccountItemAttr;
		attributes[0].data = (void *)[myUsername UTF8String];
		attributes[0].length = strlen(attributes[0].data);
		
		list.count = 1;
		list.attr = &attributes[0];
		
		result = SecKeychainSearchCreateFromAttributes(NULL, kSecInternetPasswordItemClass, &list, &search);
		
		if (result != noErr)
		{
			NSLog (@"status %d from SecKeychainSearchCreateFromAttributes\n", result);
		}
		
		if ((result = SecKeychainSearchCopyNext (search, &item)) == noErr) {
			UInt32 length;
			char *pass;
			SecKeychainAttribute attributes[1];
			SecKeychainAttributeList list;
			OSStatus status;
			
			attributes[0].tag = kSecAccountItemAttr;
			
			list.count = 1;
			list.attr = attributes;
			
			status = SecKeychainItemCopyContent (item, NULL, &list, &length, (void **)&pass);
			
			// length  may be zero, it just means a zero-length password
			myPassword = [[NSString stringWithCString:pass length:length] retain];
			
		}
		if (item) CFRelease(item);
		if (search) CFRelease (search);
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

- (void)setCategory:(CKHostCategory *)cat
{
	if (cat != myCategory)
	{
		myCategory = cat;
		[self didChange];
	}
}

- (CKHostCategory *)category
{
	return myCategory;
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
	return [NSString stringWithFormat:@"%@ %@://%@:xxxx@%@:%@/%@", myConnectionType, [AbstractConnection urlSchemeForConnectionName:myConnectionType port:myPort], myUsername, myHost, myPort, myInitialPath];
}

- (NSString *)name
{
	NSString *type = [AbstractConnection urlSchemeForConnectionName:[self connectionType] port:[self port]];
	NSMutableString *str = [NSMutableString stringWithFormat:@"%@://", type ? type : NSLocalizedString(@"auto", @"connection type")];
	if ([self username] && ![[self username] isEqualToString:@""])
	{
		[str appendFormat:@"%@@", [self username]];
	}
	if ([self host])
	{
		[str appendString:[self host]];
	}
	if ([self port] && ![[self port] isEqualToString:@""])
	{
		[str appendFormat:@":%@", [self port]];
	}
	if ([self initialPath])
	{
		if (![[self initialPath] hasPrefix:@"/"])
		{
			[str appendString:@"/"];
		}
		[str appendFormat:@"%@", [self initialPath]];
	}
	return str;
}

- (NSArray *)children
{
	return nil;
}

- (BOOL)isLeaf
{
	return YES;
}

- (void)setIcon:(NSImage *)icon
{
	if (icon != myIcon)
	{
		[self willChangeValueForKey:@"icon"];
		[myIcon autorelease];
		myIcon = [icon copy];
		[self didChangeValueForKey:@"icon"];
		[self didChange];
	}
}

- (NSImage *)icon
{
	return myIcon;
}

- (void)setProperty:(id)property forKey:(NSString *)key
{
	[self willChangeValueForKey:key];
	[myProperties setObject:property forKey:key];
	[self didChangeValueForKey:key];
}

- (id)propertyForKey:(NSString *)key
{
	return [myProperties objectForKey:key];
}

#pragma mark -
#pragma mark Droplet Support

- (NSDictionary *)plistDictionary
{
	NSMutableDictionary *p = [NSMutableDictionary dictionary];
	
	[p setObject:@"NSApplication" forKey:@"NSPrincipalClass"];
	[p setObject:@"DropletLauncher" forKey:@"NSMainNibFile"];
	[p setObject:@"1" forKey:@"LSUIElement"];
	[p setObject:@"English" forKey:@"CFBundleDevelopmentRegion"];
	[p setObject:@"com.connectionkit.DropletLauncher" forKey:@"CFBundleIdentifier"];
	[p setObject:@"6.0" forKey:@"CFBundleInfoDictionaryVersion"];
	[p setObject:@"APPL" forKey:@"CFBundlePackageType"];
	[p setObject:@"????" forKey:@"CFBundleSignature"];
	[p setObject:@"1.0" forKey:@"CFBundleVersion"];
	[p setObject:@"DropletLauncher" forKey:@"CFBundleExecutable"];
	[p setObject:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"] forKey:@"CKApplication"];
	[p setObject:@"DropletIcon" forKey:@"CFBundleIconFile"];
	NSMutableDictionary *file = [NSMutableDictionary dictionary];
	NSArray *osTypes = [NSArray arrayWithObjects:@"****", @"fold", nil];
	[file setObject:osTypes forKey:@"CFBundleTypeOSTypes"];
	NSArray *exts = [NSArray arrayWithObjects:@"*", nil];
	[file setObject:exts forKey:@"CFBundleTypeExtensions"];
	[file setObject:@"" forKey:@"CFBundleTypeIconFile"];
	[file setObject:@"All Files and Folders" forKey:@"CFBundleTypeName"];
	NSArray *files = [NSArray arrayWithObjects:file, nil];
	[p setObject:files forKey:@"CFBundleDocumentTypes"];
	return p;
}

- (NSString *)createDropletAtPath:(NSString *)path
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSMutableString *appName = [NSMutableString stringWithString:[self annotation] != nil ? [self annotation] : [self host]];
	[appName replaceOccurrencesOfString:@"." withString:@"_" options:NSLiteralSearch range:NSMakeRange(0,[appName length])];
	NSString *app = [[path stringByAppendingPathComponent:appName] stringByAppendingPathExtension:@"app"];
	NSString *contents = [app stringByAppendingPathComponent:@"Contents"];
	NSString *exe = [contents stringByAppendingPathComponent:@"MacOS"];
	NSString *resources = [contents stringByAppendingPathComponent:@"Resources"];
	NSString *plist = [[contents stringByAppendingPathComponent:@"Info"] stringByAppendingPathExtension:@"plist"];
	
	if ([fm fileExistsAtPath:app])
	{
		[fm removeFileAtPath:app handler:nil];
	}
	
	if (![fm createDirectoryAtPath:app attributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:0775] forKey:NSFilePosixPermissions]])
	{
		return nil;
	}
	[fm changeFileAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:NSFileExtensionHidden] atPath:app];
	if (![fm createDirectoryAtPath:contents attributes:nil])
	{
		return nil;
	}
	if (![fm createDirectoryAtPath:exe attributes:nil])
	{
		return nil;
	}
	if (![fm createDirectoryAtPath:resources attributes:nil])
	{
		return nil;
	}
	//do Info.plist
	[[NSPropertyListSerialization dataFromPropertyList:[self plistDictionary]
												format:NSPropertyListXMLFormat_v1_0
									  errorDescription:nil] writeToFile:plist atomically:YES];
	// write host to resources
	[NSKeyedArchiver archiveRootObject:self toFile:[[resources stringByAppendingPathComponent:@"configuration"] stringByAppendingPathExtension:@"ckhost"]];
	
	// copy executable
	[fm copyPath:[[NSBundle bundleForClass:[self class]] pathForResource:@"DropletLauncher" ofType:@""] 
		  toPath:[exe stringByAppendingPathComponent:@"DropletLauncher"] 
		 handler:nil];
	
	// copy icon
	[fm copyPath:[[NSBundle bundleForClass:[self class]] pathForResource:@"DropletIcon" ofType:@"icns"] 
		  toPath:[[resources stringByAppendingPathComponent:@"DropletIcon"] stringByAppendingPathExtension:@"icns"]
		 handler:nil];
	
	// copy the nib
	[fm copyPath:[[NSBundle bundleForClass:[self class]] pathForResource:@"DropletLauncher" ofType:@"nib"] 
		  toPath:[[resources stringByAppendingPathComponent:@"DropletLauncher"] stringByAppendingPathExtension:@"nib"]
		 handler:nil];
	
	// hide the .app extension
	
	OSStatus ret;
	NSURL *url = [NSURL fileURLWithPath:app];
	ret = LSSetExtensionHiddenForURL((CFURLRef)url, true);
	
	return app;
}
@end

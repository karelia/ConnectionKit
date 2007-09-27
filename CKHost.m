/*
 Copyright (c) 2006, Greg Hulands <ghulands@mac.com>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <Connection/CKHost.h>
#import <Carbon/Carbon.h>
#import <Security/Security.h>
#import <Connection/Connection.h>

NSString *CKHostChanged = @"CKHostChanged";
static NSImage *sHostIcon = nil;

@interface CKHost (private)
- (NSString *)name;
- (NSDictionary *)properties;
- (void)setProperties:(NSDictionary *)properties;
@end

@implementation CKHost

+ (void)initialize
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[CKHost setVersion:1];
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
		myUUID = [[NSString uuid] retain];
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
	[myUUID release];
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

- (id)copyWithZone:(NSZone *)zone
{
	CKHost *copy = [[CKHost allocWithZone:zone] init];
	
	[copy setHost:[self host]];
	[copy setPort:[self port]];
	[copy setUsername:[self username]];
	[copy setConnectionType:[self connectionType]];
	[copy setInitialPath:[self initialPath]];
	[copy setAnnotation:[self annotation]];
	[copy setIcon:[self icon]];
	[copy setProperties:[self properties]];
	
	return copy;
}

- (BOOL)isEqual:(id)anObject
{
	if ([anObject isKindOfClass:[CKHost class]])
	{
		CKHost *other = (CKHost *)anObject;
		return ([[self host] isEqualToString:[other host]] &&
				[[self port] isEqualToString:[other port]] &&
				[[self username] isEqualToString:[other username]] &&
				[[self connectionType] isEqualToString:[other connectionType]] &&
				[[self initialPath] isEqualToString:[other initialPath]]);
	}
	return NO;
}

- (id)initWithCoder:(NSCoder *)coder
{
	if ((self = [super init]))
	{
		int version = [coder decodeIntForKey:@"version"];
#pragma unused (version)
		myUUID = [[coder decodeObjectForKey:@"uuid"] copy];
		if (!myUUID)
		{
			myUUID = [[NSString uuid] retain];
		}
		myHost = [[coder decodeObjectForKey:@"host"] copy];
		myPort = [[coder decodeObjectForKey:@"port"] copy];
		myUsername = [[coder decodeObjectForKey:@"username"] copy];
		myConnectionType = [[coder decodeObjectForKey:@"type"] copy];
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
	[coder encodeObject:myUUID forKey:@"uuid"];
	[coder encodeObject:myHost forKey:@"host"];
	[coder encodeObject:myPort forKey:@"port"];
	[coder encodeObject:myUsername forKey:@"username"];
	[coder encodeObject:myConnectionType forKey:@"type"];
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

- (NSString *)uuid
{
	return myUUID;
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
			if ([myHost isEqualToString:@""] ||
				[myUsername isEqualToString:@""])
			{
				return;
			}
			
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
			status = SecKeychainFindInternetPassword (NULL,
													  strlen([myHost UTF8String]),
													  [myHost UTF8String],
													  0,
													  NULL,
													  strlen([myUsername UTF8String]),
													  [myUsername UTF8String],
													  strlen([myInitialPath UTF8String]),
													  [myInitialPath UTF8String],
													  [myPort intValue],
													  kSecProtocolTypeFTP,
													  kSecAuthenticationTypeDefault,
													  NULL,
													  NULL,
													  &item);
			
			if (status == noErr)
			{
				status = SecKeychainItemDelete(item);
				CFRelease(item); item = NULL;
			}
			else
			{
				SecKeychainSearchRef search = nil;
				status = SecKeychainSearchCreateFromAttributes(NULL, kSecInternetPasswordItemClass, &list, &search);
				
				if (status == noErr)
				{
					if ((status = SecKeychainSearchCopyNext (search, &item)) != errSecItemNotFound) 
					{
						status = SecKeychainItemDelete(item);
						if (status != noErr)
						{
							NSLog(@"Error deleting keychain item: %s (%s)\n", (int)status, GetMacOSStatusErrorString(status), GetMacOSStatusCommentString(status));
						}
					}
					if (item) CFRelease(item); item = NULL;
				}
				if (search) CFRelease(search);
			}
			char *passphraseUTF8 = (char *)[myPassword UTF8String];
			status = SecKeychainItemCreateFromContent(kSecInternetPasswordItemClass, &list, strlen(passphraseUTF8), passphraseUTF8, NULL,NULL,&item);
			if (status != 0) 
			{
				NSLog(@"Error creating new item: %s (%s)\n", (int)status, GetMacOSStatusErrorString(status), GetMacOSStatusCommentString(status));
			}
			if (item) CFRelease(item);
			
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
	[self setHost:[url host]];
	[self setUsername:[url user]];
	[self setPassword:[url password]];
	[self setInitialPath:[url path]];
	[self setPort:[NSString stringWithFormat:@"%@",[url port]]];
	[self setConnectionType:[url scheme]];
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
	if (myPassword)
	{
		return myPassword;
	}
	//Need to get the password from keychain
	if ([myHost isEqualToString:@""] || [myUsername isEqualToString:@""])
	{
		//We don't have anything to base our keychain search from, we have no chance.
		return nil;
	}
	OSStatus status;
	UInt32 length = 0;
	char *pass = NULL;
	
	// Try searching for an internet password first
	status = SecKeychainFindInternetPassword (NULL, strlen([myHost UTF8String]), [myHost UTF8String], 0, NULL, strlen([myUsername UTF8String]), [myUsername UTF8String], strlen([myInitialPath UTF8String]), [myInitialPath UTF8String], [myPort intValue], kSecProtocolTypeFTP, kSecAuthenticationTypeDefault, &length, (void **)&pass, NULL);	
	if (status != errSecItemNotFound)
	{
		//Found an internet password
		myPassword = [[NSString stringWithCString:pass length:length] retain];
		if (length)
		{
			SecKeychainItemFreeContent(NULL, pass);
		}
		if (myPassword && ![myPassword isEqualToString:@""])
		{
			return myPassword;
		}
	}
	
	//Didn't find an internet password, let's look elsewhere
	SecKeychainSearchRef search = nil;
	SecKeychainItemRef item = nil;
	SecKeychainAttributeList list;
	SecKeychainAttribute attributes[4];
	OSErr result;
	
	char *description = "ConnectionKit Password";
	NSString *label = [self name];
	
	
	attributes[0].tag = kSecAccountItemAttr;
	attributes[0].data = (void *)[myUsername UTF8String];
	attributes[0].length = strlen(attributes[0].data);
	
	attributes[1].tag = kSecCommentItemAttr;
	attributes[1].data = (void *)[label UTF8String];
	attributes[1].length = strlen(attributes[1].data);
	
	attributes[2].tag = kSecDescriptionItemAttr;
	attributes[2].data = (void *)description;
	attributes[2].length = strlen(description);
	
	attributes[3].tag = kSecLabelItemAttr;
	attributes[3].data = (void *)[label UTF8String];
	attributes[3].length = strlen(attributes[3].data);
	
	//We start out with very stringent attribute specifications. 
	//As we continue to not find a password, we scale back the requirements from the attributes.
	unsigned int attributeCountRequirement = 4;
	while (attributeCountRequirement > 0)
	{
		list.count = attributeCountRequirement;
		list.attr = &attributes[0];
		
		result = SecKeychainSearchCreateFromAttributes(NULL, kSecInternetPasswordItemClass, &list, &search);
		if (result != noErr)
		{
			//Ran into some error, log it
			NSLog(@"Status %d from SecKeychainSearchCreateFromAttributes", result);
		}
		result = SecKeychainSearchCopyNext(search, &item);
		if (result == noErr)
		{
			//We found something
			SecKeychainAttribute attributes[1];
			SecKeychainAttributeList list;
			
			attributes[0].tag = kSecAccountItemAttr;
			
			list.count = 1;
			list.attr = attributes;
			
			status = SecKeychainItemCopyContent(item, NULL, &list, &length, (void **)&pass);
			if (status != userCanceledErr)
			{
				myPassword = [[NSString stringWithCString:pass length:length] retain];
				SecKeychainItemFreeContent(&list, pass);
			}
			break;
		}
		attributes[attributeCountRequirement-1].tag = nil;
		attributes[attributeCountRequirement-1].data = nil;
		attributes[attributeCountRequirement-1].length = nil;		
		attributeCountRequirement--;
	}
	//Clean up
	if (item) CFRelease(item);
	if (search) CFRelease(search);
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

- (BOOL)isAbsoluteInitialPath
{
	return [[self initialPath] hasPrefix:@"/"];
}

- (NSString *)baseURLString
{
	NSString *scheme = [AbstractConnection urlSchemeForConnectionName:[self connectionType] port:[self port]];
	NSMutableString *url = [NSMutableString stringWithFormat:@"%@://", scheme];
	if ([self username])
	{
		[url appendString:[self username]];
		
		if ([self password])
		{
			[url appendFormat:@":%@", [self password]];
		}
		
		[url appendString:@"@"];
	}
	[url appendString:[self host]];
	
	NSString *port = myPort;
	if (!port || [port isEqualToString:@""])
	{
		port = [AbstractConnection registeredPortForConnectionType:[self connectionType]];
	}
	
	if (port)
	{
		[url appendFormat:@":%@", port]; // use the con port incase it used the default port.
	}
	
	
	return url;
}

- (NSString *)urlString
{
	NSMutableString *url = [NSMutableString stringWithString:[self baseURLString]];
	
	if ([self initialPath])
	{
		if (![[self initialPath] hasPrefix:@"/"])
		{
			[url appendString:@"/"];
		}
		else
		{
			[url appendString:@"/%2F"];
		}
		[url appendString:[self initialPath]];
	}
	else
	{
		[url appendString:@"/"];
	}
	
	if (![url hasSuffix:@"/"])
	{
		[url appendString:@"/"];
	}
	
	return url;
}

- (NSURL *)baseURL
{
	return [NSURL URLWithString:[self baseURLString]];
}

- (NSURL *)URL
{
	return [NSURL URLWithString:[self urlString]];
}

- (NSURL *)url
{
	return [self URL];
}

- (NSString *)annotation
{
	return myDescription;
}

- (id)userInfo
{
	return myUserInfo;
}

- (BOOL)isEditable
{
	return YES;
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
	
	if (!connection && myConnectionType && ![myConnectionType isEqualToString:@""] && ![myConnectionType isEqualToString:@"Auto Select"])
	{
		connection = [AbstractConnection connectionWithName:myConnectionType
													   host:myHost
													   port:myPort
												   username:myUsername
												   password:[self password]
													  error:&error];
	}
	
	if (!connection)
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

- (BOOL)canConnect
{
	return [self connection] != nil;
}

- (NSString *)description
{
	return [self urlString];
}

- (NSString *)name
{
	NSString *type = [AbstractConnection urlSchemeForConnectionName:[self connectionType] port:[self port]];
	NSMutableString *str = [NSMutableString stringWithFormat:@"%@://", type ? type : LocalizedStringInThisBundle(@"auto", @"connection type")];
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
		myIcon = [icon retain];
		[self didChangeValueForKey:@"icon"];
		[self didChange];
	}
}

- (NSImage *)icon
{
	return myIcon;
}

- (NSImage *)iconWithSize:(NSSize)size
{
	NSImage *copy = [[self icon] copy];
	[copy setScalesWhenResized:YES];
	[copy setSize:size];
	return [copy autorelease];
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

- (NSDictionary *)properties
{
	return myProperties;
}

- (void)setProperties:(NSDictionary *)properties
{
	[myProperties removeAllObjects];
	[myProperties addEntriesFromDictionary:properties];
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

- (id)valueForUndefinedKey:(NSString *)key
{
	SEL sel = NSSelectorFromString(key);
	if ([self respondsToSelector:sel])
	{
		return [self performSelector:sel];
	}
	return nil;
}

@end

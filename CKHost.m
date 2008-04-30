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
#import <Connection/Connection.h>
#import "EMKeychainProxy.h"

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
		myUsername = @"";
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

- (id)initWithDictionary:(NSDictionary *)dictionary
{
	if ((self = [super init]))
	{
		int version = [[dictionary objectForKey:@"version"] intValue];
#pragma unused (version)
		myUUID = [[dictionary objectForKey:@"uuid"] copy];
		if (!myUUID)
		{
			myUUID = [[NSString uuid] retain];
		}
		myHost = [[dictionary objectForKey:@"host"] copy];
		myPort = [[dictionary objectForKey:@"port"] copy];
		myUsername = [[dictionary objectForKey:@"username"] copy];
		myConnectionType = [[dictionary objectForKey:@"type"] copy];
		myDescription = [[dictionary objectForKey:@"description"] copy];
		myInitialPath = [[dictionary objectForKey:@"initialPath"] copy];
		if (!myInitialPath)
		{
			myInitialPath = @"";
		}
		NSData *data = [dictionary objectForKey:@"icon"];
		if (data)
		{
			myIcon = [[NSImage alloc] initWithData:data];
		}
		else
		{
			myIcon = [sHostIcon retain];
		}
		NSDictionary *props = [dictionary objectForKey:@"properties"];
		myProperties = [[NSMutableDictionary alloc] init];
		if (props)
		{
			[myProperties addEntriesFromDictionary:props];
		}
	}
	return self;
}

- (NSDictionary *)plistRepresentation
{
	NSMutableDictionary *plist = [NSMutableDictionary dictionary];
	
	[plist setObject:@"host" forKey:@"class"];
	[plist setObject:[NSNumber numberWithInt:[CKHost version]] forKey:@"version"];
	[plist setObject:myUUID forKey:@"uuid"];
	if (myHost)
	{
		[plist setObject:myHost forKey:@"host"];
	}
	if (myPort)
	{
		[plist setObject:myPort forKey:@"port"];
	}
	if (myUsername)
	{
		[plist setObject:myUsername forKey:@"username"];
	}
	if (myConnectionType)
	{
		[plist setObject:myConnectionType forKey:@"type"];
	}
	if (myDescription)
	{
		[plist setObject:myDescription forKey:@"description"];
	}
	if (myInitialPath)
	{
		[plist setObject:myInitialPath forKey:@"initialPath"];
	}
	if (myIcon)
	{
		[plist setObject:[myIcon TIFFRepresentation] forKey:@"icon"];
	}
	if (myProperties)
	{
		[plist setObject:myProperties forKey:@"properties"];
	}
	
	return plist;
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
	
	EMInternetKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] internetKeychainItemForServer:myHost withUsername:myUsername path:nil port:[myPort intValue] protocol:kSecProtocolTypeFTP];
	if (!keychainItem && myPassword && [myPassword length] > 0 && myUsername && [myUsername length] > 0)
	{
		//We don't have any keychain item created for us, but we have all the info we need to make one. Let's do it.
		[[EMKeychainProxy sharedProxy] addInternetKeychainItemForServer:myHost withUsername:myUsername password:myPassword path:nil port:[myPort intValue] protocol:kSecProtocolTypeFTP];
	}	
}

- (NSString *)uuid
{
	return myUUID;
}

- (void)setHost:(NSString *)host
{
	if ([host isEqualToString:myHost])
	{
		return;
	}
	NSString *oldServerString = (myHost != nil) ? [NSString stringWithString:myHost] : nil;

	[self willChangeValueForKey:@"host"];
	[myHost autorelease];
	myHost = [host copy];
	[self didChangeValueForKey:@"host"];
	[self didChange];
	
	if (!oldServerString || [oldServerString length] == 0)
	{
		return;
	}
	
	EMInternetKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] internetKeychainItemForServer:oldServerString withUsername:myUsername path:nil port:[myPort intValue] protocol:kSecProtocolTypeFTP];
	[keychainItem setServer:host];		
}

- (void)setPort:(NSString *)port
{
	if (port == myPort)
	{
		return;
	}
	
	NSString *oldPortString = (myPort) ? [NSString stringWithString:myPort] : nil;
	
	[self willChangeValueForKey:@"port"];
	[myPort autorelease];
	myPort = [port copy];
	[self didChangeValueForKey:@"port"];
	[self didChange];
	
	if (!oldPortString || [oldPortString length] == 0)
	{
		return;
	}
	
	EMInternetKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] internetKeychainItemForServer:myHost withUsername:myUsername path:nil port:[oldPortString intValue] protocol:kSecProtocolTypeFTP];
	[keychainItem setPort:[port intValue]];
}

- (void)setUsername:(NSString *)username
{
	if (!username)
	{
		username = @"";
	}
	
	if (username == myUsername)
	{
		return;
	}
	
	NSString *oldUsernameString = (myUsername) ? [NSString stringWithString:myUsername] : nil;
	
	[self willChangeValueForKey:@"username"];
	[myUsername autorelease];
	myUsername = [username copy];
	[self didChangeValueForKey:@"username"];
	[self didChange];
	
	if (!oldUsernameString || [oldUsernameString length] == 0)
	{
		return;
	}
	
	EMInternetKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] internetKeychainItemForServer:myHost withUsername:oldUsernameString path:nil port:[myPort intValue] protocol:kSecProtocolTypeFTP];
	[keychainItem setUsername:username];
}

- (void)setPassword:(NSString *)password
{
	if (!password)
	{
		password = @"";
	}
	
	if ([myPassword isEqualToString:password])
	{
		return;
	}

	[self willChangeValueForKey:@"password"];
	[myPassword autorelease];
	myPassword = [password copy];
	[self didChangeValueForKey:@"password"];
	[self didChange];
	
	//Save to keychain
	if (!myUsername || [myUsername length] == 0 || !myHost || [myHost length] == 0)
	{
		return;
	}
	
	EMInternetKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] internetKeychainItemForServer:myHost withUsername:myUsername path:nil port:[myPort intValue] protocol:kSecProtocolTypeFTP];
	if (keychainItem)
	{
		[keychainItem setPassword:password];
	}
	else
	{
		[[EMKeychainProxy sharedProxy] addInternetKeychainItemForServer:myHost withUsername:myUsername password:myPassword path:nil port:[myPort intValue] protocol:kSecProtocolTypeFTP];
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
	if (!path)
	{
		path = @"";
	}
	
	if (path == myInitialPath)
	{
		return;
	}
	
	[self willChangeValueForKey:@"initialPath"];
	[myInitialPath autorelease];
	myInitialPath = [path copy];
	[self didChangeValueForKey:@"initialPath"];
	[self didChange];
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
	
	if (!myHost || !myUsername || [myHost isEqualToString:@""] || [myUsername isEqualToString:@""])
	{
		//We don't have anything to go on, so let's die here.
		return nil;
	}
	
	EMInternetKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] internetKeychainItemForServer:myHost withUsername:myUsername path:nil port:[myPort intValue] protocol:kSecProtocolTypeFTP];
	return [keychainItem password];
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
        NSString *escapedUsername = [(NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)[self username], NULL, CFSTR("?=&+/@!"), kCFStringEncodingUTF8) autorelease];
		[url appendString:escapedUsername];
		
		if ([self password])
		{
            NSString *escapedPassword = [(NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)[self password], NULL, CFSTR("?=&+/@!"), kCFStringEncodingUTF8) autorelease];
			[url appendFormat:@":%@", escapedPassword];
		}
		
		[url appendString:@"@"];
	}
	if ([self host])
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
        NSString *escapedPath = [(NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)[self initialPath], NULL, CFSTR("?=&+@!"), kCFStringEncodingUTF8) autorelease];
		[url appendString:escapedPath];
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
	NSMutableString *str = [NSMutableString stringWithFormat:@"%@://", type ? type : LocalizedStringInConnectionKitBundle(@"auto", @"connection type")];
	if ([self username] && ![[self username] isEqualToString:@""])
	{
		[str appendFormat:@"%@@", [self username]];
	}
	if ([self host])
	{
		[str appendString:[self host]];
	}
	//We check if port is a string because there have been cases where client apps have (improperly) stored port as an NSNumber. In this case, it would cause a crasher, and not allow the registry to fully launch (name is called when reading it, effectively). Once we get through this launch, the registry resets the corrupt entry.
	if ([self port] && [[self port] isKindOfClass:[NSString class]] && ![[self port] isEqualToString:@""]) 
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

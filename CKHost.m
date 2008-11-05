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

- (NSString *)UUID { return _UUID; }

- (NSString *)uuid { return _UUID; }
- (NSString *)host { return _host; }
- (NSString *)port { return _port; }
- (NSString *)username { return _username; }
- (NSString *)connectionType { return _connectionType; }
- (NSString *)initialPath { return _initialPath; }
- (id) userInfo { return _userInfo; }
- (CKHostCategory *)category { return _category; }

#pragma mark -
#pragma mark Getting Started / Tearing Down
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
		_UUID = [[NSString uuid] retain];
		_connectionType = @"FTP";
		_host = @"";
		_username = @"";
		_initialPath = @"";
		_port = @"";
		_icon = [sHostIcon retain];
		_properties = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_UUID release];
	[_properties release];
	[_host release];
	[_port release];
	[_username release];
	[_password release];
	[_connectionType release];
	[_URL release];
	[_description release];
	[_initialPath release];
	[_userInfo release];
	[_icon release];
	
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
		(void) [[dictionary objectForKey:@"version"] intValue];
#pragma unused (version)
		_UUID = [[dictionary objectForKey:@"uuid"] copy];
		if (!_UUID)
		{
			_UUID = [[NSString uuid] retain];
		}
		_host = [[dictionary objectForKey:@"host"] copy];
		_port = [[dictionary objectForKey:@"port"] copy];
		_username = [[dictionary objectForKey:@"username"] copy];
		_connectionType = [[dictionary objectForKey:@"type"] copy];
		_description = [[dictionary objectForKey:@"description"] copy];
		_initialPath = [[dictionary objectForKey:@"initialPath"] copy];
		if (!_initialPath)
		{
			_initialPath = @"";
		}
		NSData *data = [dictionary objectForKey:@"icon"];
		if (data)
			_icon = [[NSImage alloc] initWithData:data];
		else
			_icon = [sHostIcon retain];
		NSDictionary *props = [dictionary objectForKey:@"properties"];
		_properties = [[NSMutableDictionary alloc] init];
		if (props)
			[_properties addEntriesFromDictionary:props];
	}
	return self;
}

- (NSDictionary *)plistRepresentation
{
	NSMutableDictionary *plist = [NSMutableDictionary dictionary];
	
	[plist setObject:@"host" forKey:@"class"];
	[plist setObject:[NSNumber numberWithInt:[CKHost version]] forKey:@"version"];
	[plist setObject:_UUID forKey:@"uuid"];
	if (_host)
	{
		[plist setObject:_host forKey:@"host"];
	}
	if (_port)
	{
		[plist setObject:_port forKey:@"port"];
	}
	if (_username)
	{
		[plist setObject:_username forKey:@"username"];
	}
	if (_connectionType)
	{
		[plist setObject:_connectionType forKey:@"type"];
	}
	if (_description)
	{
		[plist setObject:_description forKey:@"description"];
	}
	if (_initialPath)
	{
		[plist setObject:_initialPath forKey:@"initialPath"];
	}
	if (_icon)
	{
		[plist setObject:[_icon TIFFRepresentation] forKey:@"icon"];
	}
	if (_properties)
	{
		[plist setObject:_properties forKey:@"properties"];
	}
	
	return plist;
}

- (id)initWithCoder:(NSCoder *)coder
{
	if ((self = [super init]))
	{
		(void) [coder decodeIntForKey:@"version"];
#pragma unused (version)
		_UUID = [[coder decodeObjectForKey:@"uuid"] copy];
		if (!_UUID)
		{
			_UUID = [[NSString uuid] retain];
		}
		_host = [[coder decodeObjectForKey:@"host"] copy];
		_port = [[coder decodeObjectForKey:@"port"] copy];
		_username = [[coder decodeObjectForKey:@"username"] copy];
		_connectionType = [[coder decodeObjectForKey:@"type"] copy];
		_description = [[coder decodeObjectForKey:@"description"] copy];
		_initialPath = [[coder decodeObjectForKey:@"initialPath"] copy];
		if (!_initialPath)
			_initialPath = @"";
		NSData *data = [coder decodeObjectForKey:@"icon"];
		if (data)
			_icon = [[NSImage alloc] initWithData:data];
		else
			_icon = [sHostIcon retain];
		NSDictionary *props = [coder decodeObjectForKey:@"properties"];
		_properties = [[NSMutableDictionary alloc] init];
		if (props)
			[_properties addEntriesFromDictionary:props];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeInt:[CKHost version] forKey:@"version"];
	[coder encodeObject:_UUID forKey:@"uuid"];
	[coder encodeObject:_host forKey:@"host"];
	[coder encodeObject:_port forKey:@"port"];
	[coder encodeObject:_username forKey:@"username"];
	[coder encodeObject:_connectionType forKey:@"type"];
	[coder encodeObject:_description forKey:@"description"];
	[coder encodeObject:_initialPath forKey:@"initialPath"];
	if (_icon)
		[coder encodeObject:[_icon TIFFRepresentation] forKey:@"icon"];
	[coder encodeObject:_properties forKey:@"properties"];
}

#pragma mark -
#pragma mark Setters
- (void)setHost:(NSString *)host
{
	if ([host isEqualToString:_host])
		return;
	NSString *oldServerString = (_host != nil) ? [NSString stringWithString:_host] : nil;

	[self willChangeValueForKey:@"host"];
	[_host autorelease];
	_host = [host copy];
	[self didChangeValueForKey:@"host"];
	[self didChange];
	
	if (!oldServerString || [oldServerString length] == 0)
		return;
	
	EMInternetKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] internetKeychainItemForServer:oldServerString withUsername:_username path:nil port:[_port intValue] protocol:kSecProtocolTypeFTP];
	[keychainItem setServer:host];		
}

- (void)setPort:(NSString *)port
{
	if (port == _port)
		return;
	
	NSString *oldPortString = (_port) ? [NSString stringWithString:_port] : nil;
	
	[self willChangeValueForKey:@"port"];
	[_port autorelease];
	_port = [port copy];
	[self didChangeValueForKey:@"port"];
	[self didChange];
	
	if (!oldPortString || [oldPortString length] == 0)
		return;
	
	EMInternetKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] internetKeychainItemForServer:_host withUsername:_username path:nil port:[oldPortString intValue] protocol:kSecProtocolTypeFTP];
	[keychainItem setPort:[port intValue]];
}

- (void)setUsername:(NSString *)username
{
	if (!username)
		username = @"";
	
	if (username == _username)
		return;
	
	NSString *oldUsernameString = (_username) ? [NSString stringWithString:_username] : nil;
	
	[self willChangeValueForKey:@"username"];
	[_username autorelease];
	_username = [username copy];
	[self didChangeValueForKey:@"username"];
	[self didChange];
	
	if (!oldUsernameString || [oldUsernameString length] == 0)
		return;
	
	if ([[[ConnectionRegistry sharedRegistry] allHosts] containsObject:self])
	{
		EMInternetKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] internetKeychainItemForServer:_host withUsername:oldUsernameString path:nil port:[_port intValue] protocol:kSecProtocolTypeFTP];
		[keychainItem setUsername:username];
	}
}

- (void)setPassword:(NSString *)password
{
	if (!password)
		password = @"";
	
	if ([_password isEqualToString:password])
		return;

	[self willChangeValueForKey:@"password"];
	[_password autorelease];
	_password = [password copy];
	[self didChangeValueForKey:@"password"];
	[self didChange];
	
	//Save to keychain
	if (!_username || [_username length] == 0 || !_host || [_host length] == 0)
		return;
	
	if ([[[ConnectionRegistry sharedRegistry] allHosts] containsObject:self])
	{
		EMInternetKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] internetKeychainItemForServer:_host
																							   withUsername:_username
																									   path:nil
																									   port:[_port intValue]
																								   protocol:kSecProtocolTypeFTP];
		if (keychainItem)
			[keychainItem setPassword:password];
		else
		{
			[[EMKeychainProxy sharedProxy] addInternetKeychainItemForServer:_host 
															   withUsername:_username
																   password:_password
																	   path:nil
																	   port:[_port intValue]
																   protocol:kSecProtocolTypeFTP];
		}
	}
}

- (void)setConnectionType:(NSString *)type
{
	if (type != _connectionType)
	{
		[self willChangeValueForKey:@"type"];
		[_connectionType autorelease];
		_connectionType = [type copy];
		[self didChangeValueForKey:@"type"];
		[self didChange];
	}
}

- (void)setInitialPath:(NSString *)path
{
	if (!path)
		path = @"";
	
	if (path == _initialPath)
		return;
	
	[self willChangeValueForKey:@"initialPath"];
	[_initialPath autorelease];
	_initialPath = [path copy];
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
	
	[self willChangeValueForKey:@"URL"];
	[_URL autorelease];
	_URL = [url copy];
	[self didChangeValueForKey:@"URL"];
}

- (void)setAnnotation:(NSString *)description
{
	if (description != _description)
	{
		[self willChangeValueForKey:@"annotation"];
		[_description autorelease];
		_description = [description copy];
		[self didChangeValueForKey:@"annotation"];
		[self didChange];
	}
}

- (void)setUserInfo:(id)ui
{
	if (ui != _userInfo)
	{
		[self willChangeValueForKey:@"userInfo"];
		[_userInfo autorelease];
		_userInfo = [ui retain];
		[self didChangeValueForKey:@"userInfo"];
		[self didChange];
	}
}

- (void)setCategory:(CKHostCategory *)cat
{
	if (cat != _category)
	{
		_category = cat;
		[self didChange];
	}
}

- (void)setIcon:(NSImage *)icon
{
	if (icon != _icon)
	{
		[self willChangeValueForKey:@"icon"];
		[_icon autorelease];
		_icon = [icon retain];
		[self didChangeValueForKey:@"icon"];
		[self didChange];
	}
}

- (void)setProperty:(id)property forKey:(NSString *)key
{
	[self willChangeValueForKey:key];
	[_properties setObject:property forKey:key];
	[self didChangeValueForKey:key];
}

- (void)setProperties:(NSDictionary *)properties
{
	[_properties removeAllObjects];
	[_properties addEntriesFromDictionary:properties];
}

#pragma mark -
#pragma mark Accessors
- (NSString *)password
{
	if (_password)
		return _password;
	
	if (!_host || !_username || [_host isEqualToString:@""] || [_username isEqualToString:@""])
	{
		//We don't have anything to go on, so let's die here.
		return nil;
	}
	
	if ([[[ConnectionRegistry sharedRegistry] allHosts] containsObject:self])
	{
		EMInternetKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] internetKeychainItemForServer:_host
																							   withUsername:_username
																									   path:nil
																									   port:[_port intValue]
																								   protocol:kSecProtocolTypeFTP];
		return [keychainItem password];
	}
	return nil;
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
	
	NSString *port = _port;
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
	return _description;
}

- (BOOL)isEditable
{
	return YES;
}

- (id <AbstractConnectionProtocol>)connection
{
	id <AbstractConnectionProtocol> connection = nil;
	NSError *error = nil;
	
	if (_URL)
	{
		connection = [AbstractConnection connectionWithURL:_URL error:&error];
	}
	
	if (!connection && _connectionType && ![_connectionType isEqualToString:@""] && ![_connectionType isEqualToString:@"Auto Select"])
	{
		connection = [AbstractConnection connectionWithName:_connectionType
													   host:_host
													   port:_port
												   username:_username
												   password:[self password]
													  error:&error];
	}
	
	if (!connection)
	{
		connection = [AbstractConnection connectionToHost:_host
													 port:_port
												 username:_username
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

- (NSImage *)icon
{
	return _icon;
}

- (NSImage *)iconWithSize:(NSSize)size
{
	NSImage *copy = [[self icon] copy];
	[copy setScalesWhenResized:YES];
	[copy setSize:size];
	return [copy autorelease];
}

- (id)propertyForKey:(NSString *)key
{
	return [_properties objectForKey:key];
}

- (NSDictionary *)properties
{
	return _properties;
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
	[appName replaceOccurrencesOfString:@"/" withString:@":" options:NSLiteralSearch range:NSMakeRange(0,[appName length])];
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
	
	NSURL *url = [NSURL fileURLWithPath:app];
	(void)LSSetExtensionHiddenForURL((CFURLRef)url, true);
	
	return app;
}

#pragma mark -
#pragma mark Misc.
- (void)didChange
{
	[[NSNotificationCenter defaultCenter] postNotificationName:CKHostChanged object:self];
	if ([[[ConnectionRegistry sharedRegistry] allHosts] containsObject:self])
	{
		EMInternetKeychainItem *keychainItem = [[EMKeychainProxy sharedProxy] internetKeychainItemForServer:_host
																							   withUsername:_username
																									   path:nil
																									   port:[_port intValue]
																								   protocol:kSecProtocolTypeFTP];
		
		if (!keychainItem && _password && [_password length] > 0 && _username && [_username length] > 0)
		{
			//We don't have any keychain item created for us, but we have all the info we need to make one. Let's do it.
			[[EMKeychainProxy sharedProxy] addInternetKeychainItemForServer:_host withUsername:_username password:_password path:nil port:[_port intValue] protocol:kSecProtocolTypeFTP];
		}	
	}
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

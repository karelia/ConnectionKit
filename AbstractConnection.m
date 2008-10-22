/*
 Copyright (c) 2004-2006 Karelia Software. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Karelia Software nor the names of its contributors may be used to 
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

#import "AbstractConnection.h"
#import "CKTransferRecord.h"
#import "UKKQueue.h"
#import "RunLoopForwarder.h"
#import "ConnectionThreadManager.h"
#import "NSString+Connection.h"
#import "KTLog.h"
#import "RegexKitLite.h"

@interface AbstractConnection (Deprecated)
+ (id <AbstractConnectionProtocol>)connectionWithName:(NSString *)name
												 host:(NSString *)host
												 port:(NSString *)port
											 username:(NSString *)username
											 password:(NSString *)password;
+ (id <AbstractConnectionProtocol>)connectionToHost:(NSString *)host
											   port:(NSString *)port
										   username:(NSString *)username
										   password:(NSString *)password;
+ (id <AbstractConnectionProtocol>)connectionWithURL:(NSURL *)url;
@end



NSString *ACClassKey = @"Class";
NSString *ACTypesKey = @"Types";
NSString *ACTypeKey = @"ACTypeKey";
NSString *ACTypeValueKey = @"ACTypeValueKey";
NSString *ACPortTypeKey = @"ACPortTypeKey";
NSString *ACURLTypeKey = @"ACURLTypeKey";

NSString *ConnectionErrorDomain = @"ConnectionErrorDomain";

// Command Dictionary Keys
NSString *ConnectionAwaitStateKey = @"ConnectionAwaitStateKey";
NSString *ConnectionSentStateKey = @"ConnectionSentStateKey";
NSString *ConnectionCommandKey = @"ConnectionCommandKey";

// Attributes for which there isn't a corresponding NSFileManager key
NSString *cxFilenameKey = @"cxFilenameKey";
NSString *cxSymbolicLinkTargetKey = @"cxSymbolicLinkTargetKey";

// User Info Error Keys
NSString *ConnectionHostKey = @"ConnectionHostKey";
NSString *ConnectionDirectoryExistsKey = @"ConnectionDirectoryExistsKey";
NSString *ConnectionDirectoryExistsFilenameKey = @"ConnectionDirectoryExistsFilenameKey";

// Logging Domains 
NSString *TransportDomain = @"Transport";
NSString *StateMachineDomain = @"State Machine";
NSString *ParsingDomain = @"Parser";
NSString *ProtocolDomain = @"Protocol";
NSString *ConnectionDomain = @"Connection";
NSString *ThreadingDomain = @"Threading";
NSString *StreamDomain = @"Stream";
NSString *InputStreamDomain = @"Input Stream";
NSString *OutputStreamDomain = @"Output Stream";
NSString *SSLDomain = @"SSL";
NSString *EditingDomain = @"Editing";

static NSMutableArray *_connectionTypes = nil;

NSDictionary *sSentAttributes = nil;
NSDictionary *sReceivedAttributes = nil;
NSDictionary *sDataAttributes = nil;

@implementation AbstractConnection

#pragma mark -
#pragma mark Registry

+ (void)registerConnectionClass:(Class)class forTypes:(NSArray *)types
{
	NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:NSStringFromClass(class), ACClassKey, types, ACTypesKey, nil];
	[[self connectionTypes] addObject:d];
}

+ (NSDictionary *)sentAttributes
{
    if (!sSentAttributes)
        sSentAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:[NSFont fontWithName:@"Courier" size:11], NSFontAttributeName, [NSColor redColor], NSForegroundColorAttributeName, nil];
    return sSentAttributes;
}

+ (NSDictionary *)receivedAttributes
{
    if (!sReceivedAttributes)
        sReceivedAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:[NSFont fontWithName:@"Courier-Bold" size:11], NSFontAttributeName, [NSColor blackColor], NSForegroundColorAttributeName, nil];
    return sReceivedAttributes;
}

+ (NSDictionary *)dataAttributes
{
    if (!sDataAttributes)
        sDataAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:[NSFont fontWithName:@"Courier" size:11], NSFontAttributeName, [NSColor blueColor], NSForegroundColorAttributeName, nil];
    return sDataAttributes;
}

+ (NSString *)name
{
	return @"Abstract Connection";
}

/*!	Returns an array of connection type names, like FTP, WebDav, etc.
 */
+ (NSMutableArray *)connectionTypes
{
	if (nil == _connectionTypes)
	{
		_connectionTypes = [[NSMutableArray array] retain];
	}
	return _connectionTypes;
}

/*!	Returns an array of class names
 */
+ (NSArray *)registeredConnectionTypes
{
	NSEnumerator *e = [[self connectionTypes] objectEnumerator];
	NSDictionary *cur;
	NSMutableArray *names = [NSMutableArray array];
	
	while (cur = [e nextObject])
	{
		Class class = NSClassFromString([cur objectForKey:ACClassKey]);
		[names addObject:[class name]];
	}
	[names sortUsingSelector:@selector(caseInsensitiveCompare:)];
	return names;
}

+ (NSString *)registeredPortForConnectionType:(NSString *)type
{
	NSEnumerator *e = [[self connectionTypes] objectEnumerator];
	NSDictionary *cur;
	
	while (cur = [e nextObject])
	{
		Class class = NSClassFromString([cur objectForKey:ACClassKey]);
		if ([[class name] isEqualToString:type]) {
			NSArray *types = [cur objectForKey:ACTypesKey];
			NSEnumerator *g = [types objectEnumerator];
			NSDictionary *t;
			
			while (t = [g nextObject]) {
				if ([[t objectForKey:ACTypeKey] isEqualToString:ACPortTypeKey])
					return [t objectForKey:ACTypeValueKey];
			}
		}
	}
	return nil;
}

#pragma mark -
#pragma mark Protocol Class Methods

+ (id <AbstractConnectionProtocol>)connectionWithName:(NSString *)name
												 host:(NSString *)host
												 port:(NSString *)port
											 username:(NSString *)username
											 password:(NSString *)password
{
	NSEnumerator *e = [[self connectionTypes] objectEnumerator];
	NSDictionary *cur;
	
	KTLog(ConnectionDomain, KTLogDebug, @"Finding class for %@ port: %@", name, port);
	
	if (!name) {
		return [AbstractConnection connectionToHost:host
											   port:port
										   username:username
										   password:password];
	}
	
	while (cur = [e nextObject])
	{
		Class class = NSClassFromString([cur objectForKey:ACClassKey]);
		NSString *n = [[class name] lowercaseString];
		NSString *searchName = [name lowercaseString];
		
		if ([n isEqualToString:searchName])
		{
			if ([class respondsToSelector:@selector(connectionToHost:port:username:password:)])
			{
				KTLog(ConnectionDomain, KTLogDebug, @"Matched to class %@", NSStringFromClass(class));
				if (port == nil)
					port = [AbstractConnection registeredPortForConnectionType:[class name]];
				return [class connectionToHost:host
										  port:port
									  username:username
									  password:password];
			}
		}
	}
	return nil;
}

+ (NSString *)urlSchemeForConnectionName:(NSString *)name port:(NSString *)port and:(BOOL)flag
{
	NSEnumerator *e = [[self connectionTypes] objectEnumerator];
	NSDictionary *cur;
	
	while (cur = [e nextObject])
	{
		if (!flag)
		{
			if ([[NSClassFromString([cur objectForKey:ACClassKey]) name] isEqualToString:name])
			{
				return [NSClassFromString([cur objectForKey:ACClassKey]) urlScheme];
			}
		}
		
		NSEnumerator *f = [[cur objectForKey:ACTypesKey] objectEnumerator];
		NSDictionary *type;
		
		while (type = [f nextObject])
		{
			NSString *connType = [type objectForKey:ACTypeKey];
			if ([connType isEqualToString:ACPortTypeKey])
			{
				if ([[type objectForKey:ACTypeValueKey] isEqualToString:port])
				{
					if (flag)
					{
						if ([[NSClassFromString([cur objectForKey:ACClassKey]) name] isEqualToString:name])
						{
							return [NSClassFromString([cur objectForKey:ACClassKey]) urlScheme];
						}
					}
					else
					{
						Class class = NSClassFromString([cur objectForKey:ACClassKey]);
						return [class urlScheme];
					}
				}
			}
		}
	}
	if (flag)
	{
		return [AbstractConnection urlSchemeForConnectionName:name port:port and:NO];
	}
	return nil;
}

+ (NSString *)urlSchemeForConnectionName:(NSString *)name port:(NSString *)port
{
	return [AbstractConnection urlSchemeForConnectionName:name port:port and:YES];
}

+ (id <AbstractConnectionProtocol>)connectionWithName:(NSString *)name
												 host:(NSString *)host
												 port:(NSString *)port
											 username:(NSString *)username
											 password:(NSString *)password
												error:(NSError **)error
{
	id result = nil;
	NSEnumerator *e = [[self connectionTypes] objectEnumerator];
	NSDictionary *cur;
	
	KTLog(ConnectionDomain, KTLogDebug, @"Finding class for %@ port: %@", name, port);
	
	if (!name) {
		result = [AbstractConnection connectionToHost:host
												 port:port
											 username:username
											 password:password
												error:error];
	}
	else
	{
		if ([[name lowercaseString] isEqualToString:@".mac"])
		{
			name = @"MobileMe";		// shim to allow for clients to continue using .Mac name internally
		}
		while (cur = [e nextObject])
		{
			Class class = NSClassFromString([cur objectForKey:ACClassKey]);
			NSString *n = [[class name] lowercaseString];
			NSString *searchName = [name lowercaseString];
			
			if ([n isEqualToString:searchName])
			{
				if ([class respondsToSelector:@selector(connectionToHost:port:username:password:)])
				{
					KTLog(ConnectionDomain, KTLogDebug, @"Matched to class %@", NSStringFromClass(class));
					if (port == nil)
						port = [AbstractConnection registeredPortForConnectionType:[class name]];
					
					result = [class connectionToHost:host
												port:port
											username:username
											password:password
											   error:error];
					break;
				}
			}
		}
	}
	if (!result && error)
	{
		NSError *err = [NSError errorWithDomain:ConnectionErrorDomain
										   code:ConnectionNoConnectionsAvailable
									   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(
																																@"No connection available for requested connection type", @"failed to find a connection class"),
												 NSLocalizedDescriptionKey,
												 [(*error) localizedDescription],
												 NSLocalizedRecoverySuggestionErrorKey,	// some additional context
												 nil]];
		*error = err;
	}
	
	return result;
}

/*!	Tries to guess what kind of connection to make based upon the port or ..... ?????????
 */

+ (id <AbstractConnectionProtocol>)connectionToHost:(NSString *)host
											   port:(NSString *)port
										   username:(NSString *)username
										   password:(NSString *)password
{
	NSEnumerator *e = [[self connectionTypes] objectEnumerator];
	NSDictionary *cur;
	
	while (cur = [e nextObject])
	{
		NSEnumerator *f = [[cur objectForKey:ACTypesKey] objectEnumerator];
		NSDictionary *type;
		
		while (type = [f nextObject])
		{
			NSString *connType = [type objectForKey:ACTypeKey];
			if ([connType isEqualToString:ACPortTypeKey])
			{
				if ([[type objectForKey:ACTypeValueKey] isEqualToString:port])
				{
					Class class = NSClassFromString([cur objectForKey:ACClassKey]);
					return [class connectionToHost:host
											  port:port
										  username:username
										  password:password];
				}
			}
			else if ([connType isEqualToString:ACURLTypeKey])
			{
				NSRange r;
				if ((r = [host rangeOfString:[type objectForKey:ACTypeValueKey]]).location != NSNotFound)
				{
					Class class = NSClassFromString([cur objectForKey:ACClassKey]);
					NSString *hostWithOutSpecifier = [host substringFromIndex:r.location + r.length];
					return [class connectionToHost:hostWithOutSpecifier
											  port:port
										  username:username
										  password:password];
				}
			}
		}
	}
	return nil;
}

+ (id <AbstractConnectionProtocol>)connectionToHost:(NSString *)host
											   port:(NSString *)port
										   username:(NSString *)username
										   password:(NSString *)password
											  error:(NSError **)error
{
	NSEnumerator *e = [[self connectionTypes] objectEnumerator];
	NSDictionary *cur;
	
	while (cur = [e nextObject])
	{
		NSEnumerator *f = [[cur objectForKey:ACTypesKey] objectEnumerator];
		NSDictionary *type;
		
		while (type = [f nextObject])
		{
			NSString *connType = [type objectForKey:ACTypeKey];
			if ([connType isEqualToString:ACPortTypeKey])
			{
				if ([[type objectForKey:ACTypeValueKey] isEqualToString:port])
				{
					Class class = NSClassFromString([cur objectForKey:ACClassKey]);
					return [class connectionToHost:host
											  port:port
										  username:username
										  password:password
											 error:error];
				}
			}
			else if ([connType isEqualToString:ACURLTypeKey])
			{
				NSRange r;
				if ((r = [host rangeOfString:[type objectForKey:ACTypeValueKey]]).location != NSNotFound)
				{
					Class class = NSClassFromString([cur objectForKey:ACClassKey]);
					NSString *hostWithOutSpecifier = [host substringFromIndex:r.location + r.length];
					return [class connectionToHost:hostWithOutSpecifier
											  port:port
										  username:username
										  password:password
											 error:error];
				}
			}
		}
	}
	if (error)
	{
		NSError *err = [NSError errorWithDomain:ConnectionErrorDomain
										   code:ConnectionNoConnectionsAvailable
									   userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInConnectionKitBundle(@"No connection available for requested port", @"failed to find a connection class")
																			forKey:NSLocalizedDescriptionKey]];
		*error = err;
	}
	
	return nil;
}

+ (id <AbstractConnectionProtocol>)connectionWithURL:(NSURL *)url
{
	NSString *resourceSpec = [url resourceSpecifier];
	NSString *host = [url host];
	NSString *user = [url user];
	NSString *pass = [url password];
	NSString *port = [NSString stringWithFormat:@"%@",[url port]];
	
	NSEnumerator *e = [[self connectionTypes] objectEnumerator];
	NSDictionary *cur;
	
	while (cur = [e nextObject])
	{
		NSEnumerator *f = [[cur objectForKey:ACTypesKey] objectEnumerator];
		NSDictionary *type;
		
		while (type = [f nextObject])
		{
			NSString *connType = [type objectForKey:ACTypeKey];
			if ([connType isEqualToString:ACPortTypeKey])
			{
				if ([[type objectForKey:ACTypeValueKey] isEqualToString:port])
				{
					Class class = NSClassFromString([cur objectForKey:ACClassKey]);
					return [class connectionToHost:host
											  port:port
										  username:user
										  password:pass];
				}
			}
			else if ([connType isEqualToString:ACURLTypeKey])
			{
				NSRange r;
				if ((r = [resourceSpec rangeOfString:[type objectForKey:ACTypeValueKey]]).location != NSNotFound)
				{
					Class class = NSClassFromString([cur objectForKey:ACClassKey]);
					NSString *hostWithOutSpecifier = [host substringFromIndex:r.location + r.length];
					return [class connectionToHost:hostWithOutSpecifier
											  port:port
										  username:user
										  password:pass];
				}
			}
		}
	}
	return nil;
}

+ (id <AbstractConnectionProtocol>)connectionWithURL:(NSURL *)url error:(NSError **)error
{
	NSString *resourceSpec = [url resourceSpecifier];
	NSString *host = [url host];
	NSString *user = [url user];
	NSString *pass = [url password];
	NSString *port = [NSString stringWithFormat:@"%@",[url port]];
	
	NSEnumerator *e = [[self connectionTypes] objectEnumerator];
	NSDictionary *cur;
	
	while (cur = [e nextObject])
	{
		NSEnumerator *f = [[cur objectForKey:ACTypesKey] objectEnumerator];
		NSDictionary *type;
		
		while (type = [f nextObject])
		{
			NSString *connType = [type objectForKey:ACTypeKey];
			if ([connType isEqualToString:ACPortTypeKey])
			{
				if ([[type objectForKey:ACTypeValueKey] isEqualToString:port])
				{
					Class class = NSClassFromString([cur objectForKey:ACClassKey]);
					return [class connectionToHost:host
											  port:port
										  username:user
										  password:pass
											 error:error];
				}
			}
			else if ([connType isEqualToString:ACURLTypeKey])
			{
				NSRange r;
				if ((r = [resourceSpec rangeOfString:[type objectForKey:ACTypeValueKey]]).location != NSNotFound)
				{
					Class class = NSClassFromString([cur objectForKey:ACClassKey]);
					NSString *hostWithOutSpecifier = [host substringFromIndex:r.location + r.length];
					return [class connectionToHost:hostWithOutSpecifier
											  port:port
										  username:user
										  password:pass
											 error:error];
				}
			}
		}
	}
	if (error)
	{
		NSError *err = [NSError errorWithDomain:ConnectionErrorDomain
										   code:ConnectionNoConnectionsAvailable
									   userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInConnectionKitBundle(@"No connection available for requested protocol", @"failed to find a connection class")
																			forKey:NSLocalizedDescriptionKey]];
		*error = err;
	}
	return nil;
}

#pragma mark -
#pragma mark Inheritable methods

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
			 error:(NSError **)error
{
	if (self = [super init])
	{
		[self setHost:host];
		[self setPort:port];
		[self setUsername:username];
		[self setPassword:password];
		_edits = [[NSMutableDictionary dictionary] retain];
		_properties = [[NSMutableDictionary dictionary] retain];
		_cachedDirectoryContents = [[NSMutableDictionary dictionary] retain];
		_flags.isConnected = NO;
		_forwarder = [[RunLoopForwarder alloc] init];
		_name = @"Default";
		[_forwarder setReturnValueDelegate:self];
		
		if (error)
		{
			*error = nil;
		}
	}
	return self;
}

- (void)dealloc
{
	[_name release];
	[_forwarder release];
	[_connectionHost release];
	[_connectionPort release];
	[_username release];
	[_password release];
	[_transcript release];
	[_properties release];
	[_cachedDirectoryContents release];
	[_edits release];
	[_editWatcher release];
	[_editingConnection forceDisconnect];
	[_editingConnection release];
	
	[super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
	NSError *err = nil;
	id <AbstractConnectionProtocol>copy = [[[self class] allocWithZone:zone] initWithHost:[self host]
																					 port:[self port]
																				 username:[self username]
																				 password:[self password]
																					error:&err];
	if (err)
	{
		NSLog(@"Failed to copy connection: %@", err);
		[copy release];
		return nil;
	}
	NSEnumerator *e = [_properties keyEnumerator];
	id key;
	
	while ((key = [e nextObject]))
	{
		[copy setProperty:[_properties objectForKey:key] forKey:key];
	}
	
	return copy;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@ - %@", [super description], _name];
}

- (void)setHost:(NSString *)host
{
	[_connectionHost autorelease];
	_connectionHost = [host copy];
}

- (void)setPort:(NSString *)port
{
	[_connectionPort autorelease];
	_connectionPort = [port copy];
}

- (void)setUsername:(NSString *)username
{
	[_username autorelease];
	_username = [username copy];
}

- (void)setPassword:(NSString *)password
{
	[_password autorelease];
	_password = [password copy];
}

- (NSString *)host
{
	return _connectionHost;
}

- (NSString *)port
{
	return _connectionPort;
}

- (NSString *)username
{
	return _username;
}

- (NSString *)password
{
	return _password;
}

- (void)setState:(ConnectionState)state
{
	_state = state;
}

- (ConnectionState)state
{
	return _state;
}

- (NSString *)stateName:(int)state
{
	switch (state) {
		case ConnectionNotConnectedState: return @"ConnectionNotConnectedState";
		case ConnectionIdleState: return @"ConnectionIdleState";
		case ConnectionSentUsernameState: return @"ConnectionSentUsernameState";
		case ConnectionSentAccountState: return @"ConnectionSentAccountState";	
		case ConnectionSentPasswordState: return @"ConnectionSentPasswordState";
		case ConnectionAwaitingCurrentDirectoryState: return @"ConnectionAwaitingCurrentDirectoryState";
		case ConnectionOpeningDataStreamState: return @"ConnectionOpeningDataStreamState";
		case ConnectionAwaitingDirectoryContentsState: return @"ConnectionAwaitingDirectoryContentsState";
		case ConnectionChangingDirectoryState: return @"ConnectionChangingDirectoryState";  
		case ConnectionCreateDirectoryState: return @"ConnectionCreateDirectoryState";
		case ConnectionDeleteDirectoryState: return @"ConnectionDeleteDirectoryState";
		case ConnectionRenameFromState: return @"ConnectionRenameFromState";		
		case ConnectionRenameToState: return @"ConnectionRenameToState";
		case ConnectionAwaitingRenameState: return @"ConnectionAwaitingRenameState";  
		case ConnectionDeleteFileState: return @"ConnectionDeleteFileState";
		case ConnectionDownloadingFileState: return @"ConnectionDownloadingFileState";
		case ConnectionUploadingFileState: return @"ConnectionUploadingFileState";	
		case ConnectionSentOffsetState: return @"ConnectionSentOffsetState";
		case ConnectionSentQuitState: return @"ConnectionSentQuitState";		
		case ConnectionSentFeatureRequestState: return @"ConnectionSentFeatureRequestState";
		case ConnectionSettingPermissionsState: return @"ConnectionSettingPermissionsState";
		case ConnectionSentSizeState: return @"ConnectionSentSizeState";		
		case ConnectionChangedDirectoryState: return @"ConnectionChangedDirectoryState";
		case ConnectionSentDisconnectState: return @"ConnectionSentDisconnectState";
		default: return @"Unknown State";
	}
}

- (void)setDelegate:(id)del
{
	_delegate = del;
	[_forwarder setDelegate:del];
	
	// There are 21 callbacks & flags.
	// Need to keep NSObject Category, __flags list, setDelegate: updated
	_flags.permissions						= [del respondsToSelector:@selector(connection:didSetPermissionsForFile:error:)];
	_flags.badPassword						= [del respondsToSelector:@selector(connectionDidSendBadPassword:)];
	_flags.cancel							= [del respondsToSelector:@selector(connectionDidCancelTransfer:)];
	_flags.didCancel						= [del respondsToSelector:@selector(connection:didCancelTransfer:)];
	_flags.changeDirectory					= [del respondsToSelector:@selector(connection:didChangeToDirectory:error:)];
	_flags.createDirectory					= [del respondsToSelector:@selector(connection:didCreateDirectory:error:)];
	_flags.deleteDirectory					= [del respondsToSelector:@selector(connection:didDeleteDirectory:error:)];
	_flags.deleteDirectoryInAncestor		= [del respondsToSelector:@selector(connection:didDeleteDirectory:inAncestorDirectory:error:)];
	_flags.deleteFileInAncestor				= [del respondsToSelector:@selector(connection:didDeleteFile:inAncestorDirectory:error:)];
	_flags.discoverFilesToDeleteInAncestor	= [del respondsToSelector:@selector(connection:didDiscoverFilesToDelete:inAncestorDirectory:)];
	_flags.discoverFilesToDeleteInDirectory = [del respondsToSelector:@selector(connection:didDiscoverFilesToDelete:inDirectory:)];
	_flags.deleteFile						= [del respondsToSelector:@selector(connection:didDeleteFile:error:)];
	_flags.didBeginUpload					= [del respondsToSelector:@selector(connection:uploadDidBegin:)];
	_flags.didConnect						= [del respondsToSelector:@selector(connection:didConnectToHost:error:)];
	_flags.didDisconnect					= [del respondsToSelector:@selector(connection:didDisconnectFromHost:)];
	_flags.directoryContents				= [del respondsToSelector:@selector(connection:didReceiveContents:ofDirectory:error:)];
	_flags.didBeginDownload					= [del respondsToSelector:@selector(connection:downloadDidBegin:)];
	_flags.downloadFinished					= [del respondsToSelector:@selector(connection:downloadDidFinish:error:)];
	_flags.downloadPercent					= [del respondsToSelector:@selector(connection:download:progressedTo:)];
	_flags.downloadProgressed				= [del respondsToSelector:@selector(connection:download:receivedDataOfLength:)];
	_flags.error							= [del respondsToSelector:@selector(connection:didReceiveError:)];
	_flags.needsAccount						= [del respondsToSelector:@selector(connection:needsAccountForUsername:)];
	_flags.rename							= [del respondsToSelector:@selector(connection:didRename:to:error:)];
	_flags.uploadFinished					= [del respondsToSelector:@selector(connection:uploadDidFinish:error:)];
	_flags.uploadPercent					= [del respondsToSelector:@selector(connection:upload:progressedTo:)];
	_flags.uploadProgressed					= [del respondsToSelector:@selector(connection:upload:sentDataOfLength:)];
	_flags.directoryContentsStreamed		= [del respondsToSelector:@selector(connection:didReceiveContents:ofDirectory:moreComing:)];
	_flags.fileCheck						= [del respondsToSelector:@selector(connection:checkedExistenceOfPath:pathExists:error:)];
	_flags.authorizeConnection				= [del respondsToSelector:@selector(connection:authorizeConnectionToHost:message:)];
	_flags.didAuthenticate					= [del respondsToSelector:@selector(connection:didAuthenticateToHost:error:)];
	_flags.passphrase						= [del respondsToSelector:@selector(connection:passphraseForHost:username:publicKeyPath:)];
}

- (id)delegate
{
	return _delegate;
}

- (void)setProperty:(id)property forKey:(NSString *)key
{
	[_properties setObject:property forKey:key];
}

- (id)propertyForKey:(NSString *)key
{
	return [_properties objectForKey:key];
}

- (void)removePropertyForKey:(NSString *)key;
{
	[_properties removeObjectForKey:key];
}


- (void)cacheDirectory:(NSString *)path withContents:(NSArray *)contents
{
	path = [path stringByStandardizingURLComponents];
	[_cachedDirectoryContents setObject:contents forKey:path];
}

- (NSArray *)cachedContentsWithDirectory:(NSString *)path
{
	path = [path stringByStandardizingURLComponents];
	return [_cachedDirectoryContents objectForKey:path];
}

- (void)clearDirectoryCache
{
	[_cachedDirectoryContents removeAllObjects];
}


#pragma mark -
#pragma mark Placeholder implementations

- (void)connect
{
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedConnect];
}

- (void)threadedConnect
{
	_flags.isConnected = YES;
	if (_flags.didConnect)
	{
		[_forwarder connection:self didConnectToHost:[self host] error:nil];
	}
}

- (BOOL)isConnected
{
	return _flags.isConnected;
}

- (void)disconnect
{
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedDisconnect];
}

- (void)threadedDisconnect
{
	_flags.isConnected = NO;
	if (_flags.didDisconnect)
	{
		[_forwarder connection:self didDisconnectFromHost:[self host]];
	}
}

- (void)forceDisconnect
{
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedForceDisconnect];
}

- (void)threadedForceDisconnect
{
	_flags.isConnected = NO;
	if (_flags.didDisconnect)
	{
		[_forwarder connection:self didDisconnectFromHost:[self host]];
	}
}


- (void) cleanupConnection
{
	NSLog (@"base class clean up, do we have to clean anything?");
}

#define SUBCLASS_RESPONSIBLE @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"%@ must implement %@", [self className], NSStringFromSelector(_cmd)] userInfo:nil];

- (void)changeToDirectory:(NSString *)dirPath
{
    SUBCLASS_RESPONSIBLE
}

- (NSString *)currentDirectory
{
	SUBCLASS_RESPONSIBLE
}

- (void)createDirectory:(NSString *)dirPath
{
	SUBCLASS_RESPONSIBLE
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	SUBCLASS_RESPONSIBLE
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	SUBCLASS_RESPONSIBLE
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	SUBCLASS_RESPONSIBLE
}

- (void)recursivelyRenameS3Directory:(NSString *)fromDirectoryPath to:(NSString *)toDirectoryPath;
{
	SUBCLASS_RESPONSIBLE
}

- (void)deleteFile:(NSString *)path
{
	SUBCLASS_RESPONSIBLE
}

- (void)deleteDirectory:(NSString *)dirPath
{
	SUBCLASS_RESPONSIBLE
}

- (void)recursivelyDeleteDirectory:(NSString *)path;
{
	SUBCLASS_RESPONSIBLE
}

- (void)uploadFile:(NSString *)localPath
{
	SUBCLASS_RESPONSIBLE
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	SUBCLASS_RESPONSIBLE
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{	
	SUBCLASS_RESPONSIBLE
}

- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (CKTransferRecord *)recursiveRecordWithPath:(NSString *)path root:(CKTransferRecord *)root
{
	NSString *first = [path firstPathComponent];
	if ([[root name] isEqualToString:first] || [[root path] isEqualToString:@"/"])
	{
		CKTransferRecord *child = nil;
		NSEnumerator *e = [[root contents] objectEnumerator];
		CKTransferRecord *cur;
		if (![[root path] isEqualToString:@"/"])
		{
			path = [path stringByDeletingFirstPathComponent];
		}
		if ([path isEqualToString:@"/"])
		{
			return root;
		}
		
		while ((cur = [e nextObject]))
		{
			child = [self recursiveRecordWithPath:path root:cur];
			if (child)
			{
				return child;
			}
		}
		
		// if we get here we need to create the record		
		CKTransferRecord *tmp = root;
		while (![path isEqualToString:@"/"])
		{
			cur = [CKTransferRecord recordWithName:[path firstPathComponent] size:0];
			[tmp addContent:cur];
			tmp = cur;
			path = [path stringByDeletingFirstPathComponent];
		}
		return cur;
	}
	return nil;
}

- (void)_mergeRecord:(CKTransferRecord *)rec into:(CKTransferRecord *)root
{
	CKTransferRecord *parent = [self recursiveRecordWithPath:[[rec name] stringByDeletingLastPathComponent] root:root];
	[rec setName:[[rec name] lastPathComponent]];		
	[parent addContent:rec];
}

- (CKTransferRecord *)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath root:(CKTransferRecord *)root rootPath:(NSString *)rootPath ignoreHiddenFiles:(BOOL)ignoreHiddenFilesFlag
{
	NSFileManager *fm = [NSFileManager defaultManager];
	CKTransferRecord *record;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL isDir;
	
	//create this directory
	[self createDirectory:remotePath];
	
	NSEnumerator *e = [[fm directoryContentsAtPath:localPath] objectEnumerator];
	NSString *path;
	NSUInteger numberOfSubRecordsAdded = 0;
	while ((path = [e nextObject]))
	{
		path = [localPath stringByAppendingPathComponent:path];
		if (ignoreHiddenFilesFlag && [[path lastPathComponent] hasPrefix:@"."])
			continue;
		
		numberOfSubRecordsAdded++;
		
		if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir)
		{
			[self recursivelyUpload:path 
								 to:[remotePath stringByAppendingPathComponent:[path lastPathComponent]] 
							   root:root 
						   rootPath:rootPath
				  ignoreHiddenFiles:ignoreHiddenFilesFlag];
		}
		else
		{
			NSString *remote = [remotePath stringByAppendingPathComponent:[path lastPathComponent]];
			record = [self uploadFile:path
							   toFile:remote
				 checkRemoteExistence:NO
							 delegate:nil];
			if (![[root path] isEqualToString:@"/"])
			{
				[self _mergeRecord:record into:root];
			}
			else
			{
				CKTransferRecord *parent = [self recursiveRecordWithPath:[[record name] stringByDeletingLastPathComponent] root:root];
				root = parent;
				[root setName:[[root name] lastPathComponent]];		
				[record setName:[[record name] lastPathComponent]];		
				[root addContent:record];
			}
		}
	}
	
	if (numberOfSubRecordsAdded == 0)
	{
		CKTransferRecord *record = [CKTransferRecord recordWithName:remotePath size:4];
		if (![[root path] isEqualToString:@"/"])
		{
			[self _mergeRecord:record into:root];
		}
		else
		{
			CKTransferRecord *parent = [self recursiveRecordWithPath:[[record name] stringByDeletingLastPathComponent] root:root];
			root = parent;
			[root setName:[[root name] lastPathComponent]];		
			[record setName:[[record name] lastPathComponent]];		
			[root addContent:record];
		}		
		[record transferDidFinish:record error:nil];
	}
	
	[pool release];
	return root;
}

- (CKTransferRecord *)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath
{
	return [self recursivelyUpload:localPath to:remotePath ignoreHiddenFiles:NO];
}

- (CKTransferRecord *)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath ignoreHiddenFiles:(BOOL)ignoreHiddenFilesFlag
{
	CKTransferRecord *root = [CKTransferRecord rootRecordWithPath:remotePath];
	[root setUpload:YES];
	NSFileManager *fm = [NSFileManager defaultManager];
	
	CKTransferRecord *record;
	BOOL isDir;
	
	[self startBulkCommands];
	
	if ([fm fileExistsAtPath:localPath isDirectory:&isDir] && !isDir)
	{
		NSString *remote = [remotePath stringByAppendingPathComponent:[localPath lastPathComponent]];
		record = [self uploadFile:localPath
						   toFile:remote
			 checkRemoteExistence:NO
						 delegate:nil];
		if (![[root path] isEqualToString:@"/"])
		{
			[self _mergeRecord:record into:root];
		}
		else
		{
			root = record;
			[root setUpload:YES];
			[root setName:[[root name] lastPathComponent]];		
		}
	}
	else
	{
		[self createDirectory:remotePath];
		root = [self recursivelyUpload:localPath 
									to:[remotePath stringByAppendingPathComponent:[localPath lastPathComponent]] 
								  root:root 
							  rootPath:remotePath
					 ignoreHiddenFiles:ignoreHiddenFilesFlag];
	}
	[self endBulkCommands];
	return root;
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(unsigned long long)offset
{
	SUBCLASS_RESPONSIBLE
}

- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	SUBCLASS_RESPONSIBLE
}

- (CKTransferRecord *)resumeUploadFile:(NSString *)localPath 
								toFile:(NSString *)remotePath 
							fileOffset:(unsigned long long)offset
							  delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	SUBCLASS_RESPONSIBLE
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	SUBCLASS_RESPONSIBLE
}

- (CKTransferRecord *)uploadFromData:(NSData *)data
							  toFile:(NSString *)remotePath 
				checkRemoteExistence:(BOOL)flag
							delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	SUBCLASS_RESPONSIBLE
}

- (CKTransferRecord *)resumeUploadFromData:(NSData *)data
									toFile:(NSString *)remotePath 
								fileOffset:(unsigned long long)offset
								  delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	SUBCLASS_RESPONSIBLE
}

- (CKTransferRecord *)downloadFile:(NSString *)remotePath 
					   toDirectory:(NSString *)dirPath 
						 overwrite:(BOOL)flag
						  delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(unsigned long long)offset
{
	SUBCLASS_RESPONSIBLE
}

- (CKTransferRecord *)resumeDownloadFile:(NSString *)remotePath
							 toDirectory:(NSString *)dirPath
							  fileOffset:(unsigned long long)offset
								delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (CKTransferRecord *)recursivelyDownload:(NSString *)remotePath
									   to:(NSString *)localPath
								overwrite:(BOOL)flag
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (BOOL)isBusy
{
	return NO;
}

- (unsigned)numberOfTransfers
{
	return 0;
}

- (void)cancelTransfer
{
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedCancelTransfer];
}

- (void)threadedCancelTransfer
{
	
}

- (void)cancelAll
{
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedCancelAll];
}

- (void)threadedCancelAll
{
	
}

- (long long)transferSpeed
{
	return 0;
}

- (double)uploadSpeed
{
	return 0;
}

- (double)downloadSpeed
{
	return 0;
}

- (NSString *)urlScheme
{
	return [[self class] urlScheme];
}

+ (NSString *)urlScheme
{
	return @"";
}

- (void)directoryContents
{
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	SUBCLASS_RESPONSIBLE
}

- (void)startBulkCommands
{
	_flags.inBulk = YES;
}

- (void)endBulkCommands
{
	_flags.inBulk = NO;
}

- (void)setTranscript:(NSTextStorage *)transcript
{
	[transcript retain];
	[_transcript release];
	_transcript = transcript;
}

- (NSTextStorage *)transcript
{
	return _transcript;
}

- (void)appendToTranscript:(NSAttributedString *)str
{
	if (_transcript) {
		[_transcript performSelectorOnMainThread:@selector(appendAttributedString:)
									  withObject:str
								   waitUntilDone:NO];
		//	[_transcript appendAttributedString:str];
	}
}

- (NSString *)rootDirectory
{
	return nil;
}

- (void)checkExistenceOfPath:(NSString *)path
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"AbstractConnection does not implement checkExistanceOfPath:"
								 userInfo:nil];
}

- (void)editFile:(NSString *)remotePath 
{
	NSString *localEditable = [NSTemporaryDirectory() stringByAppendingPathComponent:[remotePath lastPathComponent]];
	[_edits setObject:remotePath forKey:localEditable];
	if (!_editingConnection)
	{
		_editingConnection = [self copy];
		[_editingConnection setName:@"editing"];
		[_editingConnection setDelegate:self];
		[_editingConnection setTranscript:[self transcript]];
		[_editingConnection connect];
	}
	[_editingConnection downloadFile:remotePath toDirectory:[localEditable stringByDeletingLastPathComponent] overwrite:YES];
}

- (void)setName:(NSString *)name
{
	if (name != _name)
	{
		[_name autorelease];
		_name = [name copy];
	}
}

- (NSString *)name;
{
	return _name;
}

#pragma mark -
#pragma mark UKKQueue Delegate Methods

- (void)watcher:(id<UKFileWatcher>)kq receivedNotification:(NSString*)nm forPath:(NSString*)fpath
{
	if ([nm isEqualToString:UKFileWatcherAttributeChangeNotification]) //UKFileWatcherWriteNotification does not get called because of atomicity of file writing (i believe)
	{
		KTLog(EditingDomain, KTLogDebug, @"File changed: %@... uploading to server", fpath);
		[self uploadFile:fpath toFile:[_edits objectForKey:fpath]];
	}
}

#pragma mark -
#pragma mark Editing Connection Delegate Methods

- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host
{
	if (con == _editingConnection)
	{
		[_editingConnection release];
		_editingConnection = nil;
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con download:(NSString *)path progressedTo:(NSNumber *)percent
{
	if (_flags.downloadPercent)
	{
		[_forwarder connection:self download:path progressedTo:percent];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con download:(NSString *)path receivedDataOfLength:(unsigned long long)length
{
	if (_flags.downloadProgressed)
	{
		[_forwarder connection:self download:path receivedDataOfLength:length];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con downloadDidBegin:(NSString *)remotePath
{
	if (_flags.didBeginUpload)
	{
		[_forwarder connection:self downloadDidBegin:remotePath];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con downloadDidFinish:(NSString *)remotePath error:(NSError *)error
{
	if (_flags.downloadFinished)
	{
		[_forwarder connection:self downloadDidFinish:remotePath error:error];
	}
	KTLog(EditingDomain, KTLogDebug, @"Downloaded file %@... watching for changes", remotePath);
	NSEnumerator *e = [_edits keyEnumerator];
	NSString *key, *cur;
	
	while ((key = [e nextObject]))
	{
		cur = [_edits objectForKey:key];
		if ([cur isEqualToString:remotePath])
		{
			if (!_editWatcher)
			{
				_editWatcher = [[UKKQueue alloc] init];
				[_editWatcher setDelegate:self];
			}
			[_editWatcher addPathToQueue:key];
			KTLog(EditingDomain, KTLogDebug, @"Opening file for editing %@", key);
			[[NSWorkspace sharedWorkspace] openFile:key];
		}
	}
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath progressedTo:(NSNumber *)percent
{
	if (_flags.uploadPercent)
	{
		[_forwarder connection:self upload:remotePath progressedTo:percent];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath sentDataOfLength:(unsigned long long)length
{
	if (_flags.uploadProgressed)
	{
		[_forwarder connection:self upload:remotePath sentDataOfLength:length];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidBegin:(NSString *)remotePath
{
	if (_flags.didBeginUpload)
	{
		[_forwarder connection:self uploadDidBegin:remotePath];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidFinish:(NSString *)remotePath error:(NSError *)error
{
	if (_flags.uploadFinished)
	{
		[_forwarder connection:self uploadDidFinish:remotePath error:error];
	}
}

@end

@implementation NSString (AbstractConnectionExtras)

- (NSString *)stringByAppendingDirectoryTerminator
{
    if ( ![self hasSuffix:@"/"] )
    {
        return [self stringByAppendingString:@"/"];
    }
    else
    {
        return self;
    }
}

@end

@implementation NSInvocation (AbstractConnectionExtras)

+ (NSInvocation *)invocationWithSelector:(SEL)aSelector target:(id)aTarget arguments:(NSArray *)anArgumentArray
{
    NSMethodSignature *methodSignature = [aTarget methodSignatureForSelector:aSelector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    if ( nil != invocation )
    {
        [invocation setSelector:aSelector];
        [invocation setTarget:aTarget];
        if ( (nil != anArgumentArray) && ([anArgumentArray count] > 0) )
        {
            NSEnumerator *e = [anArgumentArray objectEnumerator];
            id argument;
            int argumentIndex = 2; // arguments start at index 2 per NSInvocation.h
            while ( argument = [e nextObject] )
            {
                if ( [argument isMemberOfClass:[NSNull class]] )
                {
                    [invocation setArgument:nil atIndex:argumentIndex];
                }
                else
                {
                    [invocation setArgument:&argument atIndex:argumentIndex];
                }
                argumentIndex++;
            }
            [invocation retainArguments];
        }
    }
	
    return invocation;
}

@end

int filenameSort(id obj1, id obj2, void *context)
{
    NSString *f1 = [obj1 objectForKey:[cxFilenameKey lastPathComponent]];
	NSString *f2 = [obj2 objectForKey:[cxFilenameKey lastPathComponent]];
	
	return [f1 caseInsensitiveCompare:f2];
}

@implementation NSFileManager (AbstractConnectionExtras)

+ (NSString *)fixFilename:(NSString *)filename withAttributes:(NSMutableDictionary *)attributes
{
	NSString *fname = [NSString stringWithString:[filename stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	NSString *type = [attributes objectForKey:NSFileType];
	if ([type isEqualToString:NSFileTypeDirectory]) 
	{
		if ([fname hasSuffix:@"/"])
			fname = [fname substringToIndex:[fname length] - 1];
	}
	if ([type isEqualToString:NSFileTypeSymbolicLink]) 
	{
		if ([fname hasSuffix:@"@"])
			fname = [fname substringToIndex:[fname length] - 1];
	}
	if ([fname hasSuffix:@"@"]) //We get @'s on the filename for aliases on Mac OS X Server.
	{
		[attributes setObject:NSFileTypeSymbolicLink forKey:NSFileType];
		fname = [fname substringToIndex:[fname length] - 1];
	}
	NSNumber *permissions = [attributes objectForKey:NSFilePosixPermissions];
	if (permissions)
	{
		unsigned long perms = [permissions unsignedLongValue];
		if ((perms & 01) || (perms & 010) || (perms & 0100))
		{
			if ([fname hasSuffix:@"*"])
				fname = [fname substringToIndex:[fname length] - 1];
		}
	}
	return fname;
}

/* 
 "-rw-r--r--   1 root     other        531 Jan 29 03:26 README"
 "dr-xr-xr-x   2 root     other        512 Apr  8  1994 etc"
 "dr-xr-xr-x   2 root     512 Apr  8  1994 etc"
 "lrwxrwxrwx   1 root     other          7 Jan 25 00:17 bin -> usr/bin"
 Also produced by Microsofts FTP servers for Windows:
 "----------   1 owner    group         1803128 Jul 10 10:18 ls-lR.Z"
 "d---------   1 owner    group               0 May  9 19:45 Softlib"
 Windows also produces this crap 
 "10-20-05  05:19PM       <DIR>          fordgt/"
 "10-21-05  08:14AM                 4927 index.html"
 Also WFTPD for MSDOS: 
 "-rwxrwxrwx   1 noone    nogroup      322 Aug 19  1996 message.ftp" 
 Also NetWare:
 "d [R----F--] supervisor            512       Jan 16 18:53    login" 
 "- [R----F--] rhesus             214059       Oct 20 15:27    cx.exe"
 Also NetPresenz for the Mac:
 "-------r--         326  1391972  1392298 Nov 22  1995 MegaPhone.sit"
 "drwxrwxr-x               folder        2 May 10  1996 network"
 */

#define CONDITIONALLY_ADD NSString *fn = [attributes objectForKey:cxFilenameKey]; \
if (![fn isEqualToString:@"."] && \
![fn isEqualToString:@".."]) \
{ \
[attributedLines addObject:attributes]; \
}

+ (BOOL)wordIsInteger:(NSString *)word
{
	return [word isEqualToString:[[NSNumber numberWithInt:[word intValue]] stringValue]];
}

+ (NSString *)filenameFromIndex:(int)index inWords:(NSArray *)words attributes:(NSMutableDictionary *)attributes
{
	NSMutableString *tempStr = [NSMutableString string];
	while (index < [words count])
	{
		[tempStr appendFormat:@"%@ ", [words objectAtIndex:index]];
		index++;
	}
	return [self fixFilename:tempStr withAttributes:attributes];
}
+ (NSArray *)_linesFromListing:(NSString *)listing
{
	NSString *lineEnding = @"\r\n";
	//Determine how we break lines
	if ([listing rangeOfString:@"\r\n"].location == NSNotFound)
	{
		//We don't have \r\n, what about \n?
		if ([listing rangeOfString:@"\n"].location == NSNotFound)
		{
			//No way to separate lines, error.
			NSError *error = [NSError errorWithDomain:ConnectionErrorDomain code:ConnectionErrorParsingDirectoryListing userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInConnectionKitBundle(@"Error parsing directory listing", @"Directory Parsing Error") forKey:NSLocalizedDescriptionKey]];
			KTLog(ParsingDomain, KTLogError, @"Could not determine line endings, try refreshing directory");
			@throw error;
			return nil;
		}
		lineEnding = @"\n";
	}
	return [listing componentsSeparatedByString:lineEnding];
}
+ (NSArray *)_wordsFromLine:(NSString *)line
{
	NSArray *words = [line componentsSeparatedByString:@" "]; //Is NOT the same as componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]. Separating by character set interprets multiple whitespaces next to each other as a _single_ separator. We don't want that
	NSMutableArray *finalWords = [NSMutableArray arrayWithArray:words];
	
	//Remove all blank spaces before the date. After the date, blank spaces (even next to each other) are _valid_ characters in a filename. They cannot be removed.
	NSString *dateString = [self _dateStringFromListing:line];
	if (!dateString)
		return finalWords;
	NSString *lastDateWord = dateString;
	NSUInteger currentLocation = [dateString length] - 1;
	while (currentLocation >= 0)
	{
		unichar currentCharacter = [dateString characterAtIndex:currentLocation];
		if (currentCharacter == ' ')
		{
			//Everything after this index is part of the last word.
			lastDateWord = [dateString substringFromIndex:currentLocation+1];
			break;
		}
		currentLocation--;
	}
	
	/*
	 We loop by index instead of fast enumeration or an enumerator because we _need_ the index anyway. We need the index because we cannot remove objects from finalWords using removeObject, as it would simply remove _all_ the objects that return YES to isEqual:, which in the case of NSString, is more than just the object we've iterated to –– it would include all objects of equivalent value (i.e., all empty strings). That being said, we could use -removeObjectIdenticalTo:, but the documentation states that -removeObjectIdenticalTo: simply asks for the index, which we already have if loop by index ourselves.
	 */
	NSUInteger currentIndex = 0;
	NSMutableIndexSet *indexesOfBlankSpacesBeforeDate = [NSMutableIndexSet indexSet];
	while (currentIndex < [words count])
	{
		NSString *word = [words objectAtIndex:currentIndex];
		if ([word length] <= 0 || [word characterAtIndex:0] == ' ')
			[indexesOfBlankSpacesBeforeDate addIndex:currentIndex];
		if ([lastDateWord containsSubstring:word])
			break;
		currentIndex++;
	}
	[finalWords removeObjectsAtIndexes:indexesOfBlankSpacesBeforeDate];
	return finalWords;
}

+ (NSString *)_dateStringFromListing:(NSString *)listing
{
	//This regex finds the entire date. "May 12 2006" or "May 12 12:15"
	NSString *anyMonthRegex = @"((Jan)|(Feb)|(Mar)|(Apr)|(May)|(Jun)|(Jul)|(Aug)|(Sep)|(Oct)|(Nov)|(Dec))";
	NSString *anyDayRegex = @"((0*[1-9])|([12][0-9])|(3[01]))";
	NSString *anyTimeRegex = @"(([012]*[0-9]):([0-5][0-9]))";
	NSString *anyYearRegex = @"[0-9]{4}";
	NSString *anyDateRegex = [NSString stringWithFormat:@"%@( )+%@( )+(%@|%@)", anyMonthRegex, anyDayRegex, anyTimeRegex, anyYearRegex, nil];
	NSRange dateRange = [listing rangeOfRegex:anyDateRegex];
	if (dateRange.location == NSNotFound)
		return nil;

	return [listing substringWithRange:dateRange];
}
+ (int)_filenameColumnIndexFromLine:(NSString *)line
{
	/*
		* Look for the date, and base the filename column index as the column after that.
		* If we can't find the date or "." or "..", use popular-assumptions about the filename column index based on the number of columns we have.
	*/
	int filenameColumnIndex = -1;
	NSString *date = [self _dateStringFromListing:line];
	NSArray *words = [self _wordsFromLine:line];
	
	if (date)
	{
		//Filename is after the date column.
		NSString *lastColumnStringOfDate = [[date componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lastObject];
		int lastDateColumnIndex = [words indexOfObject:lastColumnStringOfDate];
		if (lastDateColumnIndex != NSNotFound)
			filenameColumnIndex = lastDateColumnIndex + 1;
	}

	if (filenameColumnIndex == -1)
	{
		//If we can't find the date or "." or "..", use popular-assumptions about the filename column index based on the number of columns we have.
		switch ([words count])
		{
			case 10:
				//-rwx------ 1 user group           2252 May 22 04:20 Project-Video Planning.rtf
				filenameColumnIndex = 8;
				break;
			case 9:
				//-rwx------ 1 user group           2252 May 22 04:20 myFile.tiff
				filenameColumnIndex = 7;
				break;
			case 8: //No Group
				//-rwx------ 1 user            2252 May 22 04:20 myFile.tiff
				filenameColumnIndex = 6;
				break;
			default:
				filenameColumnIndex = [words count] - 1;
				break;
		}			
	}

	return filenameColumnIndex;
}
+ (NSArray *)attributedFilesFromListing:(NSString *)listing
{
	if ([listing length] == 0)
		return [NSArray array];
	
	NSMutableArray *attributedLines = [NSMutableArray array];

	NSArray *lines = [NSFileManager _linesFromListing:listing];
	
	NSEnumerator *lineEnumerator = [lines objectEnumerator];
	NSString *line;
	while ((line = [lineEnumerator nextObject]))
	{
		if ([line length] <= 0)
			continue;
		
		NSArray *words = [NSFileManager _wordsFromLine:line];
		
		//index should be 
		// 0 - type and permissions
		// 1 - number of links
		// 2 - owner
		// 3 - group / size
		// 4 - size / date - month
		// 5 - date - month / date - day 
		// 6 - date - day / date - year or time
		// 7 - date - year or time / filename
		// 8 - filename / -> link arrow
		// 9 - link arrow / link target
		// 10 - link target
		
		if ([words count] < 4)
			continue;
		
		NSString *wordZero = [words objectAtIndex:0];
		NSString *wordOne = [words objectAtIndex:1];
		NSString *wordTwo = [words objectAtIndex:2];
		NSString *wordThree = [words objectAtIndex:3];
		NSString *wordFour = ([words count] >= 5) ? [words objectAtIndex:4] : nil;
		NSString *wordFive = ([words count] >= 6) ? [words objectAtIndex:5] : nil;
		NSString *wordSix = ([words count] >= 7) ? [words objectAtIndex:6] : nil;
		NSString *wordSeven = ([words count] >= 8) ? [words objectAtIndex:7] : nil;
		
		NSCalendarDate *date = nil;
		NSNumber *referenceCount = nil;
		NSNumber *size = nil;
		
		NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
		
		if ([wordOne hasSuffix:@"PM"] || [wordOne hasSuffix:@"AM"]) //Disgusting MSDOS Server
		{
			//11-25-05 03:42PM   <DIR>     folder/
			//02-18-08 04:57PM          0123 file
			NSString *dateString = [NSString stringWithFormat:@"%@ %@", wordZero, wordOne];
			date = [NSCalendarDate dateWithString:dateString calendarFormat:@"%m-%d-%y %I:%M%p"];
			
			if ([wordTwo isEqualToString:@"<DIR>"])
			{
				[attributes setObject:NSFileTypeDirectory forKey:NSFileType];
			}
			else
			{
				size = [NSNumber numberWithInt:[wordTwo intValue]];
				[attributes setObject:NSFileTypeRegular forKey:NSFileType];
			}
			[NSFileManager parseFilenameAndSymbolicLinksFromIndex:3 ofWords:words withAttributes:attributes];
		}		
		else if ([wordOne isEqualToString:@"folder"]) //netprez folder
		{
			[self parsePermissions:wordZero withAttributes:attributes];
			referenceCount = [NSNumber numberWithInt:[wordTwo intValue]];
			date = [NSCalendarDate getDateFromMonth:wordThree day:wordFour yearOrTime:wordFive];
			[NSFileManager parseFilenameAndSymbolicLinksFromIndex:6 ofWords:words withAttributes:attributes];
		}
		else if ([NSFileManager wordIsInteger:wordTwo] && [NSFileManager wordIsInteger:wordFour] && [wordFive intValue] >= 0 && [wordSix intValue] <= 31 && [wordSix intValue] > 0)
		{
			/* "drwxr-xr-x    2 32224    bainbrid     4096 Nov  8 20:56 aFolder" */ 
			[self parsePermissions:wordZero withAttributes:attributes];
			referenceCount = [NSNumber numberWithInt:[wordOne intValue]];
			date = [NSCalendarDate getDateFromMonth:wordFive day:wordSix yearOrTime:wordSeven];
			size = [NSNumber numberWithDouble:[wordFour doubleValue]];
			[NSFileManager parseFilenameAndSymbolicLinksFromIndex:8 ofWords:words withAttributes:attributes];
		}
		else if ([NSFileManager wordIsInteger:wordTwo] && [wordFive intValue] <= 31 && [wordFive intValue] > 0) // netprez file
		{
			/* "-------r--         326  1391972  1392298 Nov 22  1995 MegaPhone.sit" */ 
			[self parsePermissions:wordZero withAttributes:attributes];
			referenceCount = [NSNumber numberWithInt:[wordOne intValue]];
			date = [NSCalendarDate getDateFromMonth:wordFour day:wordFive yearOrTime:wordSix];
			size = [NSNumber numberWithDouble:[wordThree doubleValue]];
			[NSFileManager parseFilenameAndSymbolicLinksFromIndex:7 ofWords:words withAttributes:attributes];
		}
		else if ([wordOne isEqualToString:@"FTP"] && [wordTwo isEqualToString:@"User"]) //Trellix FTP Server
		{
			[self parsePermissions:wordZero withAttributes:attributes];
			size = [NSNumber numberWithDouble:[wordThree doubleValue]];
			date = [NSCalendarDate getDateFromMonth:wordFour day:wordFive yearOrTime:wordSix];
			[self parseFilenameAndSymbolicLinksFromIndex:7 ofWords:words withAttributes:attributes];
		}
		else //Everything else
		{
			//Permissions
			[self parsePermissions:wordZero withAttributes:attributes];
			
			//Reference Count
			referenceCount = [NSNumber numberWithInt:[wordOne intValue]];
			
			//Account
			[attributes setObject:wordTwo forKey:NSFileOwnerAccountName]; //Account
			
			//Date
			NSString *dateString = [NSFileManager _dateStringFromListing:line]; //Date
			if (!dateString)
			{
				//Much of what we do from this point is based on finding the date. This is a serious bug, and should be addressed. Log it out, report an error.
				NSLog(@"Could not parse date from line %@ of listing %@", line, listing);
				NSError *error = [NSError errorWithDomain:ConnectionErrorDomain code:ConnectionErrorParsingDirectoryListing userInfo:[NSDictionary dictionaryWithObject:LocalizedStringInConnectionKitBundle(@"Error parsing directory listing", @"Directory Parsing Error") forKey:NSLocalizedDescriptionKey]];
				@throw error;
			}

			NSArray *dateComponents = [dateString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			NSString *month = [dateComponents objectAtIndex:0];
			NSString *day = [dateComponents objectAtIndex:1];
			NSString *yearOrTime = [dateComponents objectAtIndex:2];			
			date = [NSCalendarDate getDateFromMonth:month day:day yearOrTime:yearOrTime];
			
			//Size
			int monthColumnIndex = [words indexOfObject:month];
			int sizeColumnIndex = monthColumnIndex - 1;
			size = [NSNumber numberWithDouble:[[words objectAtIndex:sizeColumnIndex] doubleValue]];
			
			//Group
			NSString *group = [NSString string];
			int currentIndex = 3; //Account's columnIndex is 2. Everything in between account and size is group.
			while (currentIndex < sizeColumnIndex)
			{
				group = [group stringByAppendingString:[words objectAtIndex:currentIndex]];
				currentIndex++;
			}
			[attributes setObject:group forKey:NSFileGroupOwnerAccountName];
			
			//Filename
			int filenameColumnIndex = [NSFileManager _filenameColumnIndexFromLine:line];
			[self parseFilenameAndSymbolicLinksFromIndex:filenameColumnIndex ofWords:words withAttributes:attributes];
		}
		
		if (date)
			[attributes setObject:date forKey:NSFileModificationDate];
		if (referenceCount)
			[attributes setObject:referenceCount forKey:NSFileReferenceCount];
		if (size)
			[attributes setObject:size forKey:NSFileSize];
		CONDITIONALLY_ADD	
	}
	
	return [attributedLines sortedArrayUsingFunction:filenameSort context:NULL];
}
+ (void)parseFilenameAndSymbolicLinksFromIndex:(int)index ofWords:(NSArray *)words withAttributes:(NSMutableDictionary *)attributes
{
	NSString *fileType = [attributes objectForKey:NSFileType];
	if ([fileType isEqualToString:NSFileTypeCharacterSpecial] || [fileType isEqualToString:NSFileTypeBlockSpecial])
	{
		index++;
		if (index >= [words count]) // sftp listings do not have the extra column
			index = [words count] - 1;
	}
	
	if ([fileType isEqualToString:NSFileTypeSymbolicLink])
	{
		NSMutableArray *filenameBits = [NSMutableArray array];
		while (index < [words count])
		{
			NSString *bit = [words objectAtIndex:index];
			if ([bit rangeOfString:@"->"].location != NSNotFound)
			{
				index++;
				break;
			}
			[filenameBits addObject:bit];
			index++;
		}
		NSArray *symBits = [words subarrayWithRange:NSMakeRange(index, [words count] - index)];
		NSString *filenameStr = [filenameBits componentsJoinedByString:@" "];
		filenameStr = [filenameStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString *symTarget = [symBits componentsJoinedByString:@" "];
		symTarget = [symTarget stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		
		[attributes setObject:[self fixFilename:filenameStr withAttributes:attributes] forKey:cxFilenameKey];
		[attributes setObject:[self fixFilename:symTarget withAttributes:attributes] forKey:cxSymbolicLinkTargetKey];
	}
	else
	{
		NSArray *filenameBits = [words subarrayWithRange:NSMakeRange(index, [words count] - index)];
		NSString *filenameStr = [filenameBits componentsJoinedByString:@" "];
		[attributes setObject:[self fixFilename:filenameStr withAttributes:attributes] forKey:cxFilenameKey];
	}
}
+ (void)parsePermissions:(NSString *)perm withAttributes:(NSMutableDictionary *)attributes
{
	char *data = (char *)[perm UTF8String];
	
	//what type of file is it
	switch (*data)
	{
		case '-': [attributes setObject:NSFileTypeRegular forKey:NSFileType]; break;
		case 'l': [attributes setObject:NSFileTypeSymbolicLink forKey:NSFileType]; break;
		case 'd': [attributes setObject:NSFileTypeDirectory forKey:NSFileType]; break;
		case 'c': [attributes setObject:NSFileTypeCharacterSpecial forKey:NSFileType]; break;
		case 'b': [attributes setObject:NSFileTypeBlockSpecial forKey:NSFileType]; break;
		default: [attributes setObject:NSFileTypeUnknown forKey:NSFileType]; break;
	}
	data++;
	//permisions
	switch (*data)
	{
		case 'r':
		case '-': //unix style listing
		{
			unsigned long perm = 0;
			//owner
			if (*data++ == 'r')		perm |= 0400;
			if (*data++ == 'w')		perm |= 0200;
			if (*data++ == 'x')		perm |= 0100;
			//group
			if (*data++ == 'r')		perm |= 040;
			if (*data++ == 'w')		perm |= 020;
			if (*data++ == 'x')		perm |= 010;
			//world
			if (*data++ == 'r')		perm |= 04;
			if (*data++ == 'w')		perm |= 02;
			if (*data++ == 'x')		perm |= 01;
			// clang flags data++ above as not being read, but it's just being scanned and skipped
			[attributes setObject:[NSNumber numberWithUnsignedLong:perm] forKey:NSFilePosixPermissions];
			break;
		}
		case ' ': //[---------]
		{
			while (*data != ']')
				data++;
			data++; // clang flags this but data is just being scanned past here
			break;
		}
		default:
			KTLog(ParsingDomain, KTLogError, @"Unknown FTP Permission state");
	}
}
@end

@implementation NSCalendarDate (AbstractConnectionExtras)
+ (NSCalendarDate *)getDateFromMonth:(NSString *)month day:(NSString *)day yearOrTime:(NSString *)yearOrTime
{
	NSCalendarDate * date;
	// Has a Year
	if ([yearOrTime rangeOfString:@":"].location == NSNotFound) 
	{
		date = [NSCalendarDate dateWithString:[NSString stringWithFormat:@"%@ %@ %@", month, day, yearOrTime] calendarFormat:@"%b %d %Y"];
	}
	// Has A Time
	else 
	{
		NSCalendarDate *now = [NSCalendarDate date];
		date = [NSCalendarDate dateWithString:[NSString stringWithFormat:@"%@ %@ %d %@", month, day, [now yearOfCommonEra], yearOrTime] calendarFormat:@"%b %d %Y %H:%M"];
		
		//Is the date in the future?
		if ([date compare:now] == NSOrderedDescending)
		{
			NSTimeInterval timeDifference = [date timeIntervalSinceDate:now];
			float sixMonthsInSeconds = (3600*24*30.5*6);
			if (timeDifference > sixMonthsInSeconds) //If it's beyond 6 months in the future, it would not have been without a year. Roll it back.
			{
				date = [NSCalendarDate dateWithYear:[date yearOfCommonEra] - 1
											  month:[date monthOfYear]
												day:[date dayOfMonth]
											   hour:[date hourOfDay]
											 minute:[date minuteOfHour]
											 second:[date secondOfMinute]
										   timeZone:[date timeZone]];
			}			
		}
	}
	
	return date;
}
@end

@implementation NSHost (IPV4)
- (NSString *)ipv4Address
{
	NSEnumerator *e = [[self addresses] objectEnumerator];
	NSString *cur;
	
	while (cur = [e nextObject]) {
		if ([cur rangeOfString:@"."].location != NSNotFound)
			return cur;
	}
	return nil;
}
@end

@implementation NSArray (AbstractConnectionExtras)
- (NSArray *)filteredArrayByRemovingHiddenFiles
{
	NSMutableArray *files = [NSMutableArray array];
	NSEnumerator *e = [self objectEnumerator];
	NSDictionary *cur;
	
	while ((cur = [e nextObject]))
	{
		if (![[[cur objectForKey:cxFilenameKey] lastPathComponent] hasPrefix:@"."])
		{
			[files addObject:cur];
		}
	}
	return files;
}
@end

/*Copyright (c) 2008 Extendmac, LLC. <support@extendmac.com>
 
 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 */

#import "EMKeychainItem.h"

@interface EMKeychainItem (Private)
- (BOOL)_modifyAttributeWithTag:(SecItemAttr)attributeTag toBeString:(NSString *)newStringValue;
@end

@implementation EMKeychainItem

- (id)initWithCoreKeychainItem:(SecKeychainItemRef)item
					  username:(NSString *)username
					  password:(NSString *)password
{
	if ((self = [super init]))
	{
		coreKeychainItem = item;
		_username = [username copy];
		_password = [password copy];
		return self;
	}
	return nil;
}

- (void)dealloc
{
	[_username release];
	[_password release];
	[_label release];
	
	[super dealloc];
}

- (NSString *)password { return _password; }

- (BOOL)setPassword:(NSString *)newPasswordString
{
	if (!newPasswordString)
	{
		return NO;
	}
	[self willChangeValueForKey:@"password"];
	[_password release];
	_password = [newPasswordString copy];
	[self didChangeValueForKey:@"password"];
	
	const char *newPassword = [newPasswordString UTF8String];
	OSStatus returnStatus = SecKeychainItemModifyAttributesAndData(coreKeychainItem, NULL, strlen(newPassword), (void *)newPassword);
	return (returnStatus == noErr);	
}

- (NSString *)username { return _username; }

- (BOOL)setUsername:(NSString *)newUsername
{
	[self willChangeValueForKey:@"username"];
	[_username release];
	_username = [newUsername copy];
	[self didChangeValueForKey:@"username"];	
	
	return [self _modifyAttributeWithTag:kSecAccountItemAttr toBeString:newUsername];
}

- (NSString *)label { return _label; }

- (BOOL)setLabel:(NSString *)newLabel
{
	[self willChangeValueForKey:@"label"];
	[_label release];
	_label = [newLabel copy];
	[self didChangeValueForKey:@"label"];
	
	return [self _modifyAttributeWithTag:kSecLabelItemAttr toBeString:newLabel];
}

- (BOOL)_modifyAttributeWithTag:(SecItemAttr)attributeTag toBeString:(NSString *)newStringValue
{
	const char *newValue = [newStringValue UTF8String];
	SecKeychainAttribute attributes[1];
	attributes[0].tag = attributeTag;
	attributes[0].length = strlen(newValue);
	attributes[0].data = (void *)newValue;
	
	SecKeychainAttributeList list;
	list.count = 1;
	list.attr = attributes;
	
	OSStatus returnStatus = SecKeychainItemModifyAttributesAndData(coreKeychainItem, &list, 0, NULL);
	return (returnStatus == noErr);
}

@end

@implementation EMGenericKeychainItem

- (id)initWithCoreKeychainItem:(SecKeychainItemRef)item
				   serviceName:(NSString *)serviceName
					  username:(NSString *)username
					  password:(NSString *)password
{
	if ((self = [super initWithCoreKeychainItem:item username:username password:password]))
	{
		_serviceName = [serviceName copy];
		return self;
	}
	return nil;
}

- (void)dealloc
{
	[_serviceName release];
	
	[super dealloc];
}

+ (id)genericKeychainItem:(SecKeychainItemRef)item 
		   forServiceName:(NSString *)serviceName
				 username:(NSString *)username
				 password:(NSString *)password
{
	return [[[EMGenericKeychainItem alloc] initWithCoreKeychainItem:item serviceName:serviceName username:username password:password] autorelease];
}

- (NSString *)serviceName { return _serviceName; }

- (BOOL)setServiceName:(NSString *)newServiceName
{
	[self willChangeValueForKey:@"serviceName"];
	[_serviceName release];
	_serviceName = [newServiceName copy];
	[self didChangeValueForKey:@"serviceName"];	
	
	return [self _modifyAttributeWithTag:kSecServiceItemAttr toBeString:newServiceName];
}

@end

@implementation EMInternetKeychainItem

- (id)initWithCoreKeychainItem:(SecKeychainItemRef)item
						server:(NSString *)server
					  username:(NSString *)username
					  password:(NSString *)password
						  path:(NSString *)path
						  port:(NSInteger)port
					  protocol:(SecProtocolType)protocol
{
	if ((self = [super initWithCoreKeychainItem:item username:username password:password]))
	{
		_server = [server copy];
		_path = [path copy];
		_port = port;
		_protocol = protocol;
		return self;
	}
	return nil;
}

- (void)dealloc
{
	[_server release];
	[_path release];
	
	[super dealloc];
}

+ (id)internetKeychainItem:(SecKeychainItemRef)item
				 forServer:(NSString *)server
				  username:(NSString *)username
				  password:(NSString *)password
					  path:(NSString *)path
					  port:(NSInteger)port
				  protocol:(SecProtocolType)protocol
{
	return [[[EMInternetKeychainItem alloc] initWithCoreKeychainItem:item server:server username:username password:password path:path port:port protocol:protocol] autorelease];
}

- (NSString *)server { return _server; }

- (BOOL)setServer:(NSString *)newServer
{
	[self willChangeValueForKey:@"server"];
	[_server release];
	_server = [newServer copy];	
	[self didChangeValueForKey:@"server"];
	
	return [self _modifyAttributeWithTag:kSecServerItemAttr toBeString:newServer];
}

- (NSString *)path { return _path; }

- (BOOL)setPath:(NSString *)newPath
{
	[self willChangeValueForKey:@"path"];
	[_path release];
	_path = [newPath copy];
	[self didChangeValueForKey:@"path"];
	
	return [self _modifyAttributeWithTag:kSecPathItemAttr toBeString:newPath];
}

- (NSInteger)port { return _port; }

- (BOOL)setPort:(NSInteger)newPort
{
	[self willChangeValueForKey:@"port"];
	_port = newPort;
	[self didChangeValueForKey:@"port"];
	
	return [self _modifyAttributeWithTag:kSecPortItemAttr toBeString:[NSString stringWithFormat:@"%i", newPort]];
}

- (SecProtocolType)protocol { return _protocol; }

- (BOOL)setProtocol:(SecProtocolType)newProtocol
{
	[self willChangeValueForKey:@"protocol"];
	_protocol = newProtocol;
	[self didChangeValueForKey:@"protocol"];
	
	SecKeychainAttribute attributes[1];
	attributes[0].tag = kSecProtocolItemAttr;
	attributes[0].length = sizeof(newProtocol);
	attributes[0].data = (void *)newProtocol;
	
	SecKeychainAttributeList list;
	list.count = 1;
	list.attr = attributes;
	
	OSStatus returnStatus = SecKeychainItemModifyAttributesAndData(coreKeychainItem, &list, 0, NULL);
	return (returnStatus == noErr);
}
@end
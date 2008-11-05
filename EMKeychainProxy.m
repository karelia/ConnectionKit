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

#import "EMKeychainProxy.h"

@implementation EMKeychainProxy

static EMKeychainProxy *sharedProxy = nil;

#pragma mark -
#pragma mark Shared Singleton
+ (id)sharedProxy
{
	if (!sharedProxy)
		[[EMKeychainProxy alloc] init];
	return sharedProxy;
}

+ (id)allocWithZone:(NSZone *)zone
{
	if (!sharedProxy)
	{
		sharedProxy = [super allocWithZone:zone];
		return sharedProxy;
	}
	return nil;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (id)retain
{
    return self;
}

- (unsigned)retainCount
{
    return UINT_MAX;  //denotes an object that cannot be released
}

- (void)release
{
    //do nothing
}

- (id)autorelease
{
    return self;
}

#pragma mark -
#pragma mark Accessors

- (BOOL)logsErrors { return _logErrors; }

- (void)setLogsErrors:(BOOL)flag { _logErrors = flag; }

#pragma mark -
#pragma mark Getting Keychain Items
- (EMGenericKeychainItem *)genericKeychainItemForService:(NSString *)serviceNameString 
											withUsername:(NSString *)usernameString
{
	if (!usernameString || [usernameString length] == 0)
		return nil;
	
	const char *serviceName = [serviceNameString UTF8String];
	const char *username = [usernameString UTF8String];
	
	UInt32 passwordLength = 0;
	char *password = nil;
	
	SecKeychainItemRef item = nil;
	OSStatus returnStatus = SecKeychainFindGenericPassword(NULL, strlen(serviceName), serviceName, strlen(username), username, &passwordLength, (void **)&password, &item);
	if (returnStatus != noErr || !item)
	{
		if (_logErrors)
		{
			NSLog(@"Error (%@) - %s", NSStringFromSelector(_cmd), GetMacOSStatusErrorString(returnStatus));
		}
		return nil;
	}
	NSString *passwordString = [NSString stringWithCString:password length:passwordLength];
	SecKeychainItemFreeContent(NULL, password);

	return [EMGenericKeychainItem genericKeychainItem:item forServiceName:serviceNameString username:usernameString password:passwordString];
}

- (EMInternetKeychainItem *)internetKeychainItemForServer:(NSString *)serverString
											 withUsername:(NSString *)usernameString
													 path:(NSString *)pathString
													 port:(NSInteger)port
												 protocol:(SecProtocolType)protocol
{
	if (!usernameString || [usernameString length] == 0 || !serverString || [serverString length] == 0)
		return nil;
	const char *server = [serverString UTF8String];
	const char *username = [usernameString UTF8String];
	const char *path = [pathString UTF8String];
	
	if (!pathString || [pathString length] == 0)
	{
		path = "";
	}
	
	UInt32 passwordLength = 0;
	char *password = nil;
	
	SecKeychainItemRef item = nil;
	//0 is kSecAuthenticationTypeAny
	OSStatus returnStatus = SecKeychainFindInternetPassword(NULL, strlen(server), server, 0, NULL, strlen(username), username, strlen(path), path, port, protocol, 0, &passwordLength, (void **)&password, &item);
	
	if (returnStatus != noErr && protocol == kSecProtocolTypeFTP)
	{
		//Some clients (like Transmit) still save passwords with kSecProtocolTypeFTPAccount, which was deprecated.  Let's check for that.
		protocol = kSecProtocolTypeFTPAccount;		
		returnStatus = SecKeychainFindInternetPassword(NULL, strlen(server), server, 0, NULL, strlen(username), username, strlen(path), path, port, protocol, 0, &passwordLength, (void **)&password, &item);
	}
	
	if (returnStatus != noErr || !item)
	{
		if (_logErrors)
		{
			NSLog(@"Error (%@) - %s", NSStringFromSelector(_cmd), GetMacOSStatusErrorString(returnStatus));
		}
		return nil;
	}
	NSString *passwordString = [NSString stringWithCString:password length:passwordLength];
	SecKeychainItemFreeContent(NULL, password);
	
	return [EMInternetKeychainItem internetKeychainItem:item forServer:serverString username:usernameString password:passwordString path:pathString port:port protocol:protocol];
}

#pragma mark -
#pragma mark Saving Passwords
- (EMGenericKeychainItem *)addGenericKeychainItemForService:(NSString *)serviceNameString
											   withUsername:(NSString *)usernameString
												   password:(NSString *)passwordString
{
	if (!usernameString || [usernameString length] == 0 || !serviceNameString || [serviceNameString length] == 0)
		return nil;
	const char *serviceName = [serviceNameString UTF8String];
	const char *username = [usernameString UTF8String];
	const char *password = [passwordString UTF8String];
	
	SecKeychainItemRef item = nil;
	OSStatus returnStatus = SecKeychainAddGenericPassword(NULL, strlen(serviceName), serviceName, strlen(username), username, strlen(password), (void *)password, &item);
	
	if (returnStatus != noErr || !item)
	{
		NSLog(@"Error (%@) - %s", NSStringFromSelector(_cmd), GetMacOSStatusErrorString(returnStatus));
		return nil;
	}
	return [EMGenericKeychainItem genericKeychainItem:item forServiceName:serviceNameString username:usernameString password:passwordString];
}

- (EMInternetKeychainItem *)addInternetKeychainItemForServer:(NSString *)serverString
												withUsername:(NSString *)usernameString
													password:(NSString *)passwordString
														path:(NSString *)pathString
														port:(NSInteger)port
													protocol:(SecProtocolType)protocol
{
	if (!usernameString || [usernameString length] == 0 || !serverString || [serverString length] == 0 || !passwordString || [passwordString length] == 0)
		return nil;
	const char *server = [serverString UTF8String];
	const char *username = [usernameString UTF8String];
	const char *password = [passwordString UTF8String];
	const char *path = [pathString UTF8String];
	
	if (!pathString || [pathString length] == 0)
	{
		path = "";
	}

	SecKeychainItemRef item = nil;
	OSStatus returnStatus = SecKeychainAddInternetPassword(NULL, strlen(server), server, 0, NULL, strlen(username), username, strlen(path), path, port, protocol, kSecAuthenticationTypeDefault, strlen(password), (void *)password, &item);
	
	if (returnStatus != noErr || !item)
	{
		NSLog(@"Error (%@) - %s", NSStringFromSelector(_cmd), GetMacOSStatusErrorString(returnStatus));
		return nil;
	}
	return [EMInternetKeychainItem internetKeychainItem:item forServer:serverString username:usernameString password:passwordString path:pathString port:port protocol:protocol];
}

#pragma mark -
#pragma mark Misc
- (void)lockKeychain
{
	SecKeychainLock(NULL);
}

- (void)unlockKeychain
{
	SecKeychainUnlock(NULL, 0, NULL, NO);
}

@end
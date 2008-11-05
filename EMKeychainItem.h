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


#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <Security/Security.h>

@interface EMKeychainItem : NSObject 
{
	NSString *_password;
	NSString *_username;
	NSString *_label;
	SecKeychainItemRef coreKeychainItem;
}

- (NSString *)password;
- (NSString *)username;
- (NSString *)label;

- (BOOL)setPassword:(NSString *)newPasswordString;
- (BOOL)setUsername:(NSString *)newUsername;

@end 

@interface EMGenericKeychainItem : EMKeychainItem
{
	NSString *_serviceName;
}

- (NSString *)serviceName;

+ (id)genericKeychainItem:(SecKeychainItemRef)item 
		   forServiceName:(NSString *)serviceName
				 username:(NSString *)username
				 password:(NSString *)password;
- (BOOL)setServiceName:(NSString *)newServiceName;
@end

@interface EMInternetKeychainItem : EMKeychainItem
{
	NSString *_server;
	NSString *_path;
	NSInteger _port;
	SecProtocolType _protocol;
}


+ (id)internetKeychainItem:(SecKeychainItemRef)item
				 forServer:(NSString *)server
				  username:(NSString *)username
				  password:(NSString *)password
					  path:(NSString *)path
					  port:(NSInteger)port
				  protocol:(SecProtocolType)protocol;

- (NSString *)server;
- (BOOL)setServer:(NSString *)newServer;

- (NSString *)path;
- (BOOL)setPath:(NSString *)newPath;

- (NSInteger)port;
- (BOOL)setPort:(NSInteger)newPort;

- (SecProtocolType)protocol;
- (BOOL)setProtocol:(SecProtocolType)newProtocol;
@end
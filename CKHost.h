//
//  CKHost.h
//  Connection
//
//  Created by Greg Hulands on 26/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol AbstractConnectionProtocol;
@class CKHostCategory;

@interface CKHost : NSObject <NSCoding>
{
	NSString	*myHost;
	NSString	*myPort;
	NSString	*myUsername;
	NSString	*myPassword;
	NSString	*myConnectionType;
	NSString	*myInitialPath;
	NSURL		*myURL;
	NSString	*myDescription;
	NSImage		*myIcon;
	
	id			myUserInfo;
	
	CKHostCategory *myCategory; // not retained
}

- (id)init;

- (void)setHost:(NSString *)host;
- (void)setPort:(NSString *)port;
- (void)setUsername:(NSString *)username;
- (void)setPassword:(NSString *)password;
- (void)setConnectionType:(NSString *)type;
- (void)setInitialPath:(NSString *)path;
- (void)setURL:(NSURL *)url;
- (void)setAnnotation:(NSString *)description;
- (void)setUserInfo:(id)ui;
- (void)setIcon:(NSImage *)icon;

- (NSString *)host;
- (NSString *)port;
- (NSString *)username;
- (NSString *)password;
- (NSString *)connectionType;
- (NSString *)initialPath;
- (NSURL *)url;
- (NSString *)annotation;
- (id)userInfo;
- (NSImage *)icon;

- (void)setCategory:(CKHostCategory *)cat;
- (CKHostCategory *)category;

// returns a new autoreleased connection of this type;
- (id <AbstractConnectionProtocol>)connection; 

- (NSString *)createDropletAtPath:(NSString *)path;

@end

extern NSString *CKHostChanged;

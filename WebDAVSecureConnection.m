//
//  WebDAVSecureConnection.m
//  FTPConnection
//
//  Created by Greg Hulands on 16/08/05.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "WebDAVSecureConnection.h"


@implementation WebDAVSecureConnection

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"443", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"https://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[WebDAVSecureConnection class] forTypes:[NSArray arrayWithObjects:port, url, nil]];
	[pool release];
}

+ (NSString *)name
{
	return @"WebDAV HTTPS";
}

@end

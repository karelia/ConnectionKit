//
//  WebDAVConnectionTest.m
//  Connection
//
//  Created by Greg Hulands on 1/05/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "WebDAVConnectionTest.h"


@implementation WebDAVConnectionTest

- (NSString *)connectionName
{
	return @"WebDAV";
}

- (NSString *)host
{
	return @"shrimpondabarbie.karelia.com";
}

- (NSString *)port
{
	return nil;
}

- (NSString *)username
{
	return @"paul";
}

- (void) setUp
{
	[super setUp];
	
	[initialDirectory release];
	initialDirectory = [[NSString stringWithString:@"/"] retain];
	[fileNameExistingOnServer release];
	fileNameExistingOnServer = [[NSString alloc] initWithString:@"/webdav/1.jpg"];
}
	
- (void) testConnectWithBadUserName
{	
}

- (void) testGetSetPermission
{	
}

@end

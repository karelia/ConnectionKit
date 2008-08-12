//
//  DotMacConnectionTest.m
//  Connection
//
//  Created by Greg Hulands on 1/05/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "DotMacConnectionTest.h"


@implementation DotMacConnectionTest

- (NSString *)connectionName
{
	return @"MobileMe";
}

- (void) setUp
{
	[super setUp];
	
	[initialDirectory release];
	initialDirectory = [[NSString stringWithString:@"/"] retain];
	[fileNameExistingOnServer release];
	fileNameExistingOnServer = [[NSString alloc] initWithString:@"/Software/Apple Software/iDisk Utility/iDisk_Utility.dmg"];
}

- (void) testConnectWithBadUserName
{	
}

@end

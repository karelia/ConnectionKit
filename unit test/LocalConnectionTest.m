//
//  LocalConnectionTest.m
//  Connection
//
//  Created by olivier on 4/24/06.
//  Copyright 2006 Olivier Destrebecq. All rights reserved.
//

#import "LocalConnectionTest.h"


@implementation fileConnectionTest
- (void) setUp
{
  
  connectionName = @"File";
  
  //set info for your ftp server here
  //
	initialDirectory = NSHomeDirectory();
	NSError *err = nil;
	connection = [[AbstractConnection connectionWithName: connectionName
													host: host
													port: port
												username: username
												password: password
												   error:&err] retain];
	if (!connection)
	{
		if (err)
		{
			NSLog(@"%@", err);
		}
	}
	
  [connection setDelegate: self];
  
  didUpload = isConnected = receivedError = NO;
}

- (void) testConnectWithBadHost
{
  //NA
}

- (void) testConnectWithBadUserName
{
  //NA
}

- (void) testConnectWithBadpassword
{
  //NA
}
@end

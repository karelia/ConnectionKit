//
//  FTPtest.m
//  Connection
//
//  Created by olivier on 4/27/06.
//  Copyright 2006 Olivier Destrebecq. All rights reserved.
//

#import "FTPtest.h"


@implementation FTPtest


- (void) setUp
{
  
	connectionName = @"FTP";
	
	//set info for your ftp server here
	//
	host = @"localhost";
	port = @"21";
	username = NSUserName();
	password = [AbstractConnectionTest keychainPasswordForServer:host account:username];
  
  fileNameExistingOnServer = @"presentation.ppt"; 
	
	initialDirectory = NSHomeDirectory();
	NSError *err = nil;
	connection = [[AbstractConnection connectionWithName: connectionName
                                                  host: host
                                                  port: port
                                              username: username
                                              password: password
                                                 error: &err] retain];
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

@end

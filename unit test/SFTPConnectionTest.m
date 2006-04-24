//
//  SFTPConnectionTest.m
//  Connection
//
//  Created by olivier on 4/23/06.
//  Copyright 2006 Olivier Destrebecq. All rights reserved.
//

#import "SFTPConnectionTest.h"


@implementation SFTPConnectionTest
- (void) setUp
{
  
  connectionName = @"SFTP";
  
  //set info for your ftp server here
  //
  username = @"olivier";
  password = @"xxxxx";   
  port = @"22";
  host = @"localhost";
  localPath = @"/Users/olivier";
  connection = [[AbstractQueueConnection connectionWithName: connectionName
                                                       host: host
                                                       port: port
                                                   username: username
                                                   password: password] retain];
  [connection setDelegate: self];
  
  didUpload = isConnected = receivedError = NO;
}
@end

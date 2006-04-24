//
//  AbstractConnectionTest.h
//  Connection
//
//  Created by olivier on 4/23/06.
//  Copyright 2006 Olivier Destrebecq. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import <Connection/Connection.h>

#define ___SOURCEROOT___ @"/Users/olivier/Documents/Projects/source/connection-svn/trunk/unit test/"
@interface FTPConnectionTest : SenTestCase {
  AbstractQueueConnection *connection;
  NSString *connectionName;
  NSString *username;
  NSString *password;
  NSString *port;
  NSString *host;
  NSString *initialDirectory;
  
  NSString *localPath;
  
  BOOL isConnected;
  BOOL receivedError;
  BOOL didUpload;
}

@end

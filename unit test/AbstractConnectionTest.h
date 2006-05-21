//
//  AbstractConnectionTest.h
//  Connection
//
//  Created by olivier on 4/23/06.
//  Copyright 2006 Olivier Destrebecq. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import <Connection/Connection.h>

@interface AbstractConnectionTest : SenTestCase {
  id <AbstractConnectionProtocol> connection;
  NSString *initialDirectory;
  NSString *fileNameExistingOnServer;       //used to check that checkForFileExistance calls work, this file has to already exist on the server
  NSString* existingFolder;
  
  BOOL isConnected;
  BOOL receivedError;
  BOOL didUpload;
  BOOL didDelete;
  BOOL fileExists;
  BOOL returnedFromFileExists;
  BOOL didSetPermission;
  BOOL didChangeDirectory;
  BOOL didDownload;
  NSString *remoteDownloadedPath;
  
  NSArray *directoryContents;
}
 
+ (NSString *)keychainPasswordForServer:(NSString *)aServerName account:(NSString *)anAccountName;


- (NSString *)connectionName;
- (NSString *)host;
- (NSString *)port;
- (NSString *)username;
- (NSString *)password;

@end

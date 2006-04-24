//
//  AbstractConnectionTest.m
//  Connection
//
//  Created by olivier on 4/23/06.
//  Copyright 2006 Olivier Destrebecq. All rights reserved.
//

#import "AbstractConnectionTest.h"


@implementation FTPConnectionTest

- (void) setUp
{
  
  connectionName = @"FTP";
  
  //set info for your ftp server here
  //
  username = @"olivier";
  password = @"xxxxxx";   
  port = @"21";
  host = @"localhost";
  localPath = @"/Users/olivier/";
  initialDirectory = @"/Users/olivier";
  connection = [[AbstractQueueConnection connectionWithName: connectionName
                                                       host: host
                                                       port: port
                                                   username: username
                                                   password: password] retain];
  [connection setDelegate: self];
  
  didUpload = isConnected = receivedError = NO;
}

- (void) testUpload
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  [connection uploadFile: [___SOURCEROOT___ stringByAppendingPathComponent: @"AbstractConnectionTest.h"]];
  
  didUpload = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didUpload) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse(receivedError, @"received error on upload");
  STAssertTrue(([initialTime timeIntervalSinceNow] > -15), @"timeout on upload");
  STAssertTrue([[NSFileManager defaultManager] fileExistsAtPath: [localPath stringByAppendingPathComponent: @"AbstractConnectionTest.h"]], @"did not upload file");
  
  //clean up
  [[NSFileManager defaultManager] removeFileAtPath: [localPath stringByAppendingPathComponent: @"AbstractConnectionTest.h"]
                                           handler: nil];
}

- (void) testUploadToFile
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  [connection uploadFile: [___SOURCEROOT___ stringByAppendingPathComponent: @"AbstractConnectionTest.h"] toFile:  @"AbstractConnectionTest.h"];
  
  didUpload = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didUpload) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse(receivedError, @"received error on upload");
  STAssertTrue(([initialTime timeIntervalSinceNow] > -15), @"timeout on upload");
  STAssertTrue([[NSFileManager defaultManager] fileExistsAtPath: [localPath stringByAppendingPathComponent: @"AbstractConnectionTest.h"]], @"did not upload file");
  
  //clean up
  [[NSFileManager defaultManager] removeFileAtPath: [localPath stringByAppendingPathComponent: @"AbstractConnectionTest.h"]
                                           handler: nil];
}

- (void) testUploadMultipleFiles
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  [connection uploadFile: [___SOURCEROOT___ stringByAppendingPathComponent: @"AbstractConnectionTest.h"] toFile:  @"AbstractConnectionTest.h"];
  [connection uploadFile: [___SOURCEROOT___ stringByAppendingPathComponent: @"AbstractConnectionTest.m"] toFile:  @"AbstractConnectionTest.m"];
  
  didUpload = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didUpload) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse(receivedError, @"received error on upload");
  STAssertTrue(([initialTime timeIntervalSinceNow] > -15), @"timeout on upload");
  STAssertTrue([[NSFileManager defaultManager] fileExistsAtPath: [localPath stringByAppendingPathComponent: @"AbstractConnectionTest.h"]], @"did not upload file");
  STAssertTrue([[NSFileManager defaultManager] fileExistsAtPath: [localPath stringByAppendingPathComponent: @"AbstractConnectionTest.m"]], @"did not upload file");
  
  //clean up
  [[NSFileManager defaultManager] removeFileAtPath: [localPath stringByAppendingPathComponent: @"AbstractConnectionTest.h"]
                                           handler: nil];
  [[NSFileManager defaultManager] removeFileAtPath: [localPath stringByAppendingPathComponent: @"AbstractConnectionTest.m"]
                                           handler: nil];
}

- (void) testConnect
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertTrue(([initialTime timeIntervalSinceNow] > -15), @"timed out on connection");
  STAssertTrue([connection isConnected], @"did not connect");
  STAssertFalse(receivedError, @"error while connecting");
  STAssertEqualObjects(initialDirectory, [connection currentDirectory], @"invalid current directory");
}

- (void) testDisconnect
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  [connection disconnect];
  initialTime = [NSDate date];
  while (([connection isConnected])  && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];

  
  STAssertTrue(([initialTime timeIntervalSinceNow] > -15), @"timed out on deconnection");
  STAssertFalse([connection isConnected], @"did not disconnect");
}

- (void) testConnectWithBadUserName
{
  [connection setUsername: @""];
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertTrue([initialTime timeIntervalSinceNow] > -15, @"timed out on connection");
  STAssertFalse([connection isConnected], @"did not connect");
  STAssertTrue(receivedError, @"error while connecting");
}

- (void) testConnectWithBadpassword
{
  [connection setPassword: @""];
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertTrue([initialTime timeIntervalSinceNow] > -15, @"timed out on connection");
  STAssertFalse([connection isConnected], @"did not connect");
  STAssertTrue(receivedError, @"error while connecting");
}

- (void) testConnectWithBadHost
{
  [connection setHost: @"asdfdsf"];
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -30))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertTrue([initialTime timeIntervalSinceNow] > -30, @"timed out on connection");
  STAssertFalse([connection isConnected], @"connected");
  STAssertTrue(receivedError, @"error while connecting");
}

- (void)connection:(id <AbstractConnectionProtocol>)con didConnectToHost:(NSString *)host
{
  isConnected = YES;
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host
{
  receivedError = YES;
}

- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveError:(NSError *)error
{
  NSLog (@"%@", error);
  receivedError = YES;
}

- (void)connectionDidSendBadPassword:(id <AbstractConnectionProtocol>)con
{
  receivedError = YES;
}


- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidFinish:(NSString *)remotePath
{
  if (![con numberOfTransfers])
    didUpload = YES;
}
@end

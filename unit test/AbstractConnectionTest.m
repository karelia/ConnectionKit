//
//  AbstractConnectionTest.m
//  Connection
//
//  Created by olivier on 4/23/06.
//  Copyright 2006 Olivier Destrebecq. All rights reserved.
//

#import "AbstractConnectionTest.h"


@implementation FTPConnectionTest

+ (NSString *)keychainPasswordForServer:(NSString *)aServerName account:(NSString *)anAccountName
{
	NSString *result = nil;
	if ([aServerName length] > 255 || [anAccountName length] > 255)
	{
		return result;
	}
	
	Str255 serverPString, accountPString;
	
	c2pstrcpy(serverPString, [aServerName UTF8String]);
	c2pstrcpy(accountPString, [anAccountName UTF8String]);
	
	char passwordBuffer[256];
	UInt32 actualLength;
	OSStatus theStatus;
	
	theStatus = KCFindInternetPassword (
                                      serverPString,			// StringPtr serverName,
                                      NULL,					// StringPtr securityDomain,
                                      accountPString,		// StringPtr accountName,
                                      kAnyPort,				// UInt16 port,
                                      kAnyProtocol,			// OSType protocol,
                                      kAnyAuthType,			// OSType authType,
                                      255,					// UInt32 maxLength,
                                      passwordBuffer,		// void * passwordData,
                                      &actualLength,			// UInt32 * actualLength,
                                      nil					// KCItemRef * item
                                      );
	if (noErr == theStatus)
	{
		passwordBuffer[actualLength] = 0;		// make it a legal C string by appending 0
		result = [NSString stringWithUTF8String:passwordBuffer];
	}
	return result;
}

- (void) setUp
{
	connectionName = @"FTP";
	
	//set info for your ftp server here
	//
	host = @"localhost";
	port = @"21";
	username = NSUserName();
	password = [FTPConnectionTest keychainPasswordForServer:host account:username];
	
	localPath = NSHomeDirectory();
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

- (void) testUpload
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  [connection uploadFile: [[env objectForKey:@"SRCROOT"] stringByAppendingPathComponent: @"unit test/AbstractConnectionTest.h"]];
  
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

- (void) testUploadToFileAndDelete
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  [connection uploadFile: [[env objectForKey:@"SRCROOT"] stringByAppendingPathComponent: @"unit test/AbstractConnectionTest.h"] toFile:  @"AbstractConnectionTest.h"];
  
  didUpload = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didUpload) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse(receivedError, @"received error on upload");
  STAssertTrue(([initialTime timeIntervalSinceNow] > -15), @"timeout on upload");
  STAssertTrue([[NSFileManager defaultManager] fileExistsAtPath: [localPath stringByAppendingPathComponent: @"AbstractConnectionTest.h"]], @"did not upload file");
  
  //clean up
  //
  [connection deleteFile: @"AbstractConnectionTest.h"];
  
  didDelete = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didDelete) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];

  STAssertFalse([[NSFileManager defaultManager] fileExistsAtPath: [localPath stringByAppendingPathComponent: @"AbstractConnectionTest.h"]], @"did not delete the file");

  //enforce clean up
  //
  [[NSFileManager defaultManager] removeFileAtPath: [localPath stringByAppendingPathComponent: @"AbstractConnectionTest.h"]
                                           handler: nil];
}

- (void) testUploadMultipleFiles
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  [connection uploadFile: [[env objectForKey:@"SRCROOT"] stringByAppendingPathComponent: @"unit test/AbstractConnectionTest.h"] toFile:  @"AbstractConnectionTest.h"];
  [connection uploadFile: [[env objectForKey:@"SRCROOT"] stringByAppendingPathComponent: @"unit test/AbstractConnectionTest.m"] toFile:  @"AbstractConnectionTest.m"];
  
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
  NSLog (@"%@\n%@", NSStringFromSelector(_cmd), error);
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


- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteFile:(NSString *)path
{
  didDelete = YES;
}
@end

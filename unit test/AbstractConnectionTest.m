//
//  AbstractConnectionTest.m
//  Connection
//
//  Created by olivier on 4/23/06.
//  Copyright 2006 Olivier Destrebecq. All rights reserved.
//

#import "AbstractConnectionTest.h"
 

@implementation AbstractConnectionTest
- (unsigned int)testCaseCount {
  unsigned int count = 0;
  
  if ([self isMemberOfClass:[AbstractConnectionTest class]] == NO) {
    count = [super testCaseCount];
  }
  
  return count;
}

- (void)performTest:(SenTestRun *)testRun {
  if ([self isMemberOfClass: [AbstractConnectionTest class]] == NO) 
  {
    [super performTest:testRun];
  }
}

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

- (void) testFileExitence
{
  [self checkThatFileExistsAtPath: fileNameExistingOnServer];  
}

- (void) testFileNonExistence
{
  [self checkThatFileDoesNotExistsAtPath: @"Windows95 was the best OS ever"];
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
  
  //check that the file exists (using the connectino framework, so maybe not the best check, but at least will work with every connection
  //
  [self checkThatFileExistsAtPath: @"AbstractConnectionTest.h"];
  
  //clean up
  //
  [connection deleteFile: @"AbstractConnectionTest.h"];
  
  didDelete = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didDelete) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  //check that the file was removed
  //
  [self checkThatFileDoesNotExistsAtPath: @"AbstractConnectionTest.h"];
  
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
  
  //check that the file exists (using the connectino framework, so maybe not the best check, but at least will work with every connection
  //
  [self checkThatFileExistsAtPath: @"AbstractConnectionTest.h"];
  
  //clean up
  //
  [connection deleteFile: @"AbstractConnectionTest.h"];
  
  didDelete = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didDelete) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];

  //Check that the file was removed
  //
  [self checkThatFileDoesNotExistsAtPath: @"AbstractConnectionTest.h"];
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
  
  [self checkThatFileExistsAtPath: @"AbstractConnectionTest.h"];
  [self checkThatFileExistsAtPath: @"AbstractConnectionTest.m"];
  
  //clean up
  [connection deleteFile: @"AbstractConnectionTest.h"];
  
  didDelete = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didDelete) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  [connection deleteFile: @"AbstractConnectionTest.m"];
  
  didDelete = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didDelete) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  [self checkThatFileDoesNotExistsAtPath: @"AbstractConnectionTest.h"];
  [self checkThatFileDoesNotExistsAtPath: @"AbstractConnectionTest.m"];
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

- (void)connection:(id <AbstractConnectionProtocol>)con checkedExistenceOfPath:(NSString *)path pathExists:(BOOL)exists
{
  fileExists = exists;
  returnedFromFileExists = YES;
}

- (void) checkThatFileExistsAtPath: (NSString*) inPath
{
  //check that the file was removed
  //
  [connection checkExistenceOfPath: inPath];
  
  fileExists = returnedFromFileExists = receivedError = NO;
  NSDate *initialTime = [NSDate date];
  while ((!returnedFromFileExists) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse(receivedError, @"did receive an error while checking for file existance");
  STAssertTrue(([initialTime timeIntervalSinceNow] > -15), @"timeout on check file existance");
  STAssertTrue(fileExists, @"file  does not exists");
}

- (void) checkThatFileDoesNotExistsAtPath: (NSString*) inPath
{
  //check that the file was removed
  //
  [connection checkExistenceOfPath: inPath];
  
  fileExists = returnedFromFileExists = receivedError = NO;
  NSDate *initialTime = [NSDate date];
  while ((!returnedFromFileExists) && (!receivedError) && ([initialTime timeIntervalSinceNow] > -15))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse(receivedError, @"did receive an error while checking for file existance");
  STAssertTrue(([initialTime timeIntervalSinceNow] > -15), @"timeout on check file existance");
  STAssertFalse(fileExists, @"file exists");
}
@end

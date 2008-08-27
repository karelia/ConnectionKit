//
//  AbstractConnectionTest.m
//  Connection
//
//  Created by olivier on 4/23/06.
//  Copyright 2006 Olivier Destrebecq. All rights reserved.
//

#import "AbstractConnectionTest.h"

const NSTimeInterval kTestTimeout = -15.0;
 
@interface AbstractConnectionTest (Private)

- (void) checkThatFileExistsAtPath: (NSString*) inPath;
- (void) checkThatFileDoesNotExistsAtPath: (NSString*) inPath;

@end

@implementation AbstractConnectionTest

- (NSString *)connectionName
{
	return @"AbstractConnection";
}

- (NSString *)host
{
	return @"localhost";
}

- (NSString *)port
{
	return nil;
}

- (NSString *)username
{
	return NSUserName();
}

- (NSString *)password
{
	return [AbstractConnectionTest keychainPasswordForServer:[self host] account:[self username]];
}

- (void) setUp
{
	//set info for your ftp server here
	//	
	NSDictionary *env = [[NSProcessInfo processInfo] environment];
	fileNameExistingOnServer = [[[env objectForKey:@"SRCROOT"] stringByAppendingPathComponent: [NSString stringWithString:@"unit test/09 moustik.mp3"]] retain];
	initialDirectory = [[NSString stringWithString:NSHomeDirectory()] retain];
  existingFolder = @"Sites";
	NSError *err = nil;
	connection = [[AbstractConnection connectionWithName: [self connectionName]
													host: [self host]
													port: [self port]
												username: [self username]
												password: [self password]
												   error: &err] retain];
	if (!connection)
	{
		if (err)
		{
			NSLog(@"%@: %@", NSStringFromSelector(_cmd), err);
		}
	}
	[connection setDelegate: self];
	didUpload = isConnected = receivedError = didSetPermission = didDelete = fileExists = returnedFromFileExists = NO;
	directoryContents = remoteDownloadedPath = nil;
}

- (void) tearDown
{
	[fileNameExistingOnServer release];
	[initialDirectory release];
	[directoryContents release];
	[connection setDelegate:nil];
	[connection release];
	connection = nil;
}

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
	NSDictionary *env = [[NSProcessInfo processInfo] environment];
	NSString *file = [[env objectForKey:@"SRCROOT"] stringByAppendingPathComponent: @"Windows95 was the best OS ever.txt"];
	[self checkThatFileDoesNotExistsAtPath:file];
}

- (void) testGetSetPermission
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertTrue([connection isConnected], @"Connection didn't connect");
  //get the directory content to save the permission
  //
  receivedError = NO;  
  NSString *file = fileNameExistingOnServer;
  NSString *dir = [file stringByDeletingLastPathComponent];
  [connection contentsOfDirectory:dir];
  
  initialTime = [NSDate date];
  while ((!directoryContents) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse (receivedError, @"received error on get directory content");
  STAssertTrue(([initialTime timeIntervalSinceNow] > kTestTimeout), @"timed out on directory content");
  STAssertNotNil (directoryContents, @"did not receive directory content");
  
  NSEnumerator *theDirectoryEnum = [directoryContents objectEnumerator];
  NSDictionary *currentFile;
  unsigned long savedPermission = 0644;
  BOOL didFindFile = NO;
  while (currentFile = [theDirectoryEnum nextObject])
  {
    if ([[currentFile objectForKey: @"cxFilenameKey"] isEqualToString: [file lastPathComponent]])
    {
		savedPermission = [[currentFile objectForKey: @"NSFilePosixPermissions"] unsignedLongValue];
		didFindFile = YES;
      break;
    }
  }
  STAssertTrue(didFindFile, @"Failed to find test file %@", [fileNameExistingOnServer lastPathComponent]);
  
  //now actually set the permission
  //
  receivedError = NO;
  [connection setPermissions:0660 forFile: file]; //read write by owner and group only
  
  
  initialTime = [NSDate date];
  while ((!didSetPermission) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse (receivedError, @"received error on set permission");
  STAssertTrue(([initialTime timeIntervalSinceNow] > kTestTimeout), @"timed out on set permission");
  STAssertTrue (didSetPermission, @"did not set the permission");
  
  //now check that the permission are set
  //
  receivedError = NO;  
  [directoryContents release];
  directoryContents = nil;
  [connection contentsOfDirectory:dir];
  
  initialTime = [NSDate date];
  while ((!directoryContents) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse (receivedError, @"received error on get directory content");
  STAssertTrue(([initialTime timeIntervalSinceNow] > kTestTimeout), @"timed out on directory content");
  STAssertNotNil (directoryContents, @"did not receive directory content");
  
  theDirectoryEnum = [directoryContents objectEnumerator];
  BOOL didCheckFile = NO;
  while (currentFile = [theDirectoryEnum nextObject])
  {
    if ([[currentFile objectForKey: @"cxFilenameKey"] isEqualToString: [fileNameExistingOnServer lastPathComponent]])
    {
		STAssertTrue(0660 == [[currentFile objectForKey:NSFilePosixPermissions] unsignedLongValue], @"did not set the remote permission");
		didCheckFile = YES;
		break;
    }
  }
  
  STAssertTrue(didCheckFile, @"Failed to check file permissions for file");
  
  //set the permission back, don't care about the result that much
  //
  receivedError = NO;
  [connection setPermissions: savedPermission forFile: file]; //read write by owner only
  
  
  initialTime = [NSDate date];
  while ((!didSetPermission) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
}

- (void) testUpload
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  [connection uploadFile: fileNameExistingOnServer];
  
  didUpload = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didUpload) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse(receivedError, @"received error on upload");
  STAssertTrue(([initialTime timeIntervalSinceNow] > kTestTimeout), @"timeout on upload");
  STAssertEqualObjects(remoteDownloadedPath, [initialDirectory stringByAppendingPathComponent: [fileNameExistingOnServer lastPathComponent]], @"did not absolute full path");
  //check that the file exists (using the connectino framework, so maybe not the best check, but at least will work with every connection
  //
  NSString *dir = [connection currentDirectory];
  [self checkThatFileExistsAtPath: [dir stringByAppendingPathComponent:[fileNameExistingOnServer lastPathComponent]]];
  
  //clean up
  //
  [connection deleteFile: [dir stringByAppendingPathComponent:[fileNameExistingOnServer lastPathComponent]]];
  
  didDelete = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didDelete) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  //check that the file was removed
  //
  [self checkThatFileDoesNotExistsAtPath: [fileNameExistingOnServer lastPathComponent]];
  
}

- (void) testUploadToFileAndDelete
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];

  [connection uploadFile: fileNameExistingOnServer 
                  toFile:[fileNameExistingOnServer lastPathComponent]];
  
  didUpload = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didUpload) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse(receivedError, @"received error on upload");
  STAssertTrue(([initialTime timeIntervalSinceNow] > kTestTimeout), @"timeout on upload");
  
  //check that the file exists (using the connectino framework, so maybe not the best check, but at least will work with every connection
  //
  [self checkThatFileExistsAtPath: [fileNameExistingOnServer lastPathComponent]];
  
  //clean up
  //
  [connection deleteFile: [fileNameExistingOnServer lastPathComponent]];
  
  didDelete = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didDelete) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];

  //Check that the file was removed
  //
  [self checkThatFileDoesNotExistsAtPath: [fileNameExistingOnServer lastPathComponent]];
}

- (void) testUploadInvalidPath
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  [connection uploadFile: [[env objectForKey:@"SRCROOT"] stringByAppendingPathComponent: @"my super duper missing file"]];

  didUpload = receivedError = NO;
  initialTime = [NSDate date];
  while ((!didUpload) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertTrue(receivedError, @"received error on upload");
  STAssertTrue(([initialTime timeIntervalSinceNow] > kTestTimeout), @"timeout on upload");
}

- (void) testConnect
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertTrue(([initialTime timeIntervalSinceNow] > kTestTimeout), @"timed out on connection");
  STAssertTrue([connection isConnected], @"did not connect");
  STAssertFalse(receivedError, @"error while connecting");
  STAssertEqualObjects(initialDirectory, [connection currentDirectory], @"invalid current directory");
}

- (void) testChangeRelativeDirectory
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  [connection changeToDirectory: existingFolder];
  initialTime = [NSDate date];
  while ((!didChangeDirectory) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertEqualObjects([initialDirectory stringByAppendingPathComponent: existingFolder], [connection currentDirectory], @"did not change directory");
}

- (void) testDisconnect
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  [connection disconnect];
  initialTime = [NSDate date];
  while (isConnected  && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  
  STAssertTrue(([initialTime timeIntervalSinceNow] > kTestTimeout), @"timed out on disconnection");
  STAssertFalse(isConnected, @"did not disconnect");
}

- (void) testConnectWithBadUserName
{
  [connection setUsername: @""];
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertTrue([initialTime timeIntervalSinceNow] > kTestTimeout, @"timed out on connection");
  STAssertFalse([connection isConnected], @"did not connect");
  STAssertTrue(receivedError, @"error while connecting");
}

- (void) testConnectWithBadpassword
{
  [connection setPassword: @"mbnv"];
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertTrue([initialTime timeIntervalSinceNow] > kTestTimeout, @"timed out on connection");
  STAssertFalse([connection isConnected], @"did connect");
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

- (void) testDownload
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  //download a file
  //
  receivedError = NO;
  [connection downloadFile: fileNameExistingOnServer
               toDirectory: NSTemporaryDirectory()
                 overwrite: YES];
  
  initialTime = [NSDate date];
  while ((!didDownload) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  
  STAssertTrue([initialTime timeIntervalSinceNow] > kTestTimeout, @"timed out on download");
  STAssertFalse(receivedError, @"error while downloading");
  STAssertEqualObjects(remoteDownloadedPath, fileNameExistingOnServer, @"did not return an absolute path");
  STAssertTrue([[NSFileManager defaultManager] fileExistsAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: [fileNameExistingOnServer lastPathComponent]]], @"did not download file");
  
  //clean up
  [[NSFileManager defaultManager] removeFileAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: [fileNameExistingOnServer lastPathComponent]]
                                           handler: nil];
}

- (void) testDownloadOverwrite
{
  [connection connect];
  
  NSDate *initialTime = [NSDate date];
  while ((!isConnected) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  //download a file
  //
  receivedError = NO;
  [[NSDictionary dictionary] writeToFile: [NSTemporaryDirectory() stringByAppendingPathComponent: [fileNameExistingOnServer lastPathComponent]]
                              atomically: NO];
  [connection downloadFile: fileNameExistingOnServer
               toDirectory: NSTemporaryDirectory()
                 overwrite: YES];
  
  initialTime = [NSDate date];
  while ((!didDownload) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  
  STAssertTrue([initialTime timeIntervalSinceNow] > -30, @"timed out on download");
  STAssertFalse(receivedError, @"error while downloading");
  STAssertEqualObjects(remoteDownloadedPath, fileNameExistingOnServer, @"did not return an absolute path");
  STAssertTrue([[NSFileManager defaultManager] fileExistsAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: [fileNameExistingOnServer lastPathComponent]]], @"did not download file");
  
  //clean up
  [[NSFileManager defaultManager] removeFileAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: [fileNameExistingOnServer lastPathComponent]]
                                           handler: nil];
}

- (void)connection:(id <AbstractConnectionProtocol>)con downloadDidFinish:(NSString *)remotePath error:(NSError *)error
{
  remoteDownloadedPath = [remotePath retain];
  didDownload = YES;
}

- (void)connection:(id <AbstractConnectionProtocol>)con didConnectToHost:(NSString *)host
{
  isConnected = YES;
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host
{
	isConnected = NO;
}

- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveError:(NSError *)error
{
  //NSLog (@"%@\n%@", NSStringFromSelector(_cmd), error);
  NSLog (@"error: %@", error);
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
  remoteDownloadedPath = [remotePath retain];
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


- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath
{
	//NSLog(@"received contents: %@", dirPath);
	
  directoryContents = [contents retain];
}

- (void)connection:(id <AbstractConnectionProtocol>)con didSetPermissionsForFile:(NSString *)path
{
  didSetPermission = YES;
}

- (void)connection:(id <AbstractConnectionProtocol>)con didChangeToDirectory:(NSString *)dirPath
{
  didChangeDirectory = YES;
}

- (void) checkThatFileExistsAtPath: (NSString*) inPath
{
  //check that the file was removed
  //
	//NSLog(@"checking for file: %@", inPath);
  [connection checkExistenceOfPath: inPath];
  
  fileExists = returnedFromFileExists = receivedError = NO;
  NSDate *initialTime = [NSDate date];
  while ((!returnedFromFileExists) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse(receivedError, @"did receive an error while checking for file existence");
  STAssertTrue(([initialTime timeIntervalSinceNow] > kTestTimeout), @"timeout on check file existence");
  STAssertTrue(fileExists, @"file does not exist");
}

- (void) checkThatFileDoesNotExistsAtPath: (NSString*) inPath
{
  //check that the file was removed
  //
	//NSLog(@"checking file doesn't exist: %@", inPath);
  [connection checkExistenceOfPath: inPath];
  
  fileExists = returnedFromFileExists = receivedError = NO;
  NSDate *initialTime = [NSDate date];
  while ((!returnedFromFileExists) && (!receivedError) && ([initialTime timeIntervalSinceNow] > kTestTimeout))  //wait for connection or 30 sec
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  
  STAssertFalse(receivedError, @"did receive an error while checking for file non-existence");
  STAssertTrue(([initialTime timeIntervalSinceNow] > kTestTimeout), @"timeout on check file non-existence");
  STAssertFalse(fileExists, @"file exists");
}
@end

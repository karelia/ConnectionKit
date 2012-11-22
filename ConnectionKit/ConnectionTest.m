//
//  ConnectionTest.m
//  Marvel
//
//  Created by Dan Wood on 11/29/04.
//  Copyright (c) 2004 Biophony, LLC. All rights reserved.
//

#import "ConnectionTest.h"
#import "FTPConnection.h"
#import "FileConnection.h"

/* AVAILABLE MACROS

UKPass()						Pass always
UKFail()						Fail always
UKTrue(condition)				Pass if condition is true
UKFalse(condition)				Pass if condition is false
UKNil(ref)						Pass if ref is nil
UKNotNil(ref)					Pass if ref is not nil
UKIntsEqual(a, b)				Pass if a == b
UKIntsNotEqual(a, b)			Pass if a != b
UKFloatsEqual(a, b, d)			Pass if a == b
UKFloatsNotEqual(a, b, d)		Pass if a != b
UKObjectsEqual(a, b)			Pass if a isEqualTo: b
UKObjectsNotEqual(a, b)			Pass if NOT a isEqualTo: b
UKObjectsSame(a, b)				Pass if a (address) == b (address)
UKObjectsNotSame(a, b)			Pass if a (address) != b (address)
UKStringsEqual(a, b)			Pass if a isEqualToString: b
UKStringsNotEqual(a, b)			Pass if a NOT isEqualToString: b
UKStringContains(a, b)			Pass if a contains b
UKStringDoesNotContain(a, b)	Pass if a does NOT contain b
UKRaisesException(exp)			Pass if exp raises an exception
UKDoesNotRaiseException(exp)	Pass if exp does NOT raise an exception
UKRaisesExceptionNamed(exp, b)	Pass if exp raises an exception named b	
UKRaisesExceptionClass(exp, b)	Pass if exp does NOT raise an exception named b

*/

@implementation ConnectionTest

- (id)init
{
	if (self = [super init])
	{
		myUniqueNumber = (unsigned long) [NSDate timeIntervalSinceReferenceDate];
		[self setCallbackDictionary:[NSMutableDictionary dictionary]];
	}
	return self;
}

- (void)dealloc
{
	[self setCallbackDictionary:nil];
	[super dealloc];
}


- (NSString *)currentDirectory
{
    return myCurrentDirectory; 
}
- (void)setCurrentDirectory:(NSString *)aCurrentDirectory
{
    [aCurrentDirectory retain];
    [myCurrentDirectory release];
    myCurrentDirectory = aCurrentDirectory;
}


/*
 
 For all the connection methods, run a standard suite of tests.  Test the following methods:
 
 (Need to hook up a delegate to self, somehow put it into a state of what is expected, so we'll know if it's called.  If we expect it to be called and it's not, we can have it set an ivar and we'll check.)
 
 What will be tricky will be that this is async.  We may need to queue up a bunch of operations, and then wait somehow until they have completed.  Maybe make a runloop?
 
 
 Making connection
 
 changing to directory (good/bad)
 getting directory (as expected?)
 making directory (good/bad)
 making directory with certain permissions
 setting permissions (try a couple of times to make sure they actually change)  (success/fail)
 rename
 delete
 delete directory
 upload file (some known file, like /etc/hosts, or make a new /tmp file with UUID)
	.... to directory
 resume upload file at offset (supported for all?)
 download file
 resumeDownload file
 cancel transfer
 get directory contents
 
 */
#pragma mark -
#pragma mark Callbacks

/*!	These callbacks work by adding their method name to the dictionary so we can tell what has been run.
	Temporarily scrunched to one line per method, to make it easy to count and sort.

*/

- (void)connection:(id <AbstractConnectionProtocol>)con didChangeToDirectory:(NSString *)dirPath { [self setCurrentDirectory:dirPath]; NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:dirPath forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con didConnectToHost:(NSString *)host { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:host forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con didCreateDirectory:(NSString *)dirPath { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:dirPath forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteDirectory:(NSString *)dirPath { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:dirPath forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteFile:(NSString *)path { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:path forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:host forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:contents forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveError:(NSError *)error { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:error forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con didRename:(NSString *)fromPath to:(NSString *)toPath { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:[NSString stringWithFormat:@"%@ -> %@",fromPath,toPath]  forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con didSetPermissionsForFile:(NSString *)path { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:path forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con download:(NSString *)path progressedTo:(NSNumber *)percent { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:[NSString stringWithFormat:@"%@: %@%%",path,percent]  forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con download:(NSString *)path receivedDataOfLength:(int)length { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:[NSString stringWithFormat:@"%@: %d bytes",path,length]  forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con downloadDidBegin:(NSString *)remotePath { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:remotePath forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con downloadDidFinish:(NSString *)remotePath { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:remotePath forKey:NSStringFromSelector(_cmd)]; }
- (NSString *)connection:(id <AbstractConnectionProtocol>)con needsAccountForUsername:(NSString *)username { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:username forKey:NSStringFromSelector(_cmd)]; return @"foo"; }
- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath progressedTo:(NSNumber *)percent { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:[NSString stringWithFormat:@"%@: %@%%",remotePath,percent]  forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath sentDataOfLength:(int)length { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:[NSString stringWithFormat:@"%@: %d bytes",remotePath,length]  forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidBegin:(NSString *)remotePath { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:remotePath forKey:NSStringFromSelector(_cmd)]; }
- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidFinish:(NSString *)remotePath { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:remotePath forKey:NSStringFromSelector(_cmd)]; }
- (void)connectionDidCancelTransfer:(id <AbstractConnectionProtocol>)con { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:[NSNumber numberWithBool:YES] forKey:NSStringFromSelector(_cmd)]; }
- (void)connectionDidSendBadPassword:(id <AbstractConnectionProtocol>)con { NSLog(@"========= CALLBACK: %@", NSStringFromSelector(_cmd)); [myCallbackDictionary setObject:[NSNumber numberWithBool:YES] forKey:NSStringFromSelector(_cmd)]; }



#pragma mark -
#pragma mark Main Test Suite


/*!	Do a full test suite
*/
- (void)runTestSuiteWithConnection:(id <AbstractConnectionProtocol>)aConn expectingFailure:(BOOL) inExpectConnectionFailure
{
	
	[aConn setDelegate:self];
	
	BOOL done = NO;
	NSString *initialDirectory = nil;

	NSDate *dropDeadDate = [NSDate dateWithTimeIntervalSinceNow:120.0];

	[aConn connect];

	while (!done && NSOrderedAscending == [((NSDate *)[NSDate date]) compare:(NSDate *)dropDeadDate])
	{
		if ([((NSObject *)aConn) isKindOfClass:[FTPConnection class]])
		{
			NSLog(@"========= TEST: top of loop, state = %d, queue= %@", [((FTPConnection *)aConn) state], [((FTPConnection *)aConn) queueDescription]);
		}
		
		if (0 == [myCallbackDictionary count])	// We don't have any callbacks from the previous iteration
		{
			NSLog(@"========= TEST: will run NSRunLoop");
			BOOL found = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:30.0]];
			//[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:20.0]];
			//[[NSRunLoop currentRunLoop] run];
			NSLog(@"========= TEST: did  run NSRunLoop, found = %d dict = %@", found, [[myCallbackDictionary allKeys] description]);
			if (!found)
			{
				done = true;		// nothing found after waiting this long, so we're done.
				break;
			}
		}
		id value;
		NSDictionary *lastCallbackDictionary = [[myCallbackDictionary copy] autorelease];
		[myCallbackDictionary removeAllObjects];	// clean out the original dict for the next pass
		
		if (nil != (value = [lastCallbackDictionary objectForKey:@"connection:didReceiveError:"]) )
		{
			NSLog(@"========= TEST: Error message: %@", value);
			UKTrue (inExpectConnectionFailure);	// pass if we did expect an error!
			done = YES;	// we're done anyhow.
		}
		else if (nil != (value = [lastCallbackDictionary objectForKey:@"connectionDidSendBadPassword:"]) )
		{
			UKTrue (inExpectConnectionFailure);	// pass if we did expect an error!
			done = YES;	// we're done anyhow.
		}
		else if (nil != (value = [lastCallbackDictionary objectForKey:@"connection:didConnectToHost:"]) )
		{
			NSLog(@"========= TEST: Connected to host: %@", value);
			UKFalse (inExpectConnectionFailure);	// pass if we did not expect an error
			
			// NEXT TASK: MAKE A NEW DIRECTORY
			[aConn createDirectory:[NSString stringWithFormat:@"d%ld", myUniqueNumber]];
		}
		else if (nil != (value = [lastCallbackDictionary objectForKey:@"connection:didCreateDirectory:"]) )
		{
			NSLog(@"========= TEST: Created directory called %@", [NSString stringWithFormat:@"d%ld", myUniqueNumber]);
			UKPass(); // Got our directory
			
			// NEXT TASK: Get the contents of the current directory
			[aConn directoryContents];
		}
		else if (nil != (value = [lastCallbackDictionary objectForKey:@"connection:didReceiveContents:ofDirectory:"]) )
		{
			NSLog(@"========= TEST: Got directory contents %@", [value description]);
			UKPass(); // Got our directory ... REALY OUGHT TO VERIFY THAT OUR FILE IS IN THERE.
			
			// NEXT TASK: Change to that new directory
			[aConn changeToDirectory:[NSString stringWithFormat:@"d%ld", myUniqueNumber]];
		}
		else if (nil != (value = [lastCallbackDictionary objectForKey:@"connection:didChangeToDirectory:"]) )
		{
			if (nil == initialDirectory)
			{
				initialDirectory = [self currentDirectory];	// this will depend on what connection we have
				UKPass(); // Got our directory ... REALY OUGHT TO VERIFY THAT OUR FILE IS IN THERE.
			}
			else	// second change; make sure we are within initial directory
			{
				NSString *expectedNewDirectory = [initialDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"d%ld", myUniqueNumber]];
				UKStringsEqual([self currentDirectory], expectedNewDirectory);
			}

			NSLog(@"========= TEST: Changed to directory %@", [value description]);
						
			// NEXT TASK: Upload a file
			[aConn uploadFile:@"/etc/hosts"];
		}
		else if (nil != (value = [lastCallbackDictionary objectForKey:@"connection:uploadDidFinish:"]) )
		{
			
			
			NSLog(@"========= TEST: Done uploading  %@", [value description]);
			UKPass(); // Got our directory ... REALY OUGHT TO VERIFY THAT OUR FILE IS IN THERE.
			
			done = YES;		// done for now ... we don't have any more tests.
			
		}
		

			
			
		
				/*
				 changing to directory (good/bad)
				 getting directory (as expected?)
				 making directory (good/bad)
				 making directory with certain permissions
				 setting permissions (try a couple of times to make sure they actually change)  (success/fail)
				 rename
				 delete
				 delete directory
				 upload file (some known file, like /etc/hosts, or make a new /tmp file with UUID)
				 .... to directory
				 resume upload file at offset (supported for all?)
				 download file
				 resumeDownload file
				 cancel transfer
				 get directory contents
*/

	}
	
	[aConn disconnect];
	NSLog(@"========= TEST: Disconnected.");
	 
	if (! (NSOrderedAscending == [((NSDate *)[NSDate date]) compare:dropDeadDate]) )
	{
		UKFail();	// Ran out of time!
	}
}

#pragma mark -
#pragma mark File tests

/*!	Test a file connection.  Since there is no connection, we can't test for a bad file connection
*/


- (void)testFileConnection
{
	FileConnection *fc = [FileConnection connection];
	
	[self runTestSuiteWithConnection:fc expectingFailure:NO];
}


#pragma mark -
#pragma mark FTP tests



- (void)testRealFTPConnection
{
	NSDictionary *environment = [[NSProcessInfo processInfo] environment];
	NSString *password = [environment objectForKey:@"biophonyTestPassword"];
		
	FTPConnection *c = [FTPConnection connectionToHost:@"test.biophony.com" port:nil username:@"test" password:password];
	
	[self runTestSuiteWithConnection:c expectingFailure:NO];
}


- (void) testQuotesScan
{
	FTPConnection *c = [FTPConnection connectionToHost:@"bogus" port:nil username:@"test" password:@"nothing"];
	
	UKNil([c scanBetweenQuotes:@"hey there we're the monkeys"]);
	UKNil([c scanBetweenQuotes:@"This has one \" quote mark"]);
	UKStringsEqual([c scanBetweenQuotes:@"empty \"\" quoted string"], @"");
	UKStringsEqual([c scanBetweenQuotes:@"257 \"/somethingee\" created"], @"/somethingee");
	UKStringsEqual([c scanBetweenQuotes:@"257 \"/he said \"\"yo\"\" to me\" created"], @"/he said \"yo\" to me");
}

/*
 
- (void)testBadAccountFTPConnection
{
	FTPConnection *c = [FTPConnection connectionToHost:@"test.biophony.com" port:nil username:@"somebodyelse" password:@"mypassword"];
	
	[self runTestSuiteWithConnection:c expectingFailure:YES];
}

- (void)testConnectionRefusedFTPConnection
{
	FTPConnection *c = [FTPConnection connectionToHost:@"vorlon.karelia.com" port:nil username:@"somebodyelse" password:@"mypassword"];
	
	[self runTestSuiteWithConnection:c expectingFailure:YES];
}

- (void)testHangingFTPConnection
{
	FTPConnection *c = [FTPConnection connectionToHost:@"ftp.zocalo.net" port:nil username:@"somebodyelse" password:@"mypassword"];
	
	[self runTestSuiteWithConnection:c expectingFailure:YES];
}

- (void)testNoHostFTPConnection
{
	FTPConnection *c = [FTPConnection connectionToHost:@"fdjskalrejwfje.com" port:nil username:@"somebodyelse" password:@"mypassword"];
	
	[self runTestSuiteWithConnection:c expectingFailure:YES];
}
*/

#pragma mark -
#pragma mark Private Support


- (NSMutableDictionary *)callbackDictionary
{
    return myCallbackDictionary; 
}
- (void)setCallbackDictionary:(NSMutableDictionary *)aCallbackDictionary
{
    [aCallbackDictionary retain];
    [myCallbackDictionary release];
    myCallbackDictionary = aCallbackDictionary;
}



@end

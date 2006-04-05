/*
 
 DotMacConnection.m
 Marvel
 
 Copyright (c) 2004-2006 Karelia Software. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Karelia Software nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/

#import "DotMacConnection.h"
#import "AbstractConnection.h"
#import "InterThreadMessaging.h"

NSString *kDAVErrorDomain = @"DAVErrorDomain";
NSString *kDAVDoesNotImplementException = @"DAVDoesNotImplementException";
NSString *kDAVInvalidSessionException = @"DAVInvalidSessionException";

#define kDMUpdateDelay 1.0

@interface DotMacConnection ( Private )
- (void)DotMacConnection_getRemoteFileAtPath:(NSString *)remotePath toPath:(NSString *)destinationPath userInfo:(id)userInfo;
- (void)DotMacConnection_moveResourceAtPath:(NSString *)sourcePath toPath:(NSString *)destinationPath userInfo:(id)userInfo;
- (void)DotMacConnection_deleteResourceAtPath:(NSString *)thePath userInfo:(id)userInfo;
- (void)DotMacConnection_listCollectionAtPath:(NSString *)thePath userInfo:(id)userInfo;
- (void)DotMacConnection_putData:(NSData *)data toPath:(NSString *)destinationPath userInfo:(id)userInfo;
- (void)DotMacConnection_putLocalFileAtPath:(NSString *)localPath toPath:(NSString *)destinationPath userInfo:(id)userInfo;
- (void)DotMacConnection_makeCollectionAtPath:(NSString *)dirPath userInfo:(id)userInfo;

- (void)queueInvocation:(NSInvocation *)anInvocation;
- (void)dequeueInvocation:(NSInvocation *)anInvocation;
- (void)processInvocations;

- (void)removePendingTransaction:(DMTransaction *)aTransaction;
- (NSMutableDictionary *)infoForTransaction:(DMTransaction *)aTransaction;
- (void)updateUploadProgressForTransaction:(DMTransaction *)aTransaction;
- (void)updateDownloadProgressForTransaction:(DMTransaction *)aTransaction;

- (void)setAccount:(DMAccount *)anAccount;
- (void)setDMiDiskSession:(DMiDiskSession *)aDMiDiskSession;
- (void)setPendingInvocations:(NSMutableArray *)aPendingInvocations;
- (void)setPendingTransactions:(NSMutableArray *)aPendingTransactions;
- (void)setInFlightTransaction:(DMTransaction *)aTransaction;

- (void)setCurrentDirectory:(NSString *)directoryName;
@end

enum { CONNECT, COMMAND, ABORT, CANCEL_ALL, DISCONNECT, FORCE_DISCONNECT };

@implementation DotMacConnection

#pragma mark class methods

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"80", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"http://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[DotMacConnection class] forTypes:[NSArray arrayWithObjects:port, url, nil]];
	[pool release];
}

+ (NSString *)name
{
	return @".Mac";
}

+ (id)connection
{
	DotMacConnection *c = [[DotMacConnection alloc] init];
	return [c autorelease];
}

- (id)init
{
	[self initWithHost:@".Mac" port:@"ignored" username:@"ignored" password:@"ignored"];
	return self;
}

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
{
	DotMacConnection *c = [[self alloc] initWithHost:host
                                                port:port
                                            username:username
                                            password:password];
	return [c autorelease];
}

#pragma mark init methods

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
{
	if (self = [super initWithHost:host port:port username:username password:password])
	{
        [self setPendingInvocations:[NSMutableArray array]];
        [self setPendingTransactions:[NSMutableArray array]];
        [self setInFlightTransaction:nil];
        myInFlightTransaction = nil;
        myLastProcessedTransaction = nil;
        _transactionInProgress = NO;
		
		myLock = [[NSLock alloc] init];
		myForwarder = [[RunLoopForwarder alloc] init];
		myPort = [[NSPort port] retain];
		[myPort setDelegate:self];
		
		[NSThread prepareForInterThreadMessages];
		
        myUploadPercent = 0;
        myDownloadPercent = 0;

		[self setAccount:[DMMemberAccount accountFromPreferencesWithApplicationID:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleSignature"]]];
		
		[NSThread detachNewThreadSelector:@selector(runDotMacBackgroundThread:) toTarget:self withObject:nil];
	}
	return self;
}

#pragma mark dealloc

- (void)dealloc
{
	[myPort setDelegate:nil];
	[myPort release];
	[myLock release];
	[myForwarder release];
	
    [self setCurrentDirectory:nil];
    [self setDMiDiskSession:nil];
    [self setAccount:nil];

    myLastProcessedTransaction = nil;
    [self setInFlightTransaction:nil];
    [self setPendingTransactions:nil];
    [self setPendingInvocations:nil];

    [super dealloc];
}

#pragma mark Threading

- (void)runDotMacBackgroundThread:(id)notUsed
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	_bgThread = [NSThread currentThread];
	[NSThread prepareForInterThreadMessages];
// NOTE: this may be leaking ... there are two retains going on here.  Apple bug report #2885852, still open after TWO YEARS!
// But then again, we can't remove the thread, so it really doesn't mean much.
	[[NSRunLoop currentRunLoop] addPort:myPort forMode:(NSString *)kCFRunLoopCommonModes];
	[[NSRunLoop currentRunLoop] run];
	
	[pool release];
}

- (void)sendPortMessage:(int)aMessage
{
	if (nil != myPort)
	{
		NSPortMessage *message
		= [[NSPortMessage alloc] initWithSendPort:myPort
									  receivePort:myPort components:nil];
		[message setMsgid:aMessage];
		
		@try {
			BOOL sent = [message sendBeforeDate:[NSDate dateWithTimeIntervalSinceNow:15.0]];
			if (!sent)
			{
				if ([AbstractConnection debugEnabled])
					NSLog(@"DotMacConnection couldn't send message %d", aMessage);
			}
		} @catch (NSException *ex) {
			NSLog(@"%@", ex);
		} @finally {
			[message release];
		} 
	}
}

- (void)handlePortMessage:(NSPortMessage *)portMessage
{
	int message = [portMessage msgid];
	
	switch (message)
	{
		case CONNECT:
		{
			[self setDMiDiskSession:[DMiDiskSession iDiskSessionWithAccount:myAccount]];
			[myDMiDiskSession setDelegate:self];
			[self setCurrentDirectory:@"/"]; // top level
			
			mySyncPeer = [[DMiDiskSession iDiskSessionWithAccount:myAccount] retain];
			[mySyncPeer setIsSynchronous:YES];
			
			int result = [self validateAccess];
			
			if ( kDMSuccess == result )
			{
				if ( _flags.didConnect )
				{
					[myForwarder connection:self didConnectToHost:_connectionHost];
				}
				_flags.isConnected = YES;
			}
			else if ( kDMInvalidCredentials == result )
			{
				if ( _flags.badPassword )
				{
					[myForwarder connectionDidSendBadPassword:self];
				}
			}
			else
			{
				if ( _flags.error )
				{
					[myForwarder connection:self didReceiveError:[NSError errorWithDomain:kDAVErrorDomain code:kDMUnknownError userInfo:[NSDictionary dictionaryWithObject:NSLocalizedString(@"Unknown WebDAV Error", @"") forKey:NSLocalizedDescriptionKey]]];
				}
			}
			break;
		}
		case COMMAND:
		{
			[self processInvocations];
			break;
		}
		case ABORT:
			if ( nil != myInFlightTransaction )
			{
            //NSLog(@"cancelling in-flight transaction:%@ uri:%@", myInFlightTransaction, [myInFlightTransaction uri]);
				[myInFlightTransaction abort];
				[self setInFlightTransaction:nil];
			}
			
			if ( _flags.cancel )
			{
				[myForwarder connectionDidCancelTransfer:self];
			}
			[self processInvocations];
			break;
		
		case CANCEL_ALL:
			if ( nil != myInFlightTransaction )
			{
				[myInFlightTransaction abort];
				[self setInFlightTransaction:nil];
			}
			
			NSEnumerator *e = [myPendingTransactions objectEnumerator];
			id object;
			
			while ( object = [e nextObject] )
			{
				//NSLog(@"transaction info:%@", [object description]);
				[[object objectForKey:@"transaction"] abort];
			}
				[self setPendingInvocations:[NSMutableArray array]];
			
			if ( _flags.cancel )
			{
				[myForwarder connectionDidCancelTransfer:self];
			}
			break;
		case DISCONNECT:
		{
			// a no-op for HTTP/DAV protocol
			NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(DotMacConnection_disconnect:) target:self arguments:[NSArray array]];
			NSLog(@"queuing disconnect");
			[self queueInvocation:invocation];
			break;
		}
		case FORCE_DISCONNECT:
			break;
	}
}

- (void)setDelegate:(id)delegate
{
	[super setDelegate:delegate];
	[myForwarder setDelegate:delegate];
}

#pragma mark AbstractConnectionProtocol methods

- (void)connect
{
    [self sendPortMessage:CONNECT];
}

- (void)disconnect
{
    [self sendPortMessage:DISCONNECT];
}

- (void)forceDisconnect
{
	[self disconnect];
}

- (void)changeToDirectory:(NSString *)dirPath
{
    NSAssert((nil != dirPath), @"dirPath is nil!");
	
    [self setCurrentDirectory:dirPath];
    if ( _flags.changeDirectory )
    {
        [myForwarder connection:self didChangeToDirectory:dirPath];
    }
}

- (NSString *)currentDirectory
{
	return myCurrentDirectory;
}

- (void)createDirectory:(NSString *)dirPath
{
    NSAssert((nil != dirPath), @"dirPath is nil!");

    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"createDirectory:" forKey:@"protocol"];
    if ( [dirPath isAbsolutePath] )
    {
        NSString *path = [dirPath stringByAppendingDirectoryTerminator];
        [self makeCollectionAtPath:path userInfo:userInfo];
    }
    else
    {
        NSString *path = [[[self currentDirectory] stringByAppendingPathComponent:dirPath] stringByAppendingDirectoryTerminator];
        [self makeCollectionAtPath:path
                          userInfo:userInfo];
    }
}

- (void)createDirectoryPath:(NSString *)dirPath
{
    // NB: this method is supposed to create the entire dirPath if it doesn't exist
    // the protocol doesn't include it, so we'll leave as-is for now
    NSAssert((nil != dirPath), @"dirPath is nil!");
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"createDirectoryPath:" forKey:@"protocol"];
    NSString *path = [dirPath stringByAppendingDirectoryTerminator];
    [self makeCollectionAtPath:path
                      userInfo:userInfo];
}

- (void)createDirectory:(NSString *)dirName atPath:(NSString *)dirPath
{
    NSAssert((nil != dirName), @"dirName is nil!");
    NSAssert((nil != dirPath), @"dirPath is nil!");
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"createDirectory:atPath:" forKey:@"protocol"];
    NSString *path = [[dirPath stringByAppendingPathComponent:dirName] stringByAppendingDirectoryTerminator];
    [self makeCollectionAtPath:path
                      userInfo:userInfo];
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
    // this is a no-op for now
    // there really isn't a way to set file permissions via WebDAV, the permissions
    // are the permissions of whatever the apache process is running under on the server

	[self createDirectory:dirPath];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
    // this is a no-op for now
    // there really isn't a way to set file permissions via WebDAV, the permissions
    // are the permissions of whatever the apache process is running under on the server
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
    NSAssert((nil != fromPath), @"fromPath is nil!");
    NSAssert((nil != toPath), @"toPath is nil!");
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"rename:to:" forKey:@"protocol"];
    [self moveResourceAtPath:fromPath toPath:toPath userInfo:userInfo];
}

- (void)deleteFile:(NSString *)path
{
    NSAssert((nil != path), @"path is nil!");
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:NO], @"isDirectory",
        @"deleteFile", @"protocol",
        nil];
    [self deleteResourceAtPath:path userInfo:userInfo];
}

- (void)deleteDirectory:(NSString *)dirPath
{
    NSAssert((nil != dirPath), @"dirPath is nil!");
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:YES], @"isDirectory",
        @"deleteDirectory", @"protocol",
        nil];
    NSString *path = [dirPath stringByAppendingDirectoryTerminator];
    [self deleteResourceAtPath:path userInfo:userInfo];
}

- (void)uploadFile:(NSString *)localPath
{
    NSAssert((nil != localPath), @"localPath is nil!");
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"uploadFile:" forKey:@"protocol"];
    [self putLocalFileAtPath:localPath
                      toPath:[myCurrentDirectory stringByAppendingPathComponent:[localPath lastPathComponent]]
                    userInfo:userInfo];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
    NSAssert((nil != localPath), @"localPath is nil!");
    NSAssert((nil != remotePath), @"remotePath is nil!");
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"uploadFile:toFile:" forKey:@"protocol"];
    [self putLocalFileAtPath:localPath
                      toPath:remotePath
                    userInfo:userInfo];
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(long long)offset
{
    [[NSException exceptionWithName:kDAVDoesNotImplementException
                             reason:[NSString stringWithFormat:@"%@ does not fully implement resumeUploadFile:fileOffset:", [self className]]
                           userInfo:nil] raise];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
    NSAssert((nil != data), @"data is nil!");
    NSAssert((nil != remotePath), @"remotePath is nil!");
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"uploadFromData:toFile:" forKey:@"protocol"];
    [self putData:data
           toPath:remotePath
         userInfo:userInfo];
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(long long)offset
{
    [[NSException exceptionWithName:kDAVDoesNotImplementException
                             reason:[NSString stringWithFormat:@"%@ does not fully implement resumeUploadFromData:toFile:fileOffset:", [self className]]
                           userInfo:nil] raise];
}

- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(long long)offset;
{
    [[NSException exceptionWithName:kDAVDoesNotImplementException
                             reason:[NSString stringWithFormat:@"%@ does not fully implement resumeUploadFile:toFile:fileOffset:", [self className]]
                           userInfo:nil] raise];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
    NSAssert((nil != remotePath), @"remotePath is nil!");
    NSAssert((nil != dirPath), @"dirPath is nil!");
    // deal with overwrite
    if ( !flag && [[NSFileManager defaultManager] fileExistsAtPath:[dirPath stringByAppendingPathComponent:[remotePath lastPathComponent]]] )
    {
        if ( _flags.error )
        {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:remotePath, @"remotePath", dirPath, @"dirPath", [NSString stringWithFormat:NSLocalizedString(@"File %@ already exists", @""), [dirPath stringByAppendingPathComponent:[remotePath lastPathComponent]]], NSLocalizedDescriptionKey, nil];
            [myForwarder connection:self didReceiveError:[NSError errorWithDomain:kDAVErrorDomain code:kDMOverwriteFileError userInfo:userInfo]];
        }
        return;
    }

    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"downloadFile:toDirectory:" forKey:@"protocol"];
    [self getRemoteFileAtPath:remotePath
                       toPath:[dirPath stringByAppendingPathComponent:[remotePath lastPathComponent]]
                     userInfo:userInfo];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(long long)offset
{
    [[NSException exceptionWithName:kDAVDoesNotImplementException
                             reason:[NSString stringWithFormat:@"%@ does not fully implement resumeDownloadFile:toDirectory:fileOffset:", [self className]]
                           userInfo:nil] raise];
}

- (unsigned)numberOfTransfers
{
	if ([self transactionInProgress])
		return 1;
	return 0;
}

- (void)cancelTransfer
{
	[self sendPortMessage:ABORT];
}

- (void)cancelAll
{
    //NSLog(@"cancelling %i invocation(s): %i transaction(s):", [myPendingInvocations count], [myPendingTransactions count]);

    [self sendPortMessage:CANCEL_ALL];
}

// a better method name would be - (void)contentsOfCurrentDirectory
- (void)directoryContents
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"directoryContents" forKey:@"protocol"];
    NSString *path = [myCurrentDirectory stringByAppendingDirectoryTerminator];
	[self listCollectionAtPath:path
                      userInfo:userInfo];
}

//a better method name would be - (void)directoryContentsAtPath:(NSString *)path
- (void)contentsOfDirectory:(NSString *)dirPath
{
    NSAssert((nil != dirPath), @"dirPath is nil!");
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"contentsOfDirectory:" forKey:@"protocol"];
    NSString *path = [dirPath stringByAppendingDirectoryTerminator];
	[self listCollectionAtPath:path
                      userInfo:userInfo];
}

#pragma mark DMTransaction-like methods

// this is a synchronous method, it returns very quickly
// and should likely be called before anything else
- (int)validateAccess
{
	// Check that we have an account.  If not, assume bad password (or account)
	if (nil == myAccount)
	{
		return kDMInvalidCredentials;
	}

    if ( nil != myDMiDiskSession )
    {
        return [myDMiDiskSession validateAccess];
    }
    else
    {
        return kDMUndefined;
    }
}

- (void)putData:(NSData *)data toPath:(NSString *)destinationPath userInfo:(id)userInfo
{
    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(DotMacConnection_putData:toPath:userInfo:)
                                                             target:self
                                                          arguments:[NSArray arrayWithObjects:data, destinationPath, userInfo, nil]];
    [self queueInvocation:invocation];
	NSLog(@".mac queueing data to: %@", destinationPath);
	//NSLog(@"Invocation Queue:\n%@", myPendingInvocations);
}

- (void)makeCollectionAtPath:(NSString *)dirPath userInfo:(id)userInfo
{
	NSLog(@".mac makeDir: %@", dirPath);
//    [self makeCollectionAtPath:dirPath createParents:NO userInfo:userInfo];
        NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(DotMacConnection_makeCollectionAtPath:userInfo:)
                                                                 target:self
                                                              arguments:[NSArray arrayWithObjects:dirPath, userInfo, nil]];
        [self queueInvocation:invocation];
}

//- (void)makeCollectionAtPath:(NSString *)dirPath createParents:(BOOL)flag userInfo:(id)userInfo
//{
//    if ( flag && ([[dirPath pathComponents] count]>1) )
//    {
//        // set up a sequence of invocations for any non-existing directories in dirPath
//        if ( nil != myDMiDiskSession )
//        {
//            if ( ![self resourceExistsAtPath:dirPath] )
//            {
//                NSArray *pathComponents = [dirPath pathComponents];
//                int i = 0;
//                int j;
//                while ( i < [pathComponents count] )
//                {
//                    // construct path to check
//                    NSString *path = @"";
//                    for ( j=0; j<=i; j++)
//                    {
//                        path = [path stringByAppendingPathComponent:[pathComponents objectAtIndex:j]];
//                    }
//
//                    if ( ![self resourceExistsAtPath:path] )
//                    {
//                        NSLog(@"did not find path: %@ i: %i", path, i);
//                        break;
//                    }
//                    i++;
//                }
//
//                NSString *basePath = @"";
//                for ( j=0 ; j<i ; j++ )
//                {
//                    basePath = [basePath stringByAppendingPathComponent:[pathComponents objectAtIndex:j]];
//                }
//                NSLog(@"should start with basePath: %@", basePath);
//
//                NSString *nextPath = basePath;
//                for ( j=i; j<[[dirPath pathComponents] count] ; j++ )
//                {
//                    nextPath = [nextPath stringByAppendingPathComponent:[pathComponents objectAtIndex:j]];
//                    nextPath = [nextPath stringByAppendingString:@"/"];
//
//                    NSLog(@"path to create is %@", nextPath);
//                    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(DotMacConnection_makeCollectionAtPath:userInfo:)
//                                                                             target:self
//                                                                          arguments:[NSArray arrayWithObjects:nextPath, userInfo, nil]];
//                    [self queueInvocation:invocation];
//                }
//            }
//        }
//        else
//        {
//            [[NSException exceptionWithName:kDAVInvalidSessionException
//                                     reason:[NSString stringWithFormat:@"%@ does not have a valid DMiDiskSession", [self className]]
//                                   userInfo:nil] raise];
//        }
//    }
//    else
//    {
//        // don't worry about parent directories, just call DotMacConnection_makeCollectionAtPath with dirPath
//        NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(DotMacConnection_makeCollectionAtPath:userInfo:)
//                                                                 target:self
//                                                              arguments:[NSArray arrayWithObjects:dirPath, userInfo, nil]];
//        [self queueInvocation:invocation];
//    }
//}

- (void)moveResourceAtPath:(NSString *)sourcePath toPath:(NSString *)destinationPath userInfo:(id)userInfo
{
    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(DotMacConnection_moveResourceAtPath:toPath:userInfo:)
                                                             target:self
                                                          arguments:[NSArray arrayWithObjects:sourcePath, destinationPath, userInfo, nil]];
    [self queueInvocation:invocation];
}

- (void)deleteResourceAtPath:(NSString *)thePath userInfo:(id)userInfo
{
    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(DotMacConnection_deleteResourceAtPath:userInfo:)
                                                             target:self
                                                          arguments:[NSArray arrayWithObjects:thePath, userInfo, nil]];
    [self queueInvocation:invocation];
}

- (void)putLocalFileAtPath:(NSString *)localPath toPath:(NSString *)destinationPath userInfo:(id)userInfo
{
    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(DotMacConnection_putLocalFileAtPath:toPath:userInfo:)
                                                             target:self
                                                          arguments:[NSArray arrayWithObjects:localPath, destinationPath, userInfo, nil]];
    [self queueInvocation:invocation];
	NSLog(@".mac queueing file to: %@", destinationPath);
	//NSLog(@"Invocation Queue:\n%@", myPendingInvocations);
}

- (void)getRemoteFileAtPath:(NSString *)remotePath toPath:(NSString *)localPath userInfo:(id)userInfo
{
    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(DotMacConnection_getRemoteFileAtPath:toPath:userInfo:)
                                                             target:self
                                                          arguments:[NSArray arrayWithObjects:remotePath, localPath, userInfo, nil]];
    [self queueInvocation:invocation];
}

- (void)listCollectionAtPath:(NSString *)thePath userInfo:(id)userInfo
{
    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(DotMacConnection_listCollectionAtPath:userInfo:)
                                                             target:self
                                                          arguments:[NSArray arrayWithObjects:thePath, userInfo, nil]];
    [self queueInvocation:invocation];
}

#pragma mark private DMTransaction-like methods

- (void)DotMacConnection_disconnect:(id)notUsed
{
	_flags.isConnected = NO;
	if (_flags.didDisconnect)
		[myForwarder connection:self didDisconnectFromHost:_connectionHost];
}

- (void)DotMacConnection_getRemoteFileAtPath:(NSString *)remotePath toPath:(NSString *)destinationPath userInfo:(id)userInfo
{
    DMTransaction *transaction = [myDMiDiskSession getDataAtPath:remotePath];
    [self setInFlightTransaction:transaction];
    if ( nil != transaction ) {
        [self performSelector:@selector(updateDownloadProgressForTransaction:) withObject:transaction afterDelay:kDMUpdateDelay];
        NSMutableDictionary *tDict = [NSMutableDictionary dictionary];
        [tDict setObject:transaction forKey:@"transaction"];
        [tDict setObject:@"getRemoteFileAtPath:toPath:" forKey:@"operation"];
        [tDict setObject:remotePath forKey:@"remotePath"];
        [tDict setObject:destinationPath forKey:@"destinationPath"];
        if ( (nil != userInfo) && [userInfo isKindOfClass:[NSDictionary class]])
        {
            //[tDict setObject:userInfo forKey:@"userInfo"];
            [tDict addEntriesFromDictionary:userInfo];
        }
        [myPendingTransactions addObject:tDict];
        if ( _flags.didBeginDownload )
        {
            [myForwarder connection:self downloadDidBegin:remotePath];
			myLastTransferBytes = 0;
        }
    }
}

- (void)DotMacConnection_moveResourceAtPath:(NSString *)sourcePath toPath:(NSString *)destinationPath userInfo:(id)userInfo
{
    DMTransaction *transaction = [myDMiDiskSession moveResourceAtPath:sourcePath toPath:destinationPath];
    [self setInFlightTransaction:transaction];
    if ( nil != transaction ) {
        NSMutableDictionary *tDict = [NSMutableDictionary dictionary];
        [tDict setObject:transaction forKey:@"transaction"];
        [tDict setObject:@"moveResourceAtPath:toPath:" forKey:@"operation"];
        [tDict setObject:sourcePath forKey:@"sourcePath"];
        [tDict setObject:destinationPath forKey:@"destinationPath"];
        if ( (nil != userInfo) && [userInfo isKindOfClass:[NSDictionary class]])
        {
            //[tDict setObject:userInfo forKey:@"userInfo"];
            [tDict addEntriesFromDictionary:userInfo];
        }
        [myPendingTransactions addObject:tDict];
    }
}

- (void)DotMacConnection_listCollectionAtPath:(NSString *)thePath userInfo:(id)userInfo
{
    DMTransaction *transaction = [myDMiDiskSession listCollectionAtPath:thePath];
    [self setInFlightTransaction:transaction];
    if ( nil != transaction ) {
        NSMutableDictionary *tDict = [NSMutableDictionary dictionary];
        [tDict setObject:transaction forKey:@"transaction"];
        [tDict setObject:@"listCollectionAtPath:" forKey:@"operation"];
        [tDict setObject:thePath forKey:@"path"];
        if ( (nil != userInfo) && [userInfo isKindOfClass:[NSDictionary class]])
        {
            //[tDict setObject:userInfo forKey:@"userInfo"];
            [tDict addEntriesFromDictionary:userInfo];
        }
        [myPendingTransactions addObject:tDict];
    }
}

- (void)DotMacConnection_deleteResourceAtPath:(NSString *)thePath userInfo:(id)userInfo
{
    DMTransaction *transaction = [myDMiDiskSession deleteResourceAtPath:thePath];
    [self setInFlightTransaction:transaction];
    if ( nil != transaction ) {
        NSMutableDictionary *tDict = [NSMutableDictionary dictionary];
        [tDict setObject:transaction forKey:@"transaction"];
        [tDict setObject:@"deleteResourceAtPath:" forKey:@"operation"];
        [tDict setObject:thePath forKey:@"path"];
        if ( (nil != userInfo) && [userInfo isKindOfClass:[NSDictionary class]])
        {
            //[tDict setObject:userInfo forKey:@"userInfo"];
            [tDict addEntriesFromDictionary:userInfo];
        }
        [myPendingTransactions addObject:tDict];
    }
}

- (void)DotMacConnection_putData:(NSData *)data toPath:(NSString *)destinationPath userInfo:(id)userInfo
{
    DMTransaction *transaction = [myDMiDiskSession putData:data toPath:destinationPath];
    [self setInFlightTransaction:transaction];
    if ( nil != transaction ) {
        [self performSelector:@selector(updateUploadProgressForTransaction:) withObject:transaction afterDelay:kDMUpdateDelay];
        NSMutableDictionary *tDict = [NSMutableDictionary dictionary];
        [tDict setObject:transaction forKey:@"transaction"];
        [tDict setObject:@"putData:toPath:" forKey:@"operation"];
        [tDict setObject:data forKey:@"data"];
        [tDict setObject:destinationPath forKey:@"destinationPath"];
        if ( (nil != userInfo) && [userInfo isKindOfClass:[NSDictionary class]])
        {
            //[tDict setObject:userInfo forKey:@"userInfo"];
            [tDict addEntriesFromDictionary:userInfo];
        }
        [myPendingTransactions addObject:tDict];
        if ( _flags.didBeginUpload )
        {
            [myForwarder connection:self uploadDidBegin:destinationPath];
			myLastTransferBytes = 0;
        }
    }
}

- (void)DotMacConnection_putLocalFileAtPath:(NSString *)localPath toPath:(NSString *)destinationPath userInfo:(id)userInfo
{
    DMTransaction *transaction = [myDMiDiskSession putLocalFileAtPath:localPath toPath:destinationPath];
    [self setInFlightTransaction:transaction];
    if ( nil != transaction ) {
        [self performSelector:@selector(updateUploadProgressForTransaction:) withObject:transaction afterDelay:kDMUpdateDelay];
        NSMutableDictionary *tDict = [NSMutableDictionary dictionary];
        [tDict setObject:transaction forKey:@"transaction"];
        [tDict setObject:@"putLocalFileAtPath:toPath:" forKey:@"operation"];
        [tDict setObject:localPath forKey:@"localPath"];
        [tDict setObject:destinationPath forKey:@"destinationPath"];
        if ( (nil != userInfo) && [userInfo isKindOfClass:[NSDictionary class]])
        {
            //[tDict setObject:userInfo forKey:@"userInfo"];
            [tDict addEntriesFromDictionary:userInfo];
        }
        [myPendingTransactions addObject:tDict];
        if ( _flags.didBeginUpload )
        {
			myLastTransferBytes = 0;
            [myForwarder connection:self uploadDidBegin:localPath];
        }
    }
}

- (void)DotMacConnection_makeCollectionAtPath:(NSString *)dirPath userInfo:(id)userInfo
{
    DMTransaction *transaction = [myDMiDiskSession makeCollectionAtPath:dirPath];
    [self setInFlightTransaction:transaction];
    if ( nil != transaction ) {
        NSMutableDictionary *tDict = [NSMutableDictionary dictionary];
        [tDict setObject:transaction forKey:@"transaction"];
        [tDict setObject:@"makeCollectionAtPath:" forKey:@"operation"];
        [tDict setObject:dirPath forKey:@"path"];
        if ( (nil != userInfo) && [userInfo isKindOfClass:[NSDictionary class]])
        {
            //[tDict setObject:userInfo forKey:@"userInfo"];
            [tDict addEntriesFromDictionary:userInfo];
        }
        [myPendingTransactions addObject:tDict];
    }
}

#pragma mark DMTransactionDelegate methods

- (void)transactionSuccessful:(DMTransaction *)aTransaction
{
	//NSLog(@".mac success: %@", [self infoForTransaction:aTransaction]);
    myLastProcessedTransaction = aTransaction;

    NSMutableDictionary *tDict = [self infoForTransaction:aTransaction];
    if ( nil != tDict )
    {
        NSString *operation = [tDict objectForKey:@"operation"];
        if ( [operation isEqualToString:@"makeCollectionAtPath:"] )
        {
            if ( _flags.createDirectory )
            {
                [myForwarder connection:self didCreateDirectory:[tDict objectForKey:@"path"]];
            }
        }
        else if ( [operation isEqualToString:@"putLocalFileAtPath:toPath:"] )
        {
            [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                     selector:@selector(updateUploadProgressForTransaction:)
                                                       object:aTransaction];
			if ( _flags.uploadPercent ) {
				[myForwarder connection:self upload:[tDict objectForKey:@"destinationPath"] progressedTo:[NSNumber numberWithInt:100]];
			}
			if ( _flags.uploadProgressed ) {
				[myForwarder connection:self upload:[tDict objectForKey:@"destinationPath"] sentDataOfLength:[aTransaction bytesTransferred] - myLastTransferBytes];
			}
            if ( _flags.uploadFinished )
            {
                [myForwarder connection:self uploadDidFinish:[tDict objectForKey:@"destinationPath"]];
            }
			myLastTransferBytes = 0;
        }
        else if ( [operation isEqualToString:@"putData:toPath:"] )
        {
            [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                     selector:@selector(updateUploadProgressForTransaction:)
                                                       object:aTransaction];
			if ( _flags.uploadPercent ) {
				[myForwarder connection:self upload:[tDict objectForKey:@"destinationPath"] progressedTo:[NSNumber numberWithInt:100]];
			}
			if ( _flags.uploadProgressed ) {
				[myForwarder connection:self upload:[tDict objectForKey:@"destinationPath"] sentDataOfLength:[aTransaction bytesTransferred] - myLastTransferBytes];
			}
            if ( _flags.uploadFinished )
            {
                [myForwarder connection:self uploadDidFinish:[tDict objectForKey:@"destinationPath"]];
            }
			myLastTransferBytes = 0;
        }
        else if ( [operation isEqualToString:@"listCollectionAtPath:"] )
        {
            if ( _flags.directoryContents )
            {
                // contents will be result of transaction
                id result = [aTransaction result];
                // build contents array
                NSMutableArray *contentsArray = [NSMutableArray array];
                NSEnumerator *e = [result objectEnumerator];
				NSMutableDictionary *attribs;
                id object;
                while ( object = [e nextObject] )
                {
					attribs = [NSMutableDictionary dictionary];
					NSString *name = [object valueForKey:kDMDisplayName];
					//get the attribs for the file
					[attribs setObject:name forKey:cxFilenameKey];
					if ([[object objectForKey:kDMIsCollection] boolValue]) {
						[attribs setObject:NSFileTypeDirectory forKey:NSFileType];
					} else {
						DMTransaction *getAttribs = [mySyncPeer extendedAttributesAtPath:[[tDict objectForKey:@"path"] stringByAppendingPathComponent:name]];
						id attribResults = [getAttribs result];
						
						[attribs setObject:NSFileTypeRegular forKey:NSFileType];
						[attribs setObject:[attribResults objectForKey:kDMContentLength] forKey:NSFileSize];
					}
					[attribs setObject:[object objectForKey:kDMLastModified] forKey:NSFileModificationDate];
					
					[contentsArray addObject:attribs];
                }
                [myForwarder connection:self didReceiveContents:contentsArray ofDirectory:[tDict objectForKey:@"path"]];
            }
        }
        else if ( [operation isEqualToString:@"moveResourceAtPath:toPath:"] )
        {
            if ( _flags.rename )
            {
                [myForwarder connection:self
                             didRename:[tDict objectForKey:@"sourcePath"]
                                    to:[tDict objectForKey:@"destinationPath"]];
            }
        }
        else if ( [operation isEqualToString:@"getRemoteFileAtPath:toPath:"] )
        {
            [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                     selector:@selector(updateDownloadProgressForTransaction:)
                                                       object:aTransaction];
            // we have to unpack the payload from the transaction and write it out ourselves
            NSData *data = [aTransaction result];
            [data writeToFile:[tDict objectForKey:@"destinationPath"] atomically:YES];

            if ( _flags.downloadFinished )
            {
                [myForwarder connection:self downloadDidFinish:[tDict objectForKey:@"remotePath"]];
            }
			myLastTransferBytes = 0;
        }
        else if ( [operation isEqualToString:@"deleteResourceAtPath:"] )
        {
            BOOL isDirectory = [[tDict objectForKey:@"isDirectory"] boolValue];
            if ( !isDirectory )
            {
                if ( _flags.deleteFile )
                {
                    [myForwarder connection:self didDeleteFile:[tDict objectForKey:@"path"]];
                }
            }
            else
            {
                if ( _flags.deleteDirectory )
                {
                    [myForwarder connection:self didDeleteDirectory:[tDict objectForKey:@"path"]];
                }
            }
        }

        // remove pending transaction dictionary
		[self removePendingTransaction:aTransaction];
    }
    _transactionInProgress = NO;
    [self processInvocations]; // check the internal queue
}

- (void)transactionHadError:(DMTransaction *)aTransaction
{
	//NSLog(@"transactionHadError: %@", [self infoForTransaction:aTransaction]);
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(updateUploadProgressForTransaction:)
                                               object:aTransaction];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(updateDownloadProgressForTransaction:)
                                               object:aTransaction];

    myLastProcessedTransaction = aTransaction;

    NSMutableDictionary *tDict = [self infoForTransaction:aTransaction];
    if ( nil != tDict )
    {
        if ( _flags.error )
        {
			if ([[tDict objectForKey:@"protocol"] isEqualToString:@"createDirectory:"]) {
				BOOL exists, isDir;
				exists = [mySyncPeer fileExistsAtPath:[tDict objectForKey:@"path"] isDirectory:&isDir];
				[tDict setObject:[NSNumber numberWithBool:exists && isDir] forKey:ConnectionDirectoryExistsKey];
			}
			[tDict setObject:[tDict objectForKey:@"path"] forKey:ConnectionDirectoryExistsFilenameKey];
            [myForwarder connection:self didReceiveError:[NSError errorWithDomain:kDAVErrorDomain code:[aTransaction httpStatusCode] userInfo:tDict]];
        }
        [self removePendingTransaction:aTransaction];
    }
    _transactionInProgress = NO;
    [self processInvocations]; // check the internal queue
}

- (void)transactionAborted:(DMTransaction *)aTransaction
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(updateUploadProgressForTransaction:)
                                               object:aTransaction];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(updateDownloadProgressForTransaction:)
                                               object:aTransaction];

    myLastProcessedTransaction = aTransaction;

    NSMutableDictionary *tDict = [self infoForTransaction:aTransaction];
    if ( nil != tDict )
    {
        if ( _flags.error )
        {
			if ([AbstractConnection debugEnabled])
				NSLog(@"transaction aborted, no error will be reported");
            //NSLog(@"%@ transaction description: %@", [tDict description]);
        }
        [myPendingTransactions removeObject:tDict];
    }
    _transactionInProgress = NO;
    [self processInvocations]; // check the internal queue
}

#pragma mark support

- (BOOL)hasValidiDiskSession
{
    return ([self validateAccess] == kDMSuccess);
}

- (BOOL)resourceExistsAtPath:(NSString *)aPath
{
    return [myDMiDiskSession resourceExistsAtPath:aPath];
}

- (BOOL)fileExistsAtPath:(NSString *)aPath
{
    return [myDMiDiskSession fileExistsAtPath:aPath];
}

- (BOOL)directoryExistsAtPath:(NSString *)aPath
{
    NSString *path = [aPath stringByAppendingDirectoryTerminator];
    BOOL isDirectory;
    return ([myDMiDiskSession fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory);
}

#pragma mark private support

- (void)removePendingTransaction:(DMTransaction *)aTransaction
{
	NSEnumerator *e = [myPendingTransactions objectEnumerator];
	NSDictionary *cur;
	
	while (cur = [e nextObject]) {
		if ([cur objectForKey:@"transaction"] == aTransaction) {
			[myPendingTransactions removeObject:cur];
			break;
		}
	}
}

- (NSMutableDictionary *)infoForTransaction:(DMTransaction *)aTransaction
{
    NSEnumerator *e = [myPendingTransactions objectEnumerator];
    NSMutableDictionary *dict;

    while ( dict = [e nextObject] ) {
        if ( [dict objectForKey:@"transaction"] == aTransaction )
        {
			NSMutableDictionary *newDict = [NSMutableDictionary dictionaryWithDictionary:dict];
			[newDict setObject:[NSNumber numberWithInt:[aTransaction transactionState]] forKey:@"transactionState"];
			int statusCode = [aTransaction httpStatusCode];
			[newDict setObject:[NSNumber numberWithInt:statusCode] forKey:@"httpStatusCode"];
			NSString *codeString = [NSHTTPURLResponse localizedStringForStatusCode:statusCode];
			if (nil != codeString)
			{
				[newDict setObject:codeString forKey:@"localizedHttpStatusCode"];
			}

			[newDict setObject:[NSNumber numberWithInt:[aTransaction errorType]] forKey:@"errorType"];

			NSString *errorMessage = nil;
			switch ([aTransaction errorType])
			{
				case kDMInvalidCredentials:
					errorMessage = NSLocalizedString(@"The credentials you provided were not accepted.", @"");
					break;

				case kDMInsufficientStorage:
					errorMessage = NSLocalizedString(@"There is insufficient storage space available.", @"");
					break;

				case kDMNetworkError:
					errorMessage = NSLocalizedString(@"There was a networking error.", @"");
					break;

				default:
					break;
			}
			if (kDMUndefined != [aTransaction httpStatusCode])
			{
				if (nil == codeString)
				{
					codeString = @"";
				}

				if  (nil == errorMessage)
				{

					errorMessage = [NSString stringWithFormat:NSLocalizedString(@"An error occured; HTTP status code = %d %@.", @""), statusCode, codeString];
				}
				else
				{
					errorMessage = [errorMessage stringByAppendingFormat:NSLocalizedString(@"  HTTP status code = %d %@.", @""), statusCode, codeString];
				}
			}
			if (nil != errorMessage)
			{
				[newDict setObject:errorMessage forKey:NSLocalizedDescriptionKey];
			}

            return newDict;
        }
    }

    return nil;
}

- (void)updateUploadProgressForTransaction:(DMTransaction *)aTransaction
{
    if ( nil != aTransaction )
    {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(updateUploadProgressForTransaction:)
                                                   object:aTransaction];
        if ( ![aTransaction isFinished] )
        {
            SInt64 contentLength = [aTransaction contentLength];
            SInt64 bytesTransferred = [aTransaction bytesTransferred];
			bytesTransferred -= myLastTransferBytes;
			myLastTransferBytes = bytesTransferred;
			
            int percent = (int)(((double)bytesTransferred/(double)contentLength)*100);

            if ( _flags.uploadPercent && (percent != myUploadPercent) )
            {
                [myForwarder connection:self upload:[aTransaction uri] progressedTo:[NSNumber numberWithInt:percent]];
            }
            if ( _flags.uploadProgressed )
            {
                [myForwarder connection:self upload:[aTransaction uri] sentDataOfLength:(int)bytesTransferred];
            }
            myUploadPercent = percent;
            [self performSelector:@selector(updateUploadProgressForTransaction:)
                       withObject:aTransaction
                       afterDelay:kDMUpdateDelay];
        }

    }
}

- (void)updateDownloadProgressForTransaction:(DMTransaction *)aTransaction
{
    if ( nil != aTransaction )
    {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(updateDownloadProgressForTransaction:)
                                                   object:aTransaction];
        if ( ![aTransaction isFinished] )
        {
            SInt64 contentLength = [aTransaction contentLength];
            SInt64 bytesTransferred = [aTransaction bytesTransferred];
			bytesTransferred -= myLastTransferBytes;
			myLastTransferBytes = bytesTransferred;
			
            int percent = (int)(((double)bytesTransferred/(double)contentLength)*100);

            if ( _flags.downloadPercent && (percent != myDownloadPercent) )
            {
                [myForwarder connection:self download:[aTransaction uri] progressedTo:[NSNumber numberWithLongLong:(bytesTransferred/contentLength)]];
            }
            if ( _flags.downloadProgressed )
            {
                [myForwarder connection:self download:[aTransaction uri] receivedDataOfLength:(int)bytesTransferred];
            }
            myDownloadPercent = percent;
            [self performSelector:@selector(updateDownloadProgressForTransaction:)
                       withObject:aTransaction
                       afterDelay:kDMUpdateDelay];
        }
    }
}

- (void)queueInvocation:(NSInvocation *)anInvocation
{
    [myPendingInvocations addObject:anInvocation];
	if ([NSThread currentThread] != _bgThread)
	{
		[self sendPortMessage:COMMAND];		// State has changed, check if we can handle message.
	}
	else
	{
		[self processInvocations];	// in background thread, just check the queue now for anything to do
	}
}

- (void)dequeueInvocation:(NSInvocation *)anInvocation
{
    [myPendingInvocations removeObject:anInvocation];
}

- (void)processInvocations
{
	NSAssert([NSThread currentThread] == _bgThread, @"Processing Invocations from wrong thread");
	
    if ( !_transactionInProgress )
    {
        if ( (nil != myPendingInvocations) && ([myPendingInvocations count] > 0) )
        {
            NSInvocation *invocation = [myPendingInvocations objectAtIndex:0];
            if ( nil != invocation )
            {
                [invocation retain];
                [self dequeueInvocation:invocation];
                _transactionInProgress = YES;
                [invocation invoke];
                [invocation release];
            }
        }
    }
}

#pragma mark accessor methods

- (id)account
{
    return myAccount;
}

- (void)setAccount:(DMAccount *)anAccount
{
    if (myAccount != anAccount)
    {
        [anAccount retain];
        [myAccount release];
        myAccount = (DMMemberAccount *)anAccount;
    }
}

- (DMTransaction *)inFlightTransaction
{
    return myInFlightTransaction;
}

- (DMTransaction *)lastProcessedTransaction
{
    return myLastProcessedTransaction;
}

- (BOOL)transactionInProgress
{
    return _transactionInProgress;
}

#pragma mark private accessor methods

- (void)setCurrentDirectory:(NSString *)theCurrentDirectory
{
    if (myCurrentDirectory != theCurrentDirectory)
    {
        [theCurrentDirectory retain];
        [myCurrentDirectory release];
        myCurrentDirectory = theCurrentDirectory;
    }
}

- (DMiDiskSession *)DMiDiskSession
{
    return myDMiDiskSession;
}

- (void)setDMiDiskSession:(DMiDiskSession *)aDMiDiskSession
{
    if (myDMiDiskSession != aDMiDiskSession)
    {
        [aDMiDiskSession retain];
        [myDMiDiskSession release];
        myDMiDiskSession = aDMiDiskSession;
    }
}

- (NSMutableArray *)pendingInvocations
{
    return myPendingInvocations;
}

- (void)setPendingInvocations:(NSMutableArray *)aMutableArray
{
    if (myPendingInvocations != aMutableArray)
    {
        [aMutableArray retain];
        [myPendingInvocations release];
        myPendingInvocations = aMutableArray;
    }
}

- (NSMutableArray *)pendingTransactions
{
    return myPendingTransactions;
}

- (void)setPendingTransactions:(NSMutableArray *)aMutableArray
{
    if (myPendingTransactions != aMutableArray)
    {
        [aMutableArray retain];
        [myPendingTransactions release];
        myPendingTransactions = aMutableArray;
    }
}

- (void)setInFlightTransaction:(DMTransaction *)aTransaction
{
    [aTransaction retain];
    [myInFlightTransaction release];
    myInFlightTransaction = aTransaction;
}

@end

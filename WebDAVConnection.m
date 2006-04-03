/*
 Copyright (c) 2004, Greg Hulands <ghulands@framedphotographics.com>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
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

#import "WebDAVConnection.h"
#import "AbstractConnection.h"
#import "DAVRequest.h"
#import "DAVResponse.h"
#import "GSNSDataExtensions.h"

@implementation WebDAVConnection

#pragma mark class methods

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"80", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"http://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[WebDAVConnection class] forTypes:[NSArray arrayWithObjects:port, url, nil]];
	[pool release];
}

+ (NSString *)name
{
	return @"WebDAV";
}

#pragma mark init methods

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
{
	WebDAVConnection *c = [[self alloc] initWithHost:host
                                                port:port
                                            username:username
                                            password:password];
	return [c autorelease];
}

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
{
	if (self = [super initWithHost:host
                              port:port
                          username:username
                          password:password])
	{
		myRequests = [[NSMutableArray alloc] init];
		myResponseBuffer = [[NSMutableData data] retain];
		NSData *authData = [[NSString stringWithFormat:@"%@:%@", username, password] dataUsingEncoding:NSUTF8StringEncoding];
		myAuthorization = [[NSString stringWithFormat:@"Basic %@", [authData base64EncodingWithLineLength:0]] retain];
	}
	return self;
}

- (void)dealloc
{
	[self sendPortMessage:KILL_THREAD];
	[myCurrentRequest release];
	[myCurrentDirectory release];
	[myResponseBuffer release];
	[myRequests release];
	[super dealloc];
}

#pragma mark -
#pragma mark Stream Overrides

- (void)handlePortMessage:(NSPortMessage *)portMessage
{
    int message = [portMessage msgid];
	
	switch (message)
	{
		case CONNECT:
		{
			[super handlePortMessage:portMessage];
			_flags.isConnected = YES;
			[self setState:ConnectionIdleState];
			if (_flags.didConnect)
			{
				[_forwarder connection:self didConnectToHost:[self host]];
			}
			break;
		}
		default: [super handlePortMessage:portMessage];
	}
}

- (void)processReceivedData:(NSData *)data
{
	[myResponseBuffer appendData:data];
	NSRange responseRange = [DAVResponse canConstructResponseWithData:myResponseBuffer];
	if (responseRange.location != NSNotFound)
	{
		NSData *packetData = [myResponseBuffer subdataWithRange:responseRange];
		DAVResponse *response = [DAVResponse responseWithRequest:myCurrentRequest data:packetData];
		[myResponseBuffer replaceBytesInRange:responseRange withBytes:NULL length:0];
		
		if ([response code] == 401)
		{
			if (myAuthorization != nil)
			{
				// the user or password supplied is bad
				if (_flags.badPassword)
				{
					[_forwarder connectionDidSendBadPassword:self];
					[self setState:ConnectionNotConnectedState];
					if (_flags.didDisconnect)
					{
						[_forwarder connection:self didDisconnectFromHost:[self host]];
					}
				}
			}
			else
			{
				// need to append authorization
				NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
				NSCharacterSet *quote = [NSCharacterSet characterSetWithCharactersInString:@"\""];
				NSString *auth = [[response headerForKey:@"WWW-Authenticate"] stringByTrimmingCharactersInSet:ws];
				NSScanner *scanner = [NSScanner scannerWithString:auth];
				NSString *authMethod = nil;
				NSString *realm = nil;
				[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&authMethod];
				[scanner scanUpToString:@"Realm\"" intoString:nil];
				[scanner scanUpToCharactersFromSet:quote intoString:&realm];
				
				if ([authMethod isEqualToString:@"Basic"])
				{
					NSString *authString = [NSString stringWithFormat:@"%@:%@", [self username], [self password]];
					NSData *authData = [authString dataUsingEncoding:NSUTF8StringEncoding];
					[myAuthorization autorelease];
					myAuthorization = [[authData base64EncodingWithLineLength:0] retain];
					//resend the request with auth
					[self sendCommand:myCurrentRequest];
				}
				else
				{
					@throw [NSException exceptionWithName:NSInternalInconsistencyException
												   reason:@"Only Basic Authentication is supported at the moment"
												 userInfo:nil];
				}
			}
		}
		NSLog(@"Received DAVResponse:\n%@", response);
		NSLog(@"XML Document:\n%@", [response contentString]);
	}
}

- (void)sendCommand:(id)command
{
	if ([command isKindOfClass:[DAVRequest class]])
	{
		NSLog(@"Sending DAVRequest:\n%@", command);
		
		DAVRequest *req = (DAVRequest *)command;
		//make sure we set the host name
		[req setHeader:[self host] forKey:@"Host"];
		if (myAuthorization)
		{
			[req setHeader:myAuthorization forKey:@"Authorization"];
		}
		[self sendData:[req serialized]];
	}
	else 
	{
		//we are an invocation
		NSInvocation *inv = (NSInvocation *)command;
		[inv invoke];
	}
}

- (void)checkQueue
{
	if (myCurrentRequest)
		return;
	if ([myRequests count] > 0)
	{
		[_queueLock lock];
		myCurrentRequest = [[myRequests objectAtIndex:0] retain];
		[myRequests removeObjectAtIndex:0];
		[_queueLock unlock];
		[self sendCommand:myCurrentRequest];
	}
}

- (void)queueRequest:(id)request
{
	[_queueLock lock];
	[myRequests addObject:request];
	[_queueLock unlock];
	
	[self sendPortMessage:COMMAND];
}

#pragma mark -
#pragma mark Abstract Connection Protocol

- (void)davDidChangeToDirectory:(NSString *)dirPath
{
	[myCurrentDirectory autorelease];
	myCurrentDirectory = [dirPath copy];
	if (_flags.changeDirectory)
	{
		[_forwarder connection:self didChangeToDirectory:dirPath];
	}
	[myCurrentRequest release];
	myCurrentRequest = nil;
	[self checkQueue];
}

- (void)changeToDirectory:(NSString *)dirPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(davDidChangeToDirectory:)
													  target:self
												   arguments:[NSArray arrayWithObjects: dirPath]];
	[self queueRequest:inv];
}

- (NSString *)currentDirectory
{
	return myCurrentDirectory;
}

- (NSString *)rootDirectory
{
	return nil;
}

- (void)createDirectory:(NSString *)dirPath
{
	
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	[self createDirectory:dirPath];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSAssert((nil != fromPath), @"fromPath is nil!");
    NSAssert((nil != toPath), @"toPath is nil!");
	
}

- (void)deleteFile:(NSString *)path
{
	
}

- (void)deleteDirectory:(NSString *)dirPath
{
	
}

- (void)uploadFile:(NSString *)localPath
{
	
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(long long)offset
{
	
}

- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(long long)offset
{
	
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(long long)offset
{
	
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"WebDAV does not currently support downloading"
								 userInfo:nil];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(long long)offset
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"WebDAV does not currently support downloading"
								 userInfo:nil];
}

- (void)davDirectoryContents:(NSString *)dir
{
	DAVRequest *r = [DAVDirectoryContentsRequest directoryContentsForPath:dir != nil ? dir : myCurrentDirectory];
	[myCurrentRequest autorelease];
	myCurrentRequest = [r retain];
	[self sendCommand:r];
}

- (void)directoryContents
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(davDirectoryContents:)
													  target:self
												   arguments:[NSArray array]];
	[self queueRequest:inv];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(davDirectoryContents:)
													  target:self
												   arguments:[NSArray arrayWithObject:dirPath]];
	[self queueRequest:inv];
}

- (long long)transferSpeed
{
	
}

- (void)checkExistenceOfPath:(NSString *)path
{
	
}

@end

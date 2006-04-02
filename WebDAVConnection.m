/*
 
 WebDAVConnection.m
 Marvel
 
 Copyright (c) 2004-2005 Biophony LLC. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Biophony LLC nor the names of its contributors may be used to 
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
#import "DAVKitPrivate.h"
#import "AbstractConnection.h"
#import "InterThreadMessaging.h"

enum { CONNECT, COMMAND, ABORT, CANCEL_ALL, DISCONNECT, FORCE_DISCONNECT, KILL_THREAD };

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
		
		
	}
	return self;
}

- (void)dealloc
{
	[self sendPortMessage:KILL_THREAD];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Abstract Connection Protocol

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
	[self sendPortMessage:FORCE_DISCONNECT];
}

- (void)changeToDirectory:(NSString *)dirPath
{
	
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
	//we cannot set permissions via webdav
	[self createDirectory:dirPath];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	//we cannot set permissions via webdav
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
	
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(long long)offset
{
	
}

- (unsigned)numberOfTransfers
{
	
}

- (void)cancelTransfer
{
	
}

- (void)cancelAll
{
	
}

- (void)directoryContents
{

}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	
}

- (long long)transferSpeed
{
	
}

- (void)checkExistenceOfPath:(NSString *)path
{
	
}

@end

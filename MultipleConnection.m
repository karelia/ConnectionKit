//
//  MultipleConnection.m
//  FTPConnection
//
//  Created by Greg Hulands on 9/01/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "MultipleConnection.h"


@implementation MultipleConnection

- (id)init
{
	if (self = [super initWithHost:@"na" port:@"na" username:@"na" password:@"na"]) {
		_connections = [[NSMutableArray array] retain];
	}
	return self;
}

/* Just keep the framework happy with this */
- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
{
	if (self = [self init]) {
		
	}
	return self
}

- (void)dealloc
{
	[_connections release];
	[super dealloc];
}

- (void)addConnection:(id<AbstractConnectionProtocol>)connection
{
	if (_flags.isConnected) {
		@throw [NSException exceptionWithName:NSInternalInconsistencyException
									   reason:@"You can only add connections when disconnected"
									 userInfo:nil];
	}
		
	if (![_connections containsObject:connection]) {
		[_connections addObject:connection];
	}
}

- (void)removeConnection:(id<AbstractConnectionProtocol>)connection
{
	if (_flags.isConnected) {
		@throw [NSException exceptionWithName:NSInternalInconsistencyException
									   reason:@"You can only remove connections when disconnected"
									 userInfo:nil];
	}
	if ([_connections containsObject:connection]) {
		[_connections removeObject:connection];
	}
}

- (NSArray *)connections
{
	return [NSArray arrayWithArray:_connections];
}

#pragma mark -
#pragma mark Abstract Connection Protocol

- (void)connect
{
	[_connections makeObjectsPerformSelector:@selector(setDelegate:) withObject:self];
	[_connections makeObjectsPerformSelector:@selector(connect)];
}

- (void)disconnect
{
	[_connections makeObjectsPerformSelector:@selector(disconnect)];
}

- (void)forceDisconnect
{
	[_connections makeObjectsPerformSelector:@selector(forceDisconnect)];
}

- (void)changeToDirectory:(NSString *)dirPath
{
	[_connections makeObjectsPerformSelector:@selector(changeToDirectory:) withObject:dirPath];
}

- (NSString *)currentDirectory
{
	return nil;
}

- (NSString *)rootDirectory
{
	return nil;
}

- (void)createDirectory:(NSString *)dirPath
{
	[_connections makeObjectsPerformSelector:@selector(createDirectory:) withObject:dirPath];
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	NSEnumerator *e = [_connections objectEnumerator];
	id<AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject]) {
		[cur createDirectory:dirPath permissions:permissions];
	}
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	NSEnumerator *e = [_connections objectEnumerator];
	id<AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject]) {
		[cur setPermissions:permissions forFile:path];
	}
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSEnumerator *e = [_connections objectEnumerator];
	id<AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject]) {
		[cur rename:fromPath to:toPath];
	}
}

- (void)deleteFile:(NSString *)path
{
	[_connections makeObjectsPerformSelector:@selector(deleteFile:) withObject:path];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	[_connections makeObjectsPerformSelector:@selector(deleteDirectory:) withObject:dirPath];
}

- (void)startBulkCommands
{
	[_connections makeObjectsPerformSelector:@selector(startBulkCommands)];
}

- (void)endBulkCommands
{
	[_connections makeObjectsPerformSelector:@selector(endBulkCommands)];
}

- (void)uploadFile:(NSString *)localPath
{
	[self uploadFile:localPath toFile:[localPath lastPathComponent]];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath
{
	[self uploadFile:localPath toFile:remotePath checkRemoteExistence:NO];
}

- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	NSEnumerator *e = [_connections objectEnumerator];
	id<AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject]) {
		[cur uploadFile:localPath toFile:remotePath checkRemoteExistence:flag];
	}
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(long long)offset
{
	[self resumeUploadFile:localPath toFile:[localPath lastPathComponent] fileOffset:0];
}

- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(long long)offset
{
	NSEnumerator *e = [_connections objectEnumerator];
	id<AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject]) {
		[cur resumeUploadFile:localPath toFile:remotePath fileOffset:offset];
	}
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	[self uploadFromData:data toFile:remotePath checkRemoteExistence:NO];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	NSEnumerator *e = [_connections objectEnumerator];
	id<AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject]) {
		[cur uploadFromData:data toFile:remotePath checkRemoteExistence:flag];
	}
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(long long)offset
{
	NSEnumerator *e = [_connections objectEnumerator];
	id<AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject]) {
		[cur resumeUploadFromData:data toFile:remotePath fileOffset:offset];
	}
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"MultipleConnections does not support downloading"
								 userInfo:nil];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(long long)offset
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"MultipleConnections does not support downloading"
								 userInfo:nil];
}

- (unsigned)numberOfTransfers
{
	
}

- (void)cancelTransfer
{
	[_connections makeObjectsPerformSelector:cancelTransfer];
}

- (void)cancelAll
{
	[_connections makeObjectsPerformSelector:cancelAll];
}

- (void)directoryContents
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"MultipleConnections does not support directoryContents"
								 userInfo:nil];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"MultipleConnections does not support contentsOfDirectory"
								 userInfo:nil];
}

- (void)checkExistenceOfPath:(NSString *)path
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"MultipleConnections does not support checkExistenceOfPath"
								 userInfo:nil];
}

#pragma mark -
#pragma mark Connection Delegate Methods

- (BOOL)connection:(id <AbstractConnectionProtocol>)con authorizeConnectionToHost:(NSString *)host message:(NSString *)message
{
	return [_delegate connection:self authorizeConnectionToHost:host message:message];
}

- (void)connection:(id <AbstractConnectionProtocol>)con didConnectToHost:(NSString *)host
{
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con didCreateDirectory:(NSString *)dirPath
{
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteDirectory:(NSString *)dirPath
{
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteFile:(NSString *)path
{
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host
{
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveError:(NSError *)error
{
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con didRename:(NSString *)fromPath to:(NSString *)toPath
{
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con didSetPermissionsForFile:(NSString *)path
{
	
}

- (NSString *)connection:(id <AbstractConnectionProtocol>)con needsAccountForUsername:(NSString *)username
{
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath progressedTo:(NSNumber *)percent
{
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath sentDataOfLength:(int)length
{
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidBegin:(NSString *)remotePath
{
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidFinish:(NSString *)remotePath
{
	
}

- (void)connectionDidCancelTransfer:(id <AbstractConnectionProtocol>)con
{
	
}

- (void)connectionDidSendBadPassword:(id <AbstractConnectionProtocol>)con
{
	
}

- (void)connection:(id <AbstractConnectionProtocol>)con checkedExistenceOfPath:(NSString *)path pathExists:(BOOL)exists
{
	
}

@end

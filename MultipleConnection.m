/*
 Copyright (c) 2004, Greg Hulands <ghulands@mac.com>
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

#import "MultipleConnection.h"
#import "AbstractConnectionProtocol.h"

@implementation MultipleConnection

- (id)init
{
	if (self = [super initWithHost:@"na" port:@"na" username:@"na" password:@"na" error:nil]) {
		_connections = [[NSMutableArray array] retain];
		_folderCreations = [[NSMutableArray array] retain];
		_connectedConnections = [[NSMutableArray array] retain];
	}
	return self;
}

/* Just keep the framework happy with this */
- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
			 error:(NSError **)error
{
	if (self = [self init]) {
		
	}
	return self;
}

- (void)dealloc
{
	[_connections release];
	[_folderCreations release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Overrides

- (NSString *)host
{
	NSMutableArray *hosts = [NSMutableArray array];
	NSEnumerator *e = [_connections objectEnumerator];
	id <AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject])
	{
		[hosts addObject:[cur host]];
	}
	
	if ([hosts count] == 1)
	{
		return [NSString stringWithFormat:@"%@", [[hosts objectAtIndex:0] host]];
	}
	else if ([hosts count] == 2)
	{
		return [NSString stringWithFormat:@"%@ %@ %@", [[hosts objectAtIndex:0] host], 
			LocalizedStringInConnectionKitBundle(@"and", @"multiple connection joiner"), [[hosts objectAtIndex:1] host]];
	}
	else
	{
		NSString *lastObject = [[[hosts lastObject] copy] autorelease];
		[hosts removeLastObject];
		NSString *joined = [hosts componentsJoinedByString:@", "];
		return [NSString stringWithFormat:@"%@ %@ %@", joined, LocalizedStringInConnectionKitBundle(@"and", @"multiple connection joiner"), lastObject];
	}
}

#pragma mark -
#pragma mark API

- (BOOL)hasQueuedCommands
{
	return ([_commandQueue count] > 0 && [_downloadQueue count] > 0 &&
			[_uploadQueue count] > 0 && [_fileDeletes count] > 0 &&
			[_filePermissions count] > 0 && [_fileRenames count] > 0 &&
			[_folderCreations count] > 0);
}

- (void)addConnection:(id<AbstractConnectionProtocol>)connection
{
	if (_flags.isConnected) {
		@throw [NSException exceptionWithName:NSInternalInconsistencyException
									   reason:@"You can only add connections when disconnected"
									 userInfo:nil];
	}
	if ([self hasQueuedCommands])
	{
		@throw [NSException exceptionWithName:NSInternalInconsistencyException
									   reason:@"You can only add connections when nothing has been queued"
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
#pragma mark Queue Additions

- (NSMutableDictionary *)newRecord
{
	NSMutableDictionary *rec = [NSMutableDictionary dictionary];
	[rec setObject:[NSMutableArray arrayWithArray:_connections] forKey:@"Connections"];
	return rec;
}

- (void)queueCreateDirectory:(id)dir
{
	[_folderCreations addObject:dir];
}

- (void)dequeueCreateDirectory
{
	[_folderCreations removeObjectAtIndex:0];
}

- (id)currentCreateDirectory
{
	return [_folderCreations objectAtIndex:0];
}

- (unsigned)numberOfCreateDirectories
{
	return [_folderCreations count];
}

- (NSArray *)createDirectories
{
	return [NSArray arrayWithArray:_folderCreations];
}

- (id)matchKey:(NSString *)key withValue:(id)value inQueue:(NSArray *)queue
{
	NSEnumerator *e = [queue objectEnumerator];
	NSDictionary *cur;
	
	while (cur = [e nextObject])
	{
		if ([[cur objectForKey:key] isEqualTo:value])
		{
			return cur;
		}
	}
	return nil;
}

- (id)uploadWithRemotePath:(NSString *)path
{
	return [self matchKey:@"file" withValue:path inQueue:_uploadQueue];
}

- (id)deletionWithRemotePath:(NSString *)path
{
	return [self matchKey:@"file" withValue:path inQueue:_fileDeletes];
}

- (id)renameWithRemotePath:(NSString *)path
{
	return [self matchKey:@"file" withValue:path inQueue:_fileRenames];
}

- (id)createDirectoryWithRemotePath:(NSString *)path
{
	return [self matchKey:@"folder" withValue:path inQueue:_folderCreations];
}

- (id)permissionChangeWithRemotePath:(NSString *)path
{
	return [self matchKey:@"file" withValue:path inQueue:_filePermissions];
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

- (void) cleanupConnection
{
	[_connections makeObjectsPerformSelector:@selector(cleanupConnection)];
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
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no directory specified");
	NSMutableDictionary *rec = [self newRecord];
	[rec setObject:dirPath forKey:@"folder"];
	[self queueCreateDirectory:rec];
	[_connections makeObjectsPerformSelector:@selector(createDirectory:) withObject:dirPath];
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	NSEnumerator *e = [_connections objectEnumerator];
	id<AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject])
	{
		[cur createDirectory:dirPath];
		[cur setPermissions:permissions forFile:dirPath];
	}
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"no file/path specified");
	NSMutableDictionary *rec = [self newRecord];
	[rec setObject:path forKey:@"file"];
	[self queuePermissionChange:rec];
	
	NSEnumerator *e = [_connections objectEnumerator];
	id<AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject]) {
		[cur setPermissions:permissions forFile:path];
	}
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	NSAssert(fromPath && ![fromPath isEqualToString:@""], @"fromPath is nil!");
    NSAssert(toPath && ![toPath isEqualToString:@""], @"toPath is nil!");
	
	NSMutableDictionary *rec = [self newRecord];
	[rec setObject:toPath forKey:@"file"];
	[self queueRename:rec];
	
	NSEnumerator *e = [_connections objectEnumerator];
	id<AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject]) {
		[cur rename:fromPath to:toPath];
	}
}

- (void)deleteFile:(NSString *)path
{
	NSAssert(path && ![path isEqualToString:@""], @"path is nil!");
	
	NSMutableDictionary *rec = [self newRecord];
	[rec setObject:path forKey:@"file"];
	[self queueDeletion:rec];
	
	[_connections makeObjectsPerformSelector:@selector(deleteFile:) withObject:path];
}

- (void)deleteDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"dirPath is nil!");
	
	NSMutableDictionary *rec = [self newRecord];
	[rec setObject:dirPath forKey:@"file"];
	[self queueDeletion:rec];
	
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
	NSMutableDictionary *rec = [self newRecord];
	[rec setObject:remotePath forKey:@"file"];
	[rec setObject:[NSNumber numberWithInt:0] forKey:@"percent"];
	[rec setObject:[NSNumber numberWithLong:0] forKey:@"bytes"];
	[self queueUpload:rec];
	
	NSEnumerator *e = [_connections objectEnumerator];
	id<AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject]) {
		[cur uploadFile:localPath toFile:remotePath checkRemoteExistence:flag];
	}
}

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(unsigned long long)offset
{
	[self resumeUploadFile:localPath toFile:[localPath lastPathComponent] fileOffset:0];
}

- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"Not supported in MultipleConnection"
								 userInfo:nil];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath
{
	[self uploadFromData:data toFile:remotePath checkRemoteExistence:NO];
}

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag
{
	NSMutableDictionary *rec = [self newRecord];
	[rec setObject:remotePath forKey:@"file"];
	[rec setObject:[NSNumber numberWithInt:0] forKey:@"percent"];
	[rec setObject:[NSNumber numberWithLong:0] forKey:@"bytes"];
	[self queueUpload:rec];
	
	NSEnumerator *e = [_connections objectEnumerator];
	id<AbstractConnectionProtocol>cur;
	
	while (cur = [e nextObject]) {
		[cur uploadFromData:data toFile:remotePath checkRemoteExistence:flag];
	}
}

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"Not supported in MultipleConnection"
								 userInfo:nil];
}

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"MultipleConnections does not support downloading"
								 userInfo:nil];
}

- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(unsigned long long)offset
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"MultipleConnections does not support downloading"
								 userInfo:nil];
}

- (void)cancelTransfer
{
	[_connections makeObjectsPerformSelector:@selector(cancelTransfer)];
}

- (void)cancelAll
{
	[_connections makeObjectsPerformSelector:@selector(cancelAll)];
}

- (void)directoryContents
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"MultipleConnections does not support directoryContents"
								 userInfo:nil];
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	NSAssert(dirPath && ![dirPath isEqualToString:@""], @"no dirPath");
	
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

- (void)connection:(id <AbstractConnectionProtocol>)con didConnectToHost:(NSString *)host error:(NSError *)error
{
	_flags.isConnected = YES;
	[_connectedConnections addObject:con];
	if ([_connectedConnections count] == 1)
	{
		//we notify as soon as the first connection makes contact
		if (_flags.didConnect)
		{
			[_delegate connection:self didConnectToHost:host error:nil];
		}
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didCreateDirectory:(NSString *)dirPath
{
	NSMutableDictionary *rec = [self createDirectoryWithRemotePath:dirPath];
	NSMutableArray *connections = [rec objectForKey:@"Connections"];
	[connections removeObject:con];
	
	if ([connections count] == 0)
	{
		if (_flags.createDirectory)
		{
			[_delegate connection:self didCreateDirectory:dirPath];
		}
		[_folderCreations removeObject:rec];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteDirectory:(NSString *)dirPath
{
	NSMutableDictionary *rec = [self deletionWithRemotePath:dirPath];
	NSMutableArray *connections = [rec objectForKey:@"Connections"];
	[connections removeObject:con];
	
	if ([connections count] == 0)
	{
		if (_flags.deleteDirectory)
		{
			[_delegate connection:self didDeleteDirectory:dirPath];
		}
		[_fileDeletes removeObject:rec];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteFile:(NSString *)path
{
	NSMutableDictionary *rec = [self deletionWithRemotePath:path];
	NSMutableArray *connections = [rec objectForKey:@"Connections"];
	[connections removeObject:con];
	
	if ([connections count] == 0)
	{
		if (_flags.deleteFile)
		{
			[_delegate connection:self didDeleteFile:path];
		}
		[_fileDeletes removeObject:rec];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host
{
	[_connectedConnections removeObject:con];
	if ([_connectedConnections count] == 0)
	{
		//we notify once all connections are disconnected
		if (_flags.didDisconnect)
		{
			[_delegate connection:self didDisconnectFromHost:host];
		}
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveError:(NSError *)error
{
	if (_flags.error)
	{
		[_delegate connection:self didReceiveError:error];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didRename:(NSString *)fromPath to:(NSString *)toPath error:(NSError *)error
{
	NSMutableDictionary *rec = [self renameWithRemotePath:toPath];
	NSMutableArray *connections = [rec objectForKey:@"Connections"];
	[connections removeObject:con];
	
	if ([connections count] == 0)
	{
		if (_flags.rename)
		{
			[_delegate connection:self didRename:fromPath to:toPath error:error];
		}
		[_fileRenames removeObject:rec];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con didSetPermissionsForFile:(NSString *)path
{
	NSMutableDictionary *rec = [self permissionChangeWithRemotePath:path];
	NSMutableArray *connections = [rec objectForKey:@"Connections"];
	[connections removeObject:con];
	
	if ([connections count] == 0)
	{
		if (_flags.permissions)
		{
			[_delegate connection:self didSetPermissionsForFile:path];
		}
		[_filePermissions removeObject:rec];
	}
}
 
- (NSString *)connection:(id <AbstractConnectionProtocol>)con needsAccountForUsername:(NSString *)username
{
	if (_flags.error)
	{
		NSError *err = [NSError errorWithDomain:ConnectionErrorDomain
										   code:555
									   userInfo:[NSDictionary dictionaryWithObject:@"You need to setup the accounts properly"
																			forKey:NSLocalizedDescriptionKey]];
		[_delegate connection:self didReceiveError:err];
	}
	return @"";
}

- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath progressedTo:(NSNumber *)percent
{
	NSMutableDictionary *rec = [self uploadWithRemotePath:remotePath];
	NSNumber *per = [rec objectForKey:@"percent"];
	int val = [per intValue];
	val += [percent intValue];
	[rec setObject:[NSNumber numberWithInt:val] forKey:@"percent"];
	div_t divide = div(val, [_connections count]);
	if (_flags.uploadPercent)
	{
		[_delegate connection:self upload:remotePath progressedTo:[NSNumber numberWithInt:divide.quot]];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath sentDataOfLength:(unsigned long long)length
{
	NSMutableDictionary *rec = [self uploadWithRemotePath:remotePath];
	NSNumber *bytes = [rec objectForKey:@"bytes"];
	unsigned long long val = [bytes unsignedLongLongValue];
	val += length;
	[rec setObject:[NSNumber numberWithUnsignedLongLong:val] forKey:@"bytes"];
	lldiv_t div = lldiv(length, [_connections count]);
	if (_flags.uploadProgressed)
	{
		[_delegate connection:self upload:remotePath sentDataOfLength:div.quot];
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidBegin:(NSString *)remotePath
{
	NSMutableDictionary *rec = [self uploadWithRemotePath:remotePath];
	NSNumber *didSend = [rec objectForKey:@"didSendBegin"];
	
	if (!didSend)
	{
		[rec setObject:[NSNumber numberWithBool:YES] forKey:@"didSendBegin"];
		if (_flags.didBeginUpload)
		{
			[_delegate connection:self uploadDidBegin:remotePath];
		}
	}
}

- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidFinish:(NSString *)remotePath
{
	NSMutableDictionary *rec = [self uploadWithRemotePath:remotePath];
	NSMutableArray *connections = [rec objectForKey:@"Connections"];
	[connections removeObject:con];
	
	if ([connections count] == 0)
	{
		if (_flags.uploadFinished)
		{
			[_delegate connection:self uploadDidFinish:remotePath];
		}
	}
}

- (void)connectionDidCancelTransfer:(id <AbstractConnectionProtocol>)con
{
	// we don't pass this on at the moment
}

- (void)connectionDidSendBadPassword:(id <AbstractConnectionProtocol>)con
{
	if (_flags.badPassword)
	{
		NSLog(@"Bad Password for actual connection: %@@%@", [con username], [con host]);
		[_delegate connectionDidSendBadPassword:self];
	}
}

@end

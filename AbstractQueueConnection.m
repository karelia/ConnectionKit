/*
 Copyright (c) 2005, Greg Hulands <ghulands@framedphotographics.com>
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

#import "AbstractQueueConnection.h"

//Download Queue Keys
NSString *QueueDownloadDestinationFileKey = @"QueueDownloadDestinationFileKey";
NSString *QueueDownloadRemoteFileKey = @"QueueDownloadRemoteFileKey";
NSString *QueueUploadLocalFileKey = @"QueueUploadLocalFileKey";
NSString *QueueUploadLocalDataKey = @"QueueUploadLocalDataKey";
NSString *QueueUploadRemoteFileKey = @"QueueUploadRemoteFileKey";
NSString *QueueUploadOffsetKey = @"QueueUploadOffsetKey";
NSString *QueueDownloadTransferPercentReceived = @"QueueDownloadTransferPercentReceived";

NSString *QueueDomain = @"Queuing";

#define QUEUE_HISTORY_COMMAND_SIZE 10

@implementation AbstractQueueConnection

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
{
	if (self = [super initWithHost:host port:port username:username password:password])
	{
		_queueLock = [[NSRecursiveLock alloc] init];
		
		_commandHistory = [[NSMutableArray array] retain];
		_commandQueue = [[NSMutableArray array] retain];
		_downloadQueue = [[NSMutableArray array] retain];
		_uploadQueue = [[NSMutableArray array] retain];
		_fileDeletes = [[NSMutableArray array] retain];
		_fileRenames = [[NSMutableArray array] retain];
		_filePermissions = [[NSMutableArray array] retain];
		_fileCheckQueue = [[NSMutableArray array] retain];
		_filesNeedingOverwriteConfirmation = [[NSMutableDictionary dictionary] retain];
	}
	return self;
}

- (void)dealloc
{
	[_queueLock release];
	[_commandHistory release];
	[_commandQueue release];
	[_downloadQueue release];
	[_uploadQueue release];
	[_fileDeletes release];
	[_fileRenames release];
	[_filePermissions release];
	[_fileCheckQueue release];
	[_filesNeedingOverwriteConfirmation release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Command History

- (id)lastCommand
{
	[_queueLock lock];
	id last = [_commandHistory count] > 0 ? [_commandHistory objectAtIndex:0] : nil;
	[_queueLock unlock];
	return last;
}

- (NSArray *)commandHistory
{
	[_queueLock lock];
	NSArray *copy = [NSArray arrayWithArray:_commandHistory];
	[_queueLock unlock];
	return copy;
}

- (void)pushCommandOnHistoryQueue:(id)command
{
	KTLog(QueueDomain, KTLogDebug, @"Pushing Command on History Queue: %@", command);
	[_queueLock lock];
	[_commandHistory insertObject:command atIndex:0];
	if (QUEUE_HISTORY_COMMAND_SIZE != 0 && [_commandHistory count] > QUEUE_HISTORY_COMMAND_SIZE)
	{
		[_commandHistory removeLastObject];
	}
	[_queueLock unlock];
}

- (void)pushCommandOnCommandQueue:(id)command
{
	KTLog(QueueDomain, KTLogDebug, @"Pushing Command on Command Queue: %@", command);
	[_queueLock lock];
	[_commandQueue insertObject:command atIndex:0];
	[_queueLock unlock];
}

#pragma mark -
#pragma mark Queue Support

- (void)checkQueue
{
	//subclasses need to implement this.
}

- (NSString *)queueDescription
{
	NSMutableString *string = [NSMutableString string];
	NSEnumerator *theEnum = [_commandQueue objectEnumerator];
	id object;
	[string appendFormat:@"Current State: %@\n", [self stateName:GET_STATE]];
	[string appendString:@"(\n"];
	
	while (nil != (object = [theEnum nextObject]) )
	{
		[string appendFormat:@"\t\"%@\" ? %@ > %@,\n", [object command], [self stateName:[object awaitState]], [self stateName:[object sentState]]];
	}
	[string deleteCharactersInRange:NSMakeRange([string length] - 2, 2)];
	[string appendString:@"\n)"];
	return string;
}

#define ADD_TO_QUEUE(queue, object) [_queueLock lock]; [queue addObject:object]; [_queueLock unlock];

- (void)queueCommand:(ConnectionCommand *)command
{
	[_queueLock lock];
	[_commandQueue addObject:command];
	KTLog(QueueDomain, KTLogDebug, @".. %@ (queue size now = %d)", [command command], [_commandQueue count]);		// show when a command gets queued
	[_queueLock unlock];
}

- (void)queueDownload:(id)download
{
	KTLog(QueueDomain, KTLogDebug, @"Queuing Download: %@", download);
	ADD_TO_QUEUE(_downloadQueue, download)
}

- (void)queueUpload:(id)upload
{
	KTLog(QueueDomain, KTLogDebug, @"Queueing Upload: %@", upload);
	ADD_TO_QUEUE(_uploadQueue, upload)
}

- (void)queueDeletion:(id)deletion
{
	KTLog(QueueDomain, KTLogDebug, @"Queuing Deletion: %@", deletion);
	ADD_TO_QUEUE(_fileDeletes, deletion)
}

- (void)queueRename:(id)name
{
	KTLog(QueueDomain, KTLogDebug, @"Queuing Rename: %@", name);
	ADD_TO_QUEUE(_fileRenames, name)
}

- (void)queuePermissionChange:(id)perms
{
	KTLog(QueueDomain, KTLogDebug, @"Queuing Permission Change: %@", perms);
	ADD_TO_QUEUE(_filePermissions, perms)
}

- (void)queueFileCheck:(id)file
{
	KTLog(QueueDomain, KTLogDebug, @"Queuing File Existence: %@", file);
	ADD_TO_QUEUE(_fileCheckQueue, file);
}

#define DEQUEUE(q) [_queueLock lock]; [q removeObjectAtIndex:0]; [_queueLock unlock];

- (void)dequeueCommand
{
	KTLog(QueueDomain, KTLogDebug, @"Dequeuing Command");
	DEQUEUE(_commandQueue)
}

- (void)dequeueDownload
{
	KTLog(QueueDomain, KTLogDebug, @"Dequeuing Download");
	DEQUEUE(_downloadQueue)
}

- (void)dequeueUpload
{
	KTLog(QueueDomain, KTLogDebug, @"Dequeuing Upload");
	DEQUEUE(_uploadQueue)
}

- (void)dequeueDeletion
{
	KTLog(QueueDomain, KTLogDebug, @"Dequeuing Deletion");
	DEQUEUE(_fileDeletes)
}

- (void)dequeueRename
{
	KTLog(QueueDomain, KTLogDebug, @"Dequeuing Rename");
	DEQUEUE(_fileRenames)
}

- (void)dequeuePermissionChange
{
	KTLog(QueueDomain, KTLogDebug, @"Dequeuing Permission Change");
	DEQUEUE(_filePermissions)
}

- (void)dequeueFileCheck
{
	KTLog(QueueDomain, KTLogDebug, @"Dequeuing File Check");
	DEQUEUE(_fileCheckQueue);
}

#define CURRENT_QUEUE(q) \
	[_queueLock lock]; \
	id obj = nil; \
	if ([q count] > 0) { \
		obj = [q objectAtIndex:0]; \
	} \
	[_queueLock unlock]; \
	return obj;

- (id)currentCommand
{
	CURRENT_QUEUE(_commandQueue);
}

- (id)currentDownload
{
	CURRENT_QUEUE(_downloadQueue);
}

- (id)currentUpload
{
	CURRENT_QUEUE(_uploadQueue);
}

- (id)currentDeletion
{
	CURRENT_QUEUE(_fileDeletes);
}

- (id)currentRename
{
	CURRENT_QUEUE(_fileRenames);
}

- (id)currentPermissionChange
{
	CURRENT_QUEUE(_filePermissions);
}

- (id)currentFileCheck
{
	CURRENT_QUEUE(_fileCheckQueue);
}

#define COUNT_QUEUE(q) [_queueLock lock]; unsigned count = [q count]; [_queueLock unlock]; return count;

- (unsigned)numberOfCommands
{
	COUNT_QUEUE(_commandQueue)
}

- (unsigned)numberOfDownloads
{
	COUNT_QUEUE(_downloadQueue)
}

- (unsigned)numberOfUploads
{
	COUNT_QUEUE(_uploadQueue)
}

- (unsigned)numberOfDeletions
{
	COUNT_QUEUE(_fileDeletes)
}

- (unsigned)numberOfRenames
{
	COUNT_QUEUE(_fileRenames)
}

- (unsigned)numberOfPermissionChanges
{
	COUNT_QUEUE(_filePermissions)
}

- (unsigned)numberOfTransfers
{
	return [self numberOfUploads] + [self numberOfDownloads];
}

- (unsigned)numberOfFileChecks
{
	COUNT_QUEUE(_fileCheckQueue);
}

#define MT_QUEUE(q) [_queueLock lock]; [q removeAllObjects]; [_queueLock unlock];

- (void)emptyCommandQueue
{
	KTLog(QueueDomain, KTLogDebug, @"Emptying Command Queue");
	MT_QUEUE(_commandQueue)
}

- (void)emptyDownloadQueue
{
	KTLog(QueueDomain, KTLogDebug, @"Emptying Download Queue");
	MT_QUEUE(_downloadQueue)
}

- (void)emptyUploadQueue
{
	KTLog(QueueDomain, KTLogDebug, @"Emptying Upload Queue");
	MT_QUEUE(_uploadQueue)
}

- (void)emptyDeletionQueue
{
	KTLog(QueueDomain, KTLogDebug, @"Emptying Deletion Queue");
	MT_QUEUE(_fileDeletes)
}

- (void)emptyRenameQueue
{
	KTLog(QueueDomain, KTLogDebug, @"Emptying Rename Queue");
	MT_QUEUE(_fileRenames)
}

- (void)emptyFileCheckQueue
{
	KTLog(QueueDomain, KTLogDebug, @"Emptying File Existence Queue");
	MT_QUEUE(_fileCheckQueue);
}

- (void)emptyPermissionChangeQueue
{
	KTLog(QueueDomain, KTLogDebug, @"Emptying Permission Change Queue");
	MT_QUEUE(_filePermissions)
}

- (void)emptyAllQueues
{
	KTLog(QueueDomain, KTLogDebug, @"Emptying All Queues");
	[_queueLock lock];
	[_commandQueue removeAllObjects];
	[_downloadQueue removeAllObjects];
	[_uploadQueue removeAllObjects];
	[_fileDeletes removeAllObjects];
	[_fileRenames removeAllObjects];
	[_filePermissions removeAllObjects];
	[_queueLock unlock];
}

@end

@implementation ConnectionCommand

+ (id)command:(id)type 
   awaitState:(ConnectionState)await
	sentState:(ConnectionState)sent
	dependant:(ConnectionCommand *)dep
	 userInfo:(id)ui
{
	return [ConnectionCommand command:type
						   awaitState:await
							sentState:sent
						   dependants:dep != nil ? [NSArray arrayWithObject:dep] : [NSArray array]
							 userInfo:ui];
}

+ (id)command:(id)type 
   awaitState:(ConnectionState)await
	sentState:(ConnectionState)sent
   dependants:(NSArray *)deps
	 userInfo:(id)ui
{
	return [[[ConnectionCommand alloc] initWithCommand:type
											awaitState:await
											 sentState:sent
											dependants:deps
											  userInfo:ui] autorelease];
}

- (id)initWithCommand:(id)type 
		   awaitState:(ConnectionState)await
			sentState:(ConnectionState)sent
		   dependants:(NSArray *)deps
			 userInfo:(id)ui
{
	if (self = [super init]) {
		_command = [type retain];
		_awaitState = await;
		_sentState = sent;
		_dependants = [[NSMutableArray arrayWithArray:deps] retain];
		_userInfo = [ui retain];
	}
	return self;
}

- (void)dealloc
{
	[_dependants release];
	[_userInfo release];
	[_command release];
	[super dealloc];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@", _command];
}

- (void)setCommand:(id)type
{
	[_command autorelease];
	_command = [type copy];
}

- (void)setAwaitState:(ConnectionState)await
{
	_awaitState = await;
}

- (void)setSentState:(ConnectionState)sent
{
	_sentState = sent;
}

- (void)setUserInfo:(id)ui
{
	[_userInfo autorelease];
	_userInfo = [ui retain];
}

- (id)command
{
	return _command;
}

- (ConnectionState)awaitState
{
	return _awaitState;
}

- (ConnectionState)sentState
{
	return _sentState;
}

- (id)userInfo
{
	return _userInfo;
}

- (void)addDependantCommand:(ConnectionCommand *)command
{
	[_dependants addObject:command];
}

- (void)removeDependantCommand:(ConnectionCommand *)command
{
	[_dependants removeObject:command];
}

- (NSArray *)dependantCommands
{
	return [NSArray arrayWithArray:_dependants];
}

@end


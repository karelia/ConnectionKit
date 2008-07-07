/*
 Copyright (c) 2005, Greg Hulands <ghulands@mac.com>
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
#import "NSObject+Connection.h"
#import "ConnectionThreadManager.h"
#import "CKTransferRecord.h"

//Download Queue Keys
NSString *QueueDownloadDestinationFileKey = @"QueueDownloadDestinationFileKey";
NSString *QueueDownloadRemoteFileKey = @"QueueDownloadRemoteFileKey";
NSString *QueueUploadLocalFileKey = @"QueueUploadLocalFileKey";
NSString *QueueUploadLocalDataKey = @"QueueUploadLocalDataKey";
NSString *QueueUploadRemoteFileKey = @"QueueUploadRemoteFileKey";
NSString *QueueUploadOffsetKey = @"QueueUploadOffsetKey";
NSString *QueueDownloadTransferPercentReceived = @"QueueDownloadTransferPercentReceived";

NSString *QueueDomain = @"Queuing";

#define QUEUE_HISTORY_COMMAND_SIZE 5

@interface NSObject (HistoryQueueSupport)
- (void)didPushToHistoryQueue;
@end

@implementation AbstractQueueConnection

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
			 error:(NSError **)error
{
	if (self = [super initWithHost:host port:port username:username password:password error:error])
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
#pragma mark Abstract Override

- (void)turnOnRecursiveUpload
{
	_flags.isRecursiveUploading = YES;
}

- (void)turnOffRecursiveUpload
{
	_flags.isRecursiveUploading = NO;
}

- (CKTransferRecord *)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(turnOnRecursiveUpload)
													  target:self
												   arguments:[NSArray array]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionIdleState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
	CKTransferRecord *rec = [super recursivelyUpload:localPath to:remotePath];
	
	inv = [NSInvocation invocationWithSelector:@selector(turnOffRecursiveUpload)
										target:self
									 arguments:[NSArray array]];
	cmd = [ConnectionCommand command:inv
						  awaitState:ConnectionIdleState
						   sentState:ConnectionIdleState
						   dependant:nil
							userInfo:nil];
	[self queueCommand:cmd];
	return rec;
}

- (void)threadedDisconnect
{
	[self emptyAllQueues];
	[super threadedDisconnect];
}

- (void)threadedForceDisconnect
{
	[self emptyAllQueues];
	[super threadedForceDisconnect];
}

- (void)threadedCancelAll
{
	[_queueLock lock];
	[_commandQueue removeAllObjects];
	[_queueLock unlock];
	[super threadedCancelAll];
}

- (BOOL)isBusy
{
	return ([self numberOfCommands] + [self numberOfDeletions] + [self numberOfPermissionChanges] + [self numberOfTransfers]) > 0;
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
	KTLog(QueueDomain, KTLogDebug, @"Pushing Command on History Queue: %@", [command shortDescription]);
	[_queueLock lock];
	[_commandHistory insertObject:command atIndex:0];
	
	// This is a framework internal "hack" to allow the webdav file upload request to release the data of a file
	if ([command isKindOfClass:[ConnectionCommand class]])
	{
		if ([[command command] respondsToSelector:@selector(didPushToHistoryQueue)])
		{
			[[command command] didPushToHistoryQueue];
		}
	}
	if (QUEUE_HISTORY_COMMAND_SIZE != 0 && [_commandHistory count] > QUEUE_HISTORY_COMMAND_SIZE)
	{
		[_commandHistory removeLastObject];
	}
	[_queueLock unlock];
}

- (void)pushCommandOnCommandQueue:(id)command
{
	KTLog(QueueDomain, KTLogDebug, @"Pushing Command on Command Queue: %@", [command shortDescription]);
	[_queueLock lock];
	[_commandQueue insertObject:command atIndex:0];
	[_queueLock unlock];
}

#pragma mark -
#pragma mark Queue Support

- (void)setState:(int)aState		// Safe "setter" -- do NOT just change raw variable.  Called by EITHER thread.
{
	KTLog(StateMachineDomain, KTLogDebug, @"Changing State from %@ to %@", [self stateName:_state], [self stateName:aState]);
	
    [super setState:aState];
	
	[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] checkQueue];
}

- (void)sendCommand:(id)command
{
	; //subclass to do work
}

- (BOOL)isCheckingQueue
{
	return myQueueFlags.isCheckingQueue;
}

- (void)checkQueue
{
	KTLog(StateMachineDomain, KTLogDebug, @"Checking Queue");
	[_queueLock lock];
	myQueueFlags.isCheckingQueue = YES;
	[_queueLock unlock];
	
	BOOL checkAgain = NO;
	do {
		BOOL nextTry = 0 != [self numberOfCommands];
		if (!nextTry)
		{
			KTLog(StateMachineDomain, KTLogDebug, @"Queue is Empty");
		}
		while (nextTry)
		{
			ConnectionCommand *command = [[self currentCommand] retain];
			if (command && GET_STATE == [command awaitState])
			{
				KTLog(StateMachineDomain, KTLogDebug, @"Dispatching Command: %@", [command command]);
				_state = [command sentState];	// don't use setter; we don't want to recurse
				[self pushCommandOnHistoryQueue:command];
				[self dequeueCommand];
				
				[self sendCommand:[command command]];
				
				// go to next one, there's something else to do
				[_queueLock lock];
				nextTry = [_commandQueue count] > 0; 
				if (!nextTry)
				{
					myQueueFlags.isCheckingQueue = NO;
				}
				[_queueLock unlock];
			}
			else
			{
				KTLog(StateMachineDomain, KTLogDebug, @"State %@ not ready for command at top of queue: %@, needs %@", [self stateName:GET_STATE], [command command], [self stateName:[command awaitState]]);
				nextTry = NO;		// don't try.  
			}
			[command release];
		}
		
		
		// It is possible that queueCommand: can be called while checkQueue is called
		// and queueCommand: will not call checkQueue because the value of myQueueFlags.isCheckingQueue
		// is YES. checkQueue, however, might have already checked the numberOfCommands and assigned
		// NO to nextTry BEFORE queueCommand: gets called (and queueCommand: gets called before
		// checkQueue reaches then end and sets isCheckingQueue to NO) which will lead to checkQueue
		// never being called for that newly added command. 
		// This simple check counting mechanism allows queueCommand to signal to checkQueue that a new
		// command has been added and the queue should be checked again. -- Seth Willits
		[_queueLock lock];
		checkAgain = (_checkQueueCount > 0);
		if (checkAgain)
		{
			_checkQueueCount--;
		}
		[_queueLock unlock];
		
	} while (checkAgain);
	
	
	[_queueLock lock];
	myQueueFlags.isCheckingQueue = NO;
	[_queueLock unlock];
	KTLog(StateMachineDomain, KTLogDebug, @"Done Checking Queue");
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
- (NSMutableArray *)uploadQueue
{
	return _uploadQueue;
}
- (NSMutableArray *)downloadQueue
{
	return _downloadQueue;
}
- (NSMutableArray *)commandQueue
{
	return _downloadQueue;
}
/* NOTE:  Not sure if we necessarily need this subclass override here. This does seem to fix an issue with file based connections, but until I have a chance to test it further, we'll leave it commented out.  -Brian Amerige 
- (void)startBulkCommands
{
	[super startBulkCommands];
	_openBulkCommands++;
}
- (void)endBulkCommands
{
	[super endBulkCommands];
	_openBulkCommands--;
	
	if (_openBulkCommands == 0 && ![self isCheckingQueue])
	{
		[self checkQueue];
	}
}*/

#define ADD_TO_QUEUE(queue, object) [_queueLock lock]; [queue addObject:object]; [_queueLock unlock];

- (void)queueCommand:(ConnectionCommand *)command
{
	[_queueLock lock];
	[_commandQueue addObject:command];
	KTLog(QueueDomain, KTLogDebug, @".. %@ (queue size now = %d)", [command command], [_commandQueue count]);		// show when a command gets queued
	[_queueLock unlock];
	
	BOOL isChecking;
	
	[_queueLock lock];
	isChecking = myQueueFlags.isCheckingQueue;
	
	// See checkQueue for an explanation of _checkQueueCount
	if (isChecking) {
		_checkQueueCount++;
	}
	[_queueLock unlock];
	
	if (!_flags.inBulk && !isChecking) {
		[[[ConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] checkQueue];
	}
}

- (void)queueDownload:(id)download
{
	KTLog(QueueDomain, KTLogDebug, @"Queuing Download: %@", [download shortDescription]);
	ADD_TO_QUEUE(_downloadQueue, download)
}

- (void)queueUpload:(id)upload
{
	KTLog(QueueDomain, KTLogDebug, @"Queueing Upload: %@", [upload shortDescription]);
	ADD_TO_QUEUE(_uploadQueue, upload)
}

- (void)queueDeletion:(id)deletion
{
	KTLog(QueueDomain, KTLogDebug, @"Queuing Deletion: %@", [deletion shortDescription]);
	ADD_TO_QUEUE(_fileDeletes, deletion)
}

- (void)queueRename:(id)name
{
	KTLog(QueueDomain, KTLogDebug, @"Queuing Rename: %@", [name shortDescription]);
	ADD_TO_QUEUE(_fileRenames, name)
}

- (void)queuePermissionChange:(id)perms
{
	KTLog(QueueDomain, KTLogDebug, @"Queuing Permission Change: %@", [perms shortDescription]);
	ADD_TO_QUEUE(_filePermissions, perms)
}

- (void)queueFileCheck:(id)file
{
	KTLog(QueueDomain, KTLogDebug, @"Queuing File Existence: %@", [file shortDescription]);
	ADD_TO_QUEUE(_fileCheckQueue, file);
}

#define DEQUEUE(q) [_queueLock lock]; if ([q count] > 0) [q removeObjectAtIndex:0]; [_queueLock unlock];

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
		obj = [[[q objectAtIndex:0] retain] autorelease]; \
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

@interface ConnectionCommand (Private)
- (void)setParentCommand:(ConnectionCommand *)cmd;
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
		[_dependants makeObjectsPerformSelector:@selector(setParentCommand:) withObject:self];
		_userInfo = [ui retain];
		_properties = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_dependants makeObjectsPerformSelector:@selector(setParentCommand:) withObject:nil];
	[_dependants release];
	[_userInfo release];
	[_command release];
	[_properties release];
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

- (void)setProperty:(id)property forKey:(NSString *)key
{
	[_properties setObject:property forKey:key];
}

- (id)propertyForKey:(NSString *)key
{
	return [_properties objectForKey:key];
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
	[command setParentCommand:self];
	[_dependants addObject:command];
}

- (void)removeDependantCommand:(ConnectionCommand *)command
{
	[command setParentCommand:nil];
	[_dependants removeObject:command];
}

- (NSArray *)dependantCommands
{
	return [NSArray arrayWithArray:_dependants];
}

- (void)setParentCommand:(ConnectionCommand *)cmd
{
	_parent = cmd;
}

- (ConnectionCommand *)parentCommand
{
	return _parent;
}

- (ConnectionCommand *)firstCommandInChain
{
	if (_parent)
		return [_parent firstCommandInChain];
	return self;
}

- (void)recursivelyAddedSequencedCommand:(ConnectionCommand *)cmd toSequence:(NSMutableArray *)sequence
{
	[sequence addObject:cmd];
	NSEnumerator *e = [[cmd dependantCommands] objectEnumerator];
	ConnectionCommand *cur;
	
	while (cur = [e nextObject])
	{
		[self recursivelyAddedSequencedCommand:cur toSequence:sequence];
	}
}

- (NSArray *)sequencedChain
{
	NSMutableArray *sequence = [NSMutableArray array];
	
	ConnectionCommand *first = [self firstCommandInChain];
	
	[self recursivelyAddedSequencedCommand:first toSequence:sequence];
	
	return sequence;
}

@end


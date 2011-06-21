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

#import "CKAbstractQueueConnection.h"
#import "NSObject+Connection.h"
#import "CKConnectionThreadManager.h"
#import "CKTransferRecord.h"

//Download Queue Keys
NSString *CKQueueDownloadDestinationFileKey = @"QueueDownloadDestinationFileKey";
NSString *CKQueueDownloadRemoteFileKey = @"QueueDownloadRemoteFileKey";
NSString *CKQueueUploadLocalFileKey = @"QueueUploadLocalFileKey";
NSString *CKQueueUploadLocalDataKey = @"QueueUploadLocalDataKey";
NSString *CKQueueUploadRemoteFileKey = @"QueueUploadRemoteFileKey";
NSString *CKQueueUploadOffsetKey = @"QueueUploadOffsetKey";
NSString *CKQueueDownloadTransferPercentReceived = @"QueueDownloadTransferPercentReceived";

NSString *CKQueueDomain = @"Queuing";

#define QUEUE_HISTORY_COMMAND_SIZE 5

@interface NSObject (HistoryQueueSupport)
- (void)didPushToHistoryQueue;
@end

@implementation CKAbstractQueueConnection

- (id)initWithRequest:(CKConnectionRequest *)request
{
	if (self = [super initWithRequest:request])
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
	_isRecursiveUploading = YES;
}

- (void)turnOffRecursiveUpload
{
	_isRecursiveUploading = NO;
}

- (CKTransferRecord *)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(turnOnRecursiveUpload)
													  target:self
												   arguments:[NSArray array]];
	CKConnectionCommand *cmd = [CKConnectionCommand command:inv
											 awaitState:CKConnectionIdleState
											  sentState:CKConnectionIdleState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
	CKTransferRecord *rec = [super recursivelyUpload:localPath to:remotePath];
	
	inv = [NSInvocation invocationWithSelector:@selector(turnOffRecursiveUpload)
										target:self
									 arguments:[NSArray array]];
	cmd = [CKConnectionCommand command:inv
						  awaitState:CKConnectionIdleState
						   sentState:CKConnectionIdleState
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
	KTLog(CKQueueDomain, KTLogDebug, @"Pushing Command on History Queue: %@", [command shortDescription]);
	[_queueLock lock];
	[_commandHistory insertObject:command atIndex:0];
	
	// This is a framework internal "hack" to allow the webdav file upload request to release the data of a file
	if ([command isKindOfClass:[CKConnectionCommand class]])
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
	KTLog(CKQueueDomain, KTLogDebug, @"Pushing Command on Command Queue: %@", [command shortDescription]);
	[_queueLock lock];
	[_commandQueue insertObject:command atIndex:0];
	[_queueLock unlock];
}

#pragma mark -
#pragma mark Queue Support

- (void)setState:(CKConnectionState)aState		// Safe "setter" -- do NOT just change raw variable.  Called by EITHER thread.
{
	KTLog(CKStateMachineDomain, KTLogDebug, @"Changing State from %@ to %@", [self stateName:_state], [self stateName:aState]);
	
    [super setState:aState];
	
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] checkQueue];
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
	KTLog(CKStateMachineDomain, KTLogDebug, @"Checking Queue");
	[_queueLock lock];
	myQueueFlags.isCheckingQueue = YES;
	[_queueLock unlock];
	
	BOOL checkAgain = NO;
	do {
		BOOL nextTry = 0 != [self numberOfCommands];
		if (!nextTry)
		{
			KTLog(CKStateMachineDomain, KTLogDebug, @"Queue is Empty");
		}
		while (nextTry)
		{
			CKConnectionCommand *command = [[self currentCommand] retain];
			if (command && GET_STATE == [command awaitState])
			{
				KTLog(CKStateMachineDomain, KTLogDebug, @"Dispatching Command: %@", [command command]);
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
				KTLog(CKStateMachineDomain, KTLogDebug, @"State %@ not ready for command at top of queue: %@, needs %@", [self stateName:GET_STATE], [command command], [self stateName:[command awaitState]]);
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
	KTLog(CKStateMachineDomain, KTLogDebug, @"Done Checking Queue");
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

- (void)queueCommand:(CKConnectionCommand *)command
{
	[_queueLock lock];
	[_commandQueue addObject:command];
	KTLog(CKQueueDomain, KTLogDebug, @".. %@ (queue size now = %d)", [command command], [_commandQueue count]);		// show when a command gets queued
	[_queueLock unlock];
	
	BOOL isChecking;
	
	[_queueLock lock];
	isChecking = myQueueFlags.isCheckingQueue;
	
	// See checkQueue for an explanation of _checkQueueCount
	if (isChecking) {
		_checkQueueCount++;
	}
	[_queueLock unlock];
	
	if (!_inBulk && !isChecking) {
		[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] checkQueue];
	}
}

- (void)queueDownload:(id)download
{
	KTLog(CKQueueDomain, KTLogDebug, @"Queuing Download: %@", [download shortDescription]);
	ADD_TO_QUEUE(_downloadQueue, download)
}

- (void)queueUpload:(id)upload
{
	KTLog(CKQueueDomain, KTLogDebug, @"Queueing Upload: %@", [upload shortDescription]);
	ADD_TO_QUEUE(_uploadQueue, upload)
}

- (void)queueDeletion:(id)deletion
{
	KTLog(CKQueueDomain, KTLogDebug, @"Queuing Deletion: %@", [deletion shortDescription]);
	ADD_TO_QUEUE(_fileDeletes, deletion)
}

- (void)queueRename:(id)name
{
	KTLog(CKQueueDomain, KTLogDebug, @"Queuing Rename: %@", [name shortDescription]);
	ADD_TO_QUEUE(_fileRenames, name)
}

- (void)queuePermissionChange:(id)perms
{
	KTLog(CKQueueDomain, KTLogDebug, @"Queuing Permission Change: %@", [perms shortDescription]);
	ADD_TO_QUEUE(_filePermissions, perms)
}

- (void)queueFileCheck:(id)file
{
	KTLog(CKQueueDomain, KTLogDebug, @"Queuing File Existence: %@", [file shortDescription]);
	ADD_TO_QUEUE(_fileCheckQueue, file);
}

#define DEQUEUE(q) [_queueLock lock]; if ([q count] > 0) [q removeObjectAtIndex:0]; [_queueLock unlock];

- (void)dequeueCommand
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing Command");
	DEQUEUE(_commandQueue)
}

- (void)dequeueDownload
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing Download");
	DEQUEUE(_downloadQueue)
}

- (void)dequeueUpload
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing Upload");
	DEQUEUE(_uploadQueue)
}

- (void)dequeueDeletion
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing Deletion");
	DEQUEUE(_fileDeletes)
}

- (void)dequeueRename
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing Rename");
	DEQUEUE(_fileRenames)
}

- (void)dequeuePermissionChange
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing Permission Change");
	DEQUEUE(_filePermissions)
}

- (void)dequeueFileCheck
{
	KTLog(CKQueueDomain, KTLogDebug, @"Dequeuing File Check");
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
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying Command Queue");
	MT_QUEUE(_commandQueue)
}

- (void)emptyDownloadQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying Download Queue");
	MT_QUEUE(_downloadQueue)
}

- (void)emptyUploadQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying Upload Queue");
	MT_QUEUE(_uploadQueue)
}

- (void)emptyDeletionQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying Deletion Queue");
	MT_QUEUE(_fileDeletes)
}

- (void)emptyRenameQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying Rename Queue");
	MT_QUEUE(_fileRenames)
}

- (void)emptyFileCheckQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying File Existence Queue");
	MT_QUEUE(_fileCheckQueue);
}

- (void)emptyPermissionChangeQueue
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying Permission Change Queue");
	MT_QUEUE(_filePermissions)
}

- (void)emptyAllQueues
{
	KTLog(CKQueueDomain, KTLogDebug, @"Emptying All Queues");
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

@interface CKConnectionCommand (Private)
- (void)setParentCommand:(CKConnectionCommand *)cmd;
@end

@implementation CKConnectionCommand

+ (id)command:(id)type 
   awaitState:(CKConnectionState)await
	sentState:(CKConnectionState)sent
	dependant:(CKConnectionCommand *)dep
	 userInfo:(id)ui
{
	return [CKConnectionCommand command:type
						   awaitState:await
							sentState:sent
						   dependants:dep != nil ? [NSArray arrayWithObject:dep] : [NSArray array]
							 userInfo:ui];
}

+ (id)command:(id)type 
   awaitState:(CKConnectionState)await
	sentState:(CKConnectionState)sent
   dependants:(NSArray *)deps
	 userInfo:(id)ui
{
	return [[[CKConnectionCommand alloc] initWithCommand:type
											awaitState:await
											 sentState:sent
											dependants:deps
											  userInfo:ui] autorelease];
}

- (id)initWithCommand:(id)type 
		   awaitState:(CKConnectionState)await
			sentState:(CKConnectionState)sent
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

- (void)setAwaitState:(CKConnectionState)await
{
	_awaitState = await;
}

- (void)setSentState:(CKConnectionState)sent
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

- (CKConnectionState)awaitState
{
	return _awaitState;
}

- (CKConnectionState)sentState
{
	return _sentState;
}

- (id)userInfo
{
	return _userInfo;
}

- (void)addDependantCommand:(CKConnectionCommand *)command
{
	[command setParentCommand:self];
	[_dependants addObject:command];
}

- (void)removeDependantCommand:(CKConnectionCommand *)command
{
	[command setParentCommand:nil];
	[_dependants removeObject:command];
}

- (NSArray *)dependantCommands
{
	return [NSArray arrayWithArray:_dependants];
}

- (void)setParentCommand:(CKConnectionCommand *)cmd
{
	_parent = cmd;
}

- (CKConnectionCommand *)parentCommand
{
	return _parent;
}

- (CKConnectionCommand *)firstCommandInChain
{
	if (_parent)
		return [_parent firstCommandInChain];
	return self;
}

- (void)recursivelyAddedSequencedCommand:(CKConnectionCommand *)cmd toSequence:(NSMutableArray *)sequence
{
	[sequence addObject:cmd];
	NSEnumerator *e = [[cmd dependantCommands] objectEnumerator];
	CKConnectionCommand *cur;
	
	while (cur = [e nextObject])
	{
		[self recursivelyAddedSequencedCommand:cur toSequence:sequence];
	}
}

- (NSArray *)sequencedChain
{
	NSMutableArray *sequence = [NSMutableArray array];
	
	CKConnectionCommand *first = [self firstCommandInChain];
	
	[self recursivelyAddedSequencedCommand:first toSequence:sequence];
	
	return sequence;
}

@end


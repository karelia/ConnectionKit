/*
 Copyright (c) 2005-2006, Greg Hulands <ghulands@mac.com>
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

#import <Foundation/Foundation.h>
#import <Connection/AbstractConnection.h>

/*
 *	The ConnectionCommand class is used to queue up related commands into chains in the commandQueue.
 *	What this means is that if you are wanting to perform an upload and set the permissions on that 
 *	file, but the file exists and it is set to ask for confirmation, if it stalls at waiting for the 
 *	user to confirm to overwrite, then you don't want the permissions to set the existing file that 
 *  exists. So when in that state what will happen is that the command for the upload will be put into
 *	the confirmation dictionary so that when the user responds with what to do we can continue that 
 *  chain of commands out of sequence. Basically means it is Async.
 */

@interface ConnectionCommand : NSObject
{
	id				_command;
	NSMutableArray	*_dependants; 
	ConnectionState _awaitState;
	ConnectionState _sentState;
	id				_userInfo;
	ConnectionCommand *_parent;			// weak reference
	NSMutableDictionary *_properties;
}

+ (id)command:(id)type 
   awaitState:(ConnectionState)await
	sentState:(ConnectionState)sent
	dependant:(ConnectionCommand *)dep
	 userInfo:(id)ui;

+ (id)command:(id)type 
   awaitState:(ConnectionState)await
	sentState:(ConnectionState)sent
   dependants:(NSArray *)deps
	 userInfo:(id)ui;

- (id)initWithCommand:(id)type 
		   awaitState:(ConnectionState)await
			sentState:(ConnectionState)sent
		   dependants:(NSArray *)deps
			 userInfo:(id)ui;

- (void)setCommand:(id)type;
- (void)setAwaitState:(ConnectionState)await;
- (void)setSentState:(ConnectionState)sent;
- (void)setUserInfo:(id)ui;
- (id)command;
- (ConnectionState)awaitState;
- (ConnectionState)sentState;
- (id)userInfo;

- (void)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;

- (void)addDependantCommand:(ConnectionCommand *)command;
- (void)removeDependantCommand:(ConnectionCommand *)command;
- (NSArray *)dependantCommands;

// returns the sequence of execution of commands
- (NSArray *)sequencedChain;

@end

extern NSString *QueueDomain;

@interface AbstractQueueConnection : AbstractConnection 
{
	NSRecursiveLock		*_queueLock;
	int					_checkQueueCount;
	int					_openBulkCommands;
	// Queue Support
	NSMutableArray		*_commandHistory;
	NSMutableArray		*_commandQueue;
	NSMutableArray		*_downloadQueue;
	NSMutableArray		*_uploadQueue;
	NSMutableArray		*_fileDeletes;
	NSMutableArray		*_filePermissions;
	NSMutableArray		*_fileRenames;
	NSMutableArray		*_fileCheckQueue;
	NSMutableDictionary	*_filesNeedingOverwriteConfirmation;
	
	struct __aqc_flags {
		unsigned isCheckingQueue: 1;
		unsigned usued: 29;
	} myQueueFlags;
}

- (void)checkQueue;
- (BOOL)isCheckingQueue;

//Queue Accessors
- (NSMutableArray *)uploadQueue;
- (NSMutableArray *)downloadQueue;
- (NSMutableArray *)commandQueue;	

//Command History
- (id)lastCommand;
- (NSArray *)commandHistory;
- (void)pushCommandOnHistoryQueue:(id)command;
- (void)pushCommandOnCommandQueue:(id)command; //places it at the head of the queue

// Queue Support
- (void)queueCommand:(ConnectionCommand *)command;
- (void)queueDownload:(id)download;
- (void)queueUpload:(id)upload;
- (void)queueDeletion:(id)deletion;
- (void)queueRename:(id)name;
- (void)queuePermissionChange:(id)perms;
- (void)queueFileCheck:(id)file;

- (void)dequeueCommand;
- (void)dequeueDownload;
- (void)dequeueUpload;
- (void)dequeueDeletion;
- (void)dequeueRename;
- (void)dequeuePermissionChange;
- (void)dequeueFileCheck;

- (id)currentCommand;
- (id)currentDownload;
- (id)currentUpload;
- (id)currentDeletion;
- (id)currentRename;
- (id)currentPermissionChange;
- (id)currentFileCheck;

- (unsigned)numberOfCommands;
- (unsigned)numberOfDownloads;
- (unsigned)numberOfUploads;
- (unsigned)numberOfDeletions;
- (unsigned)numberOfRenames;
- (unsigned)numberOfPermissionChanges;
- (unsigned)numberOfFileChecks;

- (void)emptyCommandQueue;
- (void)emptyDownloadQueue;
- (void)emptyUploadQueue;
- (void)emptyDeletionQueue;
- (void)emptyRenameQueue;
- (void)emptyPermissionChangeQueue;
- (void)emptyFileCheckQueue;
- (void)emptyAllQueues;

// Testing
- (NSString *)queueDescription;

@end

//Upload/Download Queue Keys
extern NSString *QueueDownloadDestinationFileKey;
extern NSString *QueueDownloadRemoteFileKey;
extern NSString *QueueUploadLocalFileKey;
extern NSString *QueueUploadLocalDataKey;
extern NSString *QueueUploadRemoteFileKey;
extern NSString *QueueUploadOffsetKey;
extern NSString *QueueDownloadTransferPercentReceived;

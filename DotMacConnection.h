/*

  DotMacConnection.h
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

#import <Cocoa/Cocoa.h>
#import <DotMacKit/DotMacKit.h>

#import "AbstractConnection.h"

extern NSString *kDAVErrorDomain;
extern NSString *kDAVDoesNotImplementException;
extern NSString *kDAVInvalidSessionException;

enum { kDMOverwriteFileError = 60, kInvalidSession };

@class RunLoopForwarder; 

@interface DotMacConnection : AbstractConnection
{
    @protected
	NSThread		*_bgThread;
	NSPort			*myPort;
	NSLock			*myLock;
	RunLoopForwarder*myForwarder;
	
    DMiDiskSession  *myDMiDiskSession;
	DMiDiskSession	*mySyncPeer;
    DMMemberAccount *myAccount;

    NSString        *myCurrentDirectory;

    NSMutableArray  *myPendingInvocations;
    NSMutableArray  *myPendingTransactions;
    DMTransaction   *myInFlightTransaction;
    DMTransaction   *myLastProcessedTransaction;    // not retained

    int myUploadPercent;
    int myDownloadPercent;
	unsigned long long myLastTransferBytes;

    BOOL _transactionInProgress;

}

#pragma mark AbstractConnectionProtocol class methods

+ (NSString *)name;

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password;

#pragma mark AbstractConnectionProtocol instance methods

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password;

- (void)connect;
- (void)disconnect;
- (void)changeToDirectory:(NSString *)dirPath;

- (void)createDirectory:(NSString *)dirPath;
- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions;
- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path;

- (void)rename:(NSString *)fromPath to:(NSString *)toPath;
- (void)deleteFile:(NSString *)path;
- (void)deleteDirectory:(NSString *)dirPath;

- (void)uploadFile:(NSString *)localPath;
- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath;
- (void)resumeUploadFile:(NSString *)localPath fileOffset:(long long)offset;
- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(long long)offset;
- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath;
- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(long long)offset;

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag;
- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(long long)offset;

- (unsigned)numberOfTransfers;
- (void)cancelTransfer;
- (void)cancelAll;

- (void)directoryContents;
- (void)contentsOfDirectory:(NSString *)dirPath;

#pragma mark AbstractConnectionProtocol accessors

- (NSString *)currentDirectory;

#pragma mark additional accessors

- (id)account;

- (DMiDiskSession *)DMiDiskSession;
- (NSMutableArray *)pendingInvocations;
- (NSMutableArray *)pendingTransactions;

- (DMTransaction *)inFlightTransaction;
- (DMTransaction *)lastProcessedTransaction;
- (BOOL)transactionInProgress;

#pragma mark DMTransaction-like methods

// synchronous, messages DMiDiskSession immediately
- (int)validateAccess;

// synchronous checking for existence of path, asychronous creation of path
//- (void)makeCollectionAtPath:(NSString *)dirPath createParents:(BOOL)flag userInfo:(id)userInfo;

// asynchronous, the delegate is notified via AbstractConnectionDelegate informal protocol
- (void)listCollectionAtPath:(NSString *)thePath userInfo:(id)userInfo;
- (void)makeCollectionAtPath:(NSString *)dirPath userInfo:(id)userInfo;

- (void)deleteResourceAtPath:(NSString *)thePath userInfo:(id)userInfo;
- (void)moveResourceAtPath:(NSString *)sourcePath toPath:(NSString *)destinationPath userInfo:(id)userInfo;

- (void)putData:(NSData *)data toPath:(NSString *)destinationPath userInfo:(id)userInfo;
- (void)putLocalFileAtPath:(NSString *)localPath toPath:(NSString *)destinationPath userInfo:(id)userInfo;

- (void)getRemoteFileAtPath:(NSString *)remotePath toPath:(NSString *)localPath userInfo:(id)userInfo;

#pragma mark support

// synchronous, convenience methods used for testing
- (BOOL)hasValidiDiskSession;
- (BOOL)resourceExistsAtPath:(NSString *)aPath;

- (BOOL)fileExistsAtPath:(NSString *)aPath;
- (BOOL)directoryExistsAtPath:(NSString *)aPath;

@end

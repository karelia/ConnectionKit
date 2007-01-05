/*
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
#import <Cocoa/Cocoa.h>

#define LocalizedStringInThisBundle(key, comment) \
[[NSBundle bundleForClass:[self class]] localizedStringForKey:(key) value:@"" table:nil]

@class CKTransferRecord;

// Some shared Error Codes

enum {
	ConnectionErrorUploading = 49101,
	ConnectionErrorDownloading,
	ConnectionErrorCreatingDirectory,
	ConnectionErrorChangingDirectory
};

typedef struct __flags {
	unsigned isConnected:1;
	
	// There are 21 callbacks & flags.
	// Need to keep NSObject Category, __flags list, setDelegate: updated
	
	unsigned permissions:1;
	unsigned badPassword:1;
	unsigned cancel:1;
	unsigned changeDirectory:1;
	unsigned createDirectory:1;
	unsigned deleteDirectory:1;
	unsigned deleteFile:1;
	unsigned didBeginUpload:1;
	unsigned didConnect:1;
	unsigned didDisconnect:1;
	unsigned directoryContents:1;
	unsigned didBeginDownload:1;
	unsigned downloadFinished:1;
	unsigned downloadPercent:1;
	unsigned downloadProgressed:1;
	unsigned error:1;
	unsigned needsAccount:1;
	unsigned rename:1;
	unsigned uploadFinished:1;
	unsigned uploadPercent:1;
	unsigned uploadProgressed:1;
	unsigned directoryContentsStreamed:1;
	unsigned inBulk:1;
	unsigned fileCheck:1;
	unsigned authorizeConnection:1;
	unsigned isRecursiveUploading:1;
	unsigned isRecursiveDeleting:1;
	
	unsigned padding:4;
} connectionFlags;


@protocol AbstractConnectionProtocol <NSObject>

+ (NSString *)name;


+ (id <AbstractConnectionProtocol>)connectionToHost:(NSString *)host
											   port:(NSString *)port
										   username:(NSString *)username
										   password:(NSString *)password
											  error:(NSError **)error;

+ (id <AbstractConnectionProtocol>)connectionWithURL:(NSURL *)url error:(NSError **)error;

+ (id <AbstractConnectionProtocol>)connectionWithName:(NSString *)name
												 host:(NSString *)host
												 port:(NSString *)port
											 username:(NSString *)username
											 password:(NSString *)password
												error:(NSError **)error;

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
			 error:(NSError **)error;

- (void)setHost:(NSString *)host;
- (void)setPort:(NSString *)port;
- (void)setUsername:(NSString *)username;
- (void)setPassword:(NSString *)password;

- (NSString *)host;
- (NSString *)port;
- (NSString *)username;
- (NSString *)password;

- (void)setDelegate:(id)delegate;   // we do not retain the delegate
- (id)delegate;

- (void)connect;
- (BOOL)isConnected;

/* disconnect queues a disconnection where as forceDisconnect '
   will terminate at the next available opportunity. */
- (void)disconnect;
- (void)forceDisconnect;
- (void) cleanupConnection;

- (void)changeToDirectory:(NSString *)dirPath;
- (NSString *)currentDirectory;

- (NSString *)rootDirectory;
- (void)createDirectory:(NSString *)dirPath;
- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions;
- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path;

- (void)rename:(NSString *)fromPath to:(NSString *)toPath;
- (void)deleteFile:(NSString *)path;
- (void)deleteDirectory:(NSString *)dirPath;
- (void)recursivelyDeleteDirectory:(NSString *)path;

- (void)startBulkCommands;
- (void)endBulkCommands;

- (void)uploadFile:(NSString *)localPath;
- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath;
- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag;
/* 
	New method that allows you to set a custom delegate for the upload.
	You must implement the ConnectionTransferDelegate informal protocol.
	By default the transfer record returned is the delegate of the transfer.
*/
- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate;
/* 
	returns CKTransferRecord as a heirarchy of what will be upload, remote and local files 
	can be found in the records node properties
*/
- (CKTransferRecord *)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath;

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(unsigned long long)offset;
- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset;

- (CKTransferRecord *)resumeUploadFile:(NSString *)localPath 
								toFile:(NSString *)remotePath 
							fileOffset:(unsigned long long)offset
							  delegate:(id)delegate;


- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath;
- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag;

/* 
	New method that allows you to set a custom delegate for the upload.
	You must implement the ConnectionTransferDelegate informal protocol.
	By default the transfer record returned is the delegate of the transfer.
*/
- (CKTransferRecord *)uploadFromData:(NSData *)data
							  toFile:(NSString *)remotePath 
				checkRemoteExistence:(BOOL)flag
							delegate:(id)delegate;

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(unsigned long long)offset;

- (CKTransferRecord *)resumeUploadFromData:(NSData *)data
									toFile:(NSString *)remotePath 
								fileOffset:(unsigned long long)offset
								  delegate:(id)delegate;

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag;
- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(unsigned long long)offset;

/* 
	New method that allows you to set a custom delegate for the download.
	You must implement the ConnectionTransferDelegate informal protocol.
	By default the transfer record returned is the delegate of the transfer.
*/
- (CKTransferRecord *)downloadFile:(NSString *)remotePath 
					   toDirectory:(NSString *)dirPath 
						 overwrite:(BOOL)flag
						  delegate:(id)delegate;

- (CKTransferRecord *)resumeDownloadFile:(NSString *)remotePath
							 toDirectory:(NSString *)dirPath
							  fileOffset:(unsigned long long)offset
								delegate:(id)delegate;

- (void)checkExistenceOfPath:(NSString *)path;

- (unsigned)numberOfTransfers;
- (void)cancelTransfer;
- (void)cancelAll;

- (void)directoryContents;
- (void)contentsOfDirectory:(NSString *)dirPath;

- (void)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;

- (void)setTranscript:(NSTextStorage *)transcript;

- (double)uploadSpeed; // bytes per second
- (double)downloadSpeed;

- (NSString *)urlScheme; // by default calls class method
+ (NSString *)urlScheme; //eg http

- (void)editFile:(NSString *)remoteFile;

@end



@interface NSObject (AbstractConnectionDelegate)

// There are 21 callbacks & flags.
// Need to keep NSObject Category, __flags list, setDelegate: updated

- (void)connection:(id <AbstractConnectionProtocol>)con didChangeToDirectory:(NSString *)dirPath;
- (BOOL)connection:(id <AbstractConnectionProtocol>)con authorizeConnectionToHost:(NSString *)host message:(NSString *)message;
- (void)connection:(id <AbstractConnectionProtocol>)con didConnectToHost:(NSString *)host;
- (void)connection:(id <AbstractConnectionProtocol>)con didCreateDirectory:(NSString *)dirPath;
- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteDirectory:(NSString *)dirPath;
- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteFile:(NSString *)path;
- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host;
- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath;
- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath moreComing:(BOOL)flag;
- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveError:(NSError *)error;
- (void)connection:(id <AbstractConnectionProtocol>)con didRename:(NSString *)fromPath to:(NSString *)toPath;
- (void)connection:(id <AbstractConnectionProtocol>)con didSetPermissionsForFile:(NSString *)path;
- (void)connection:(id <AbstractConnectionProtocol>)con download:(NSString *)path progressedTo:(NSNumber *)percent;
- (void)connection:(id <AbstractConnectionProtocol>)con download:(NSString *)path receivedDataOfLength:(unsigned long long)length; 
- (void)connection:(id <AbstractConnectionProtocol>)con downloadDidBegin:(NSString *)remotePath;
- (void)connection:(id <AbstractConnectionProtocol>)con downloadDidFinish:(NSString *)remotePath;
- (NSString *)connection:(id <AbstractConnectionProtocol>)con needsAccountForUsername:(NSString *)username;
- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath progressedTo:(NSNumber *)percent;
- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath sentDataOfLength:(unsigned long long)length;
- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidBegin:(NSString *)remotePath;
- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidFinish:(NSString *)remotePath;
- (void)connectionDidCancelTransfer:(id <AbstractConnectionProtocol>)con;
- (void)connectionDidSendBadPassword:(id <AbstractConnectionProtocol>)con;
- (void)connection:(id <AbstractConnectionProtocol>)con checkedExistenceOfPath:(NSString *)path pathExists:(BOOL)exists;
@end

@interface NSObject (ConnectionTransferDelegate)
- (void)transferDidBegin:(CKTransferRecord *)transfer;
- (void)transfer:(CKTransferRecord *)transfer transferredDataOfLength:(unsigned long long)length;
- (void)transfer:(CKTransferRecord *)transfer progressedTo:(NSNumber *)percent;
- (void)transfer:(CKTransferRecord *)transfer receivedError:(NSError *)error;
- (void)transferDidFinish:(CKTransferRecord *)transfer;
@end

//registration type dictionary keys
extern NSString *ACTypeKey;
extern NSString *ACTypeValueKey;
extern NSString *ACPortTypeKey;
extern NSString *ACURLTypeKey; /* ftp://, http://, etc */

// Attributes for which there isn't a corresponding NSFileManager key
extern NSString *cxFilenameKey;
extern NSString *cxSymbolicLinkTargetKey;

//User Info Keys for Errors
extern NSString *ConnectionDirectoryExistsKey;
extern NSString *ConnectionDirectoryExistsFilenameKey;

/*
 * The InputStream and OutputStream protocols, provides a transparent way to interchange
 * the implementation specific streams.
 */
@protocol InputStream <NSObject>
- (void)open;
- (void)close;
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)setDelegate:(id)delegate;
- (id)delegate;
- (BOOL)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (NSError *)streamError;
- (NSStreamStatus)streamStatus;
- (BOOL)hasBytesAvailable;
- (int)read:(uint8_t *)buffer maxLength:(unsigned int)len;
@end

@protocol OutputStream <NSObject>
- (void)open;
- (void)close;
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)setDelegate:(id)delegate;
- (id)delegate;
- (BOOL)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (NSError *)streamError;
- (NSStreamStatus)streamStatus;

- (int)write:(const uint8_t *)buffer maxLength:(unsigned int)len;
@end

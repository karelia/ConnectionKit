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
#import "CKConnectionRequest.h"

#define LocalizedStringInConnectionKitBundle(key, comment) \
[[NSBundle bundleForClass:[self class]] localizedStringForKey:(key) value:@"" table:nil]


@class CKTransferRecord;

// Some shared Error Codes
enum {
	ConnectionErrorUploading = 49101,
	ConnectionErrorDownloading,
	ConnectionErrorCreatingDirectory,
	ConnectionErrorChangingDirectory,
	ConnectionErrorDeleting,
	ConnectionErrorConnecting,
	ConnectionErrorDisconnecting,
	ConnectionErrorUnexpectedlyDisconnected,
	ConnectionErrorListingDirectory,
	ConnectionErrorGeneric,
};

typedef enum {
	CKTranscriptSent,
	CKTranscriptReceived,
	CKTranscriptData,
} CKTranscriptType;

typedef enum
{
	CKFTPProtocol = 0,
	CKSFTPProtocol,
	CKWebDAVProtocol,
	CKMobileMeProtocol,
	CKAmazonS3Protocol,
	CKFileProtocol,
	
	//Incomplete protocols
	CKFTPOverSSLProtocol,
	CKSecureWebDAVProtocol,
	CKNNTPProtocol,
} CKProtocol;


@protocol CKConnection <NSObject>

+ (CKProtocol)protocol;

/*!
 @method URLSchemes
 @result An array of the URL schemes supported by the connection.
 */
+ (NSArray *)URLSchemes;

/*!
 @method port
 @discussion Return 0 for abstract classes or connections that do not use a port.
 @result The default port for connections of the receiver's class.
 */
+ (NSInteger)defaultPort;


/*!
 @method initWithRequest:
 @abstract The designated initializer for connections.
 @param request The request to connect with. The request object is deep-copied as part of the
 initialization process. Changes made to request after this method returns do not affect the request
 that is used for the loading process.
 @result Returns an initialized connection object or nil if the request was unsuitable.
 */
- (id)initWithRequest:(CKConnectionRequest *)request;


/*!
 @method request
 @discussion Please do NOT modify this request in any way!
 @result Returns the request supplied when creating the connection.
 */
- (CKConnectionRequest *)request;


// you can set a name on a connection to help with debugging.
// TODO: Should this really be part of the protocol, or a CKAbstractConnection implementation detail?
- (NSString *)name; 
- (void)setName:(NSString *)name;

/*!
 @method delegate:
 @result Returns the receiver's delegate.
 */
- (id)delegate;
/*!
 @method setDelegate:
 @abstract Sets the receiver's delegate.
 @discussion The delegate is not retained. The delegate should implement any of the methods in the CKConnectionDelegate informal protocol to receive callbacks when connection events occur.
 */
- (void)setDelegate:(id)delegate;

/*!
 @method setProperty:forKey:
 @abstract Adds a given key-value pair to the receiver.
 @param property The value for key.
 @param key The key for value. Note that when using key-value coding, the key must be a string (see Key-Value Coding Fundamentals).
 @discussion Raises an NSInvalidArgumentException if key or property is nil. If you need to represent a nil value in the receiver, use NSNull. If key already exists in the receiver, the receiver’s previous value object for that key is sent a release message and object takes its place.
 */
- (void)setProperty:(id)property forKey:(id)key;

/*!
 @method propertyForKey:
 @abstract Returns the value associated with a given key.
 @param propertyKey The key for which to return the corresponding value.
 @return The value associated with aKey, or nil if no value is associated with aKey.
 */
- (id)propertyForKey:(id)propertyKey;

/*!
 @method removePropertyForKey:
 @abstract Removes the key-value pair associated with key.
 @param key The key whose key-value pair should be removed.
 */
- (void)removePropertyForKey:(id)key;

/*!
 @method connect
 @abstract Causes the receiver to start the connection, if it has not already. This is generally asynchronous.
 */
- (void)connect;
/*!
 @method isConnected
 @result Returns YES once the connection has successfully connected to the server
 */
- (BOOL)isConnected;
- (BOOL)isBusy;

 
/*!
 @method disconnect
 @abstract Ends the connection after any other items in the queue have been processed.
 */
- (void)disconnect;
/*!
 @method forceDisconnect
 @abstract Ends the connection at the next available opportunity.
 */
- (void)forceDisconnect;
- (void)cleanupConnection;

- (void)changeToDirectory:(NSString *)dirPath;
- (NSString *)currentDirectory;

- (NSString *)rootDirectory;
- (void)createDirectory:(NSString *)dirPath;
- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions;
- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path;

- (void)rename:(NSString *)fromPath to:(NSString *)toPath;
- (void)recursivelyRenameS3Directory:(NSString *)fromDirectoryPath to:(NSString *)toDirectoryPath;

- (void)deleteFile:(NSString *)path;
- (void)deleteDirectory:(NSString *)dirPath;
- (void)recursivelyDeleteDirectory:(NSString *)path;

/**
	@method uploadLocalItem:toRemoteDirectory:ignoreHiddenItems:
	@abstract The designated method for uploading a given item to the remote host.
	@param localPath The path the item to upload. May be a file, directory, or symbolic link. May not be nil.
	@param remoteDirectoryPath The remote-path to the directory to upload into. Must be an absolute path. May not be nil.
	@param ignoreHiddenItemsFlag If YES, items which are prefixed with a "." will not be uploaded, recursively or not.
	@discussion If localPath contains a tilde, it is expanded. If the item at localPath is a symbolic link, the link is resolved, and the target is uploaded with the target's filename.
	@result A transfer record to represent the transfer.
 */
- (CKTransferRecord *)uploadLocalItem:(NSString *)localPath
					toRemoteDirectory:(NSString *)remoteDirectoryPath
					ignoreHiddenItems:(BOOL)ignoreHiddenItemsFlag;

- (CKTransferRecord *)_uploadFile:(NSString *)localPath 
						   toFile:(NSString *)remotePath 
			 checkRemoteExistence:(BOOL)flag 
						 delegate:(id)delegate;

- (CKTransferRecord *)uploadFromData:(NSData *)data
							  toFile:(NSString *)remotePath 
				checkRemoteExistence:(BOOL)flag
							delegate:(id)delegate;
- (CKTransferRecord *)resumeUploadFile:(NSString *)localPath 
								toFile:(NSString *)remotePath 
							fileOffset:(unsigned long long)offset
							  delegate:(id)delegate;
- (CKTransferRecord *)resumeUploadFromData:(NSData *)data
									toFile:(NSString *)remotePath 
								fileOffset:(unsigned long long)offset
								  delegate:(id)delegate;
/* 
	New method that allows you to set a custom delegate for the download.
	You must implement the CKConnectionTransferDelegate informal protocol.
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

- (CKTransferRecord *)recursivelyDownload:(NSString *)remotePath
									   to:(NSString *)localPath
								overwrite:(BOOL)flag;


- (void)checkExistenceOfPath:(NSString *)path;

- (unsigned)numberOfTransfers;
- (void)cancelTransfer;
- (void)cancelAll;

- (void)directoryContents;
- (void)contentsOfDirectory:(NSString *)dirPath;

- (double)uploadSpeed; // bytes per second
- (double)downloadSpeed;

- (void)cancelTransfer;

@end


#pragma mark -


@interface NSObject (CKConnectionDelegate)

// Need to keep NSObject Category, __flags list, setDelegate: updated

#pragma mark Connecting / Disconnecting
- (void)connection:(id <CKConnection>)con didConnectToHost:(NSString *)host error:(NSError *)error; // this only guarantees that the socket connected.
/*!
	@method connection:didOpenAtPath:authenticated:error:
	@abstract Indicates the connection has successfully opened at the given path.
	@param con The connection which opened.
	@param dirPath The directory the connection opened in. On HTTP-based connections, this is nil.
	@param didAuthenticate NO if the connection's username and/or password were rejected. YES, otherwise.
	@param error An error if the connection failed to open. Nil if the connection opened successfully.
	@discussion Note that on HTTP connections (WebDAV, S3) we immediately send didOpenAtPath:, before the first request is even sent. If the first request fails to authenticate, it is sent again with didAuthenticate = NO.
 */
- (void)connection:(id <CKConnection>)con didOpenAtPath:(NSString *)dirPath authenticated:(BOOL)didAuthenticate error:(NSError *)error;
- (void)connection:(id <CKConnection>)con didDisconnectFromHost:(NSString *)host;

#pragma mark Authentication
- (NSString *)connection:(id <CKConnection>)con passphraseForHost:(NSString *)host username:(NSString *)username publicKeyPath:(NSString *)publicKeyPath;   //SFTP Passphrase Support


#pragma mark General
- (void)connection:(id <CKConnection>)con didCreateDirectory:(NSString *)dirPath error:(NSError *)error;

- (void)connection:(id <CKConnection>)con didChangeToDirectory:(NSString *)dirPath error:(NSError *)error;
- (void)connection:(id <CKConnection>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath error:(NSError *)error;
- (void)connection:(id <CKConnection>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath moreComing:(BOOL)flag;
- (void)connection:(id <CKConnection>)con didRename:(NSString *)fromPath to:(NSString *)toPath error:(NSError *)error;
- (void)connection:(id <CKConnection>)con didSetPermissionsForFile:(NSString *)path error:(NSError *)error;

- (void)connectionDidCancelTransfer:(id <CKConnection>)con; // this is deprecated. Use method below
- (void)connection:(id <CKConnection>)con didCancelTransfer:(NSString *)remotePath;

- (void)connection:(id <CKConnection>)con checkedExistenceOfPath:(NSString *)path pathExists:(BOOL)exists error:(NSError *)error;

- (void)connection:(id <CKConnection>)con didReceiveError:(NSError *)error;

#pragma mark Deletion
- (void)connection:(id <CKConnection>)con didDeleteDirectory:(NSString *)dirPath error:(NSError *)error;
- (void)connection:(id <CKConnection>)con didDeleteFile:(NSString *)path error:(NSError *)error;

//Recursive Deletion Methods
- (void)connection:(id <CKConnection>)con didDiscoverFilesToDelete:(NSArray *)contents inAncestorDirectory:(NSString *)ancestorDirPath;
- (void)connection:(id <CKConnection>)con didDiscoverFilesToDelete:(NSArray *)contents inDirectory:(NSString *)dirPath;
- (void)connection:(id <CKConnection>)con didDeleteDirectory:(NSString *)dirPath inAncestorDirectory:(NSString *)ancestorDirPath error:(NSError *)error;
- (void)connection:(id <CKConnection>)con didDeleteFile:(NSString *)path inAncestorDirectory:(NSString *)ancestorDirPath error:(NSError *)error;

#pragma mark Downloading
- (void)connection:(id <CKConnection>)con download:(NSString *)path progressedTo:(NSNumber *)percent;
- (void)connection:(id <CKConnection>)con download:(NSString *)path receivedDataOfLength:(unsigned long long)length; 
- (void)connection:(id <CKConnection>)con downloadDidBegin:(NSString *)remotePath;
- (void)connection:(id <CKConnection>)con downloadDidFinish:(NSString *)remotePath error:(NSError *)error;

#pragma mark Uploading
- (void)connection:(id <CKConnection>)con upload:(NSString *)remotePath progressedTo:(NSNumber *)percent;
- (void)connection:(id <CKConnection>)con upload:(NSString *)remotePath sentDataOfLength:(unsigned long long)length;
- (void)connection:(id <CKConnection>)con uploadDidBegin:(NSString *)remotePath;
- (void)connection:(id <CKConnection>)con uploadDidFinish:(NSString *)remotePath error:(NSError *)error;

#pragma mark Transcript
/*!
 @method connection:appendString:toTranscript:
 @abstract Called when the connection has something to add to the connection transcript.
 @discussion Delegates should implement this method if they are interested in keeping a transcript. This could be to
 log the string to the console or add it to a text view.
 @param connection The connection sending the message
 @param string The string to add to the transcript
 @param transcript The nature of the string that is to be transcribed. CKAbstractConnection has class methods to apply formatting to the transcript.
 */
- (void)connection:(id <CKConnection>)connection appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript;

@end


#pragma mark -


@interface NSObject (CKConnectionTransferDelegate)
- (void)transferDidBegin:(CKTransferRecord *)transfer;
- (void)transfer:(CKTransferRecord *)transfer transferredDataOfLength:(unsigned long long)length;
- (void)transfer:(CKTransferRecord *)transfer progressedTo:(NSNumber *)percent;
- (void)transfer:(CKTransferRecord *)transfer receivedError:(NSError *)error;
- (void)transferDidFinish:(CKTransferRecord *)transfer error:(NSError *)error;
@end


//User Info Keys for Errors
extern NSString *ConnectionHostKey;
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
- (BOOL) hasSpaceAvailable;

- (int)write:(const uint8_t *)buffer maxLength:(unsigned int)len;
@end

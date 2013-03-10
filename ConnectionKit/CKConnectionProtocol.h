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
    CKTranscriptInfo,
} CKTranscriptType;


/*  A lightweight version of CKConnection, selfishly for Sandvox's benefit
 */
@protocol CKPublishingConnection <NSObject>

/*!
 @method URLSchemes
 @result An array of the URL schemes supported by the connection.
 */
+ (NSArray *)URLSchemes;

/*!
 @method initWithRequest:
 @abstract The designated initializer for connections.
 @param request The request to connect with. The request object is deep-copied as part of the
 initialization process. Changes made to request after this method returns do not affect the request
 that is used for the loading process.
 @result Returns an initialized connection object or nil if the request was unsuitable.
 */
- (id)initWithRequest:(NSURLRequest *)request;

/*!
 @discussion The delegate is not retained. The delegate should implement any of the methods in the CKConnectionDelegate informal protocol to receive callbacks when connection events occur.
 */
@property(nonatomic, assign) NSObject *delegate;

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

/* 
	New method that allows you to set a custom delegate for the upload.
	You must implement the ConnectionTransferDelegate informal protocol.
	By default the transfer record returned is the delegate of the transfer.
 
 SFTP connections require permissions to be explicitly specified up-front as part of creating a file. (in practice some servers then ignore them). Other connection types tend to apply default permissions of their own. You should generally pass in 0644 for broad compatibility. Importantly the connection makes NO GUARANTEE the permissions will be respected; they're just an attempt for SFTP and similar
*/
- (CKTransferRecord *)uploadFileAtURL:(NSURL *)url toPath:(NSString *)path openingPosixPermissions:(unsigned long)permissions;

/* 
 New method that allows you to set a custom delegate for the upload.
 You must implement the ConnectionTransferDelegate informal protocol.
 By default the transfer record returned is the delegate of the transfer.
 
 See openingPosixPermissions advice above
 */
- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path openingPosixPermissions:(unsigned long)permissions;

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path;

- (void)deleteFile:(NSString *)path;

- (void)createDirectoryAtPath:(NSString *)path posixPermissions:(NSNumber *)permissions;
- (void)changeToDirectory:(NSString *)dirPath;
- (NSString *)currentDirectory;
- (void)directoryContents;

@end


@protocol CKConnection <CKPublishingConnection>

+ (NSString *)name;

/*!
 @method port
 @discussion Return 0 for abstract classes or connections that do not use a port.
 @result The default port for connections of the receiver's class.
 */
+ (NSInteger)defaultPort;


/*!
 @method request
 @discussion Please do NOT modify this request in any way!
 @result Returns the request supplied when creating the connection.
 */
- (NSURLRequest *)request;


// you can set a name on a connection to help with debugging.
// TODO: Should this really be part of the protocol, or a CKAbstractConnection implementation detail?
- (NSString *)name; 
- (void)setName:(NSString *)name;

- (BOOL)isBusy;

 
- (void)cleanupConnection;

- (NSString *)rootDirectory;

- (void)rename:(NSString *)fromPath to:(NSString *)toPath;
- (void)recursivelyRenameS3Directory:(NSString *)fromDirectoryPath to:(NSString *)toDirectoryPath;

- (void)deleteDirectory:(NSString *)dirPath;
- (void)recursivelyDeleteDirectory:(NSString *)path;


/* 
	returns CKTransferRecord as a heirarchy of what will be upload, remote and local files 
	can be found in the records node properties
*/
- (CKTransferRecord *)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath;
- (CKTransferRecord *)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath ignoreHiddenFiles:(BOOL)flag;

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

- (void)contentsOfDirectory:(NSString *)dirPath;

- (double)uploadSpeed; // bytes per second
- (double)downloadSpeed;

- (void)editFile:(NSString *)remoteFile;

@end


#pragma mark -


@interface NSObject (CKConnectionDelegate)

// There are 29 callbacks & flags.
// Need to keep NSObject Category, __flags list, setDelegate: updated

#pragma mark Overall connection
- (void)connection:(id <CKPublishingConnection>)con didConnectToHost:(NSString *)host error:(NSError *)error; // this only guarantees that the socket connected.
- (void)connection:(id <CKPublishingConnection>)con didDisconnectFromHost:(NSString *)host;

- (void)connection:(id <CKPublishingConnection>)con didReceiveError:(NSError *)error;

#pragma mark Authentication
/*!
 @method connection:didReceiveAuthenticationChallenge:
 @abstract Operates just like the NSURLConnection delegate method -connection:didReceiveAuthenticationChallenge:
 @param connection The connection for which authentication is needed
 @param challenge The NSURLAuthenticationChallenge to start authentication for
 */
- (void)connection:(id <CKPublishingConnection>)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
/*!
 @method connection:didCancelAuthenticationChallenge:
 @abstract Operates exactly the same as its NSURLConnection counterpart.
 @param connection The connection sending the message.
 @param challenge The challenge that was canceled.
 */
- (void)connection:(id <CKPublishingConnection>)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

- (NSString *)connection:(id <CKConnection>)con passphraseForHost:(NSString *)host username:(NSString *)username publicKeyPath:(NSString *)publicKeyPath;   //SFTP Passphrase Support


#pragma mark Other

- (void)connection:(id <CKPublishingConnection>)con didCreateDirectory:(NSString *)dirPath error:(NSError *)error;
- (void)connection:(id <CKConnection>)con didDeleteDirectory:(NSString *)dirPath error:(NSError *)error;
- (void)connection:(id <CKPublishingConnection>)con didDeleteFile:(NSString *)path error:(NSError *)error;


// recursivelyDeleteDirectory
//     These methods may change soon -- Seth
- (void)connection:(id <CKConnection>)con didDiscoverFilesToDelete:(NSArray *)contents inAncestorDirectory:(NSString *)ancestorDirPath;
- (void)connection:(id <CKConnection>)con didDiscoverFilesToDelete:(NSArray *)contents inDirectory:(NSString *)dirPath;
- (void)connection:(id <CKConnection>)con didDeleteDirectory:(NSString *)dirPath inAncestorDirectory:(NSString *)ancestorDirPath error:(NSError *)error;
- (void)connection:(id <CKConnection>)con didDeleteFile:(NSString *)path inAncestorDirectory:(NSString *)ancestorDirPath error:(NSError *)error;


- (void)connection:(id <CKPublishingConnection>)con didChangeToDirectory:(NSString *)dirPath error:(NSError *)error;
- (void)connection:(id <CKPublishingConnection>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath error:(NSError *)error;
- (void)connection:(id <CKConnection>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath moreComing:(BOOL)flag;
- (void)connection:(id <CKConnection>)con didRename:(NSString *)fromPath to:(NSString *)toPath error:(NSError *)error;
- (void)connection:(id <CKPublishingConnection>)con didSetPermissionsForFile:(NSString *)path error:(NSError *)error;


- (void)connection:(id <CKConnection>)con download:(NSString *)path progressedTo:(NSNumber *)percent;
- (void)connection:(id <CKConnection>)con download:(NSString *)path receivedDataOfLength:(unsigned long long)length; 
- (void)connection:(id <CKConnection>)con downloadDidBegin:(NSString *)remotePath;
- (void)connection:(id <CKConnection>)con downloadDidFinish:(NSString *)remotePath error:(NSError *)error;


- (void)connection:(id <CKConnection>)con upload:(NSString *)remotePath progressedTo:(NSNumber *)percent;
- (void)connection:(id <CKConnection>)con upload:(NSString *)remotePath sentDataOfLength:(unsigned long long)length;
- (void)connection:(id <CKPublishingConnection>)con uploadDidBegin:(NSString *)remotePath;
- (void)connection:(id <CKPublishingConnection>)con uploadDidFinish:(NSString *)remotePath error:(NSError *)error;
- (void)connectionDidCancelTransfer:(id <CKConnection>)con; // this is deprecated. Use method below
- (void)connection:(id <CKConnection>)con didCancelTransfer:(NSString *)remotePath;

- (void)connection:(id <CKConnection>)con checkedExistenceOfPath:(NSString *)path pathExists:(BOOL)exists error:(NSError *)error;

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
- (void)connection:(id <CKPublishingConnection>)connection appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript;

@end


#pragma mark -


@interface NSObject (CKConnectionTransferDelegate)
- (void)transferDidBegin:(CKTransferRecord *)transfer;
- (void)transfer:(CKTransferRecord *)transfer transferredDataOfLength:(unsigned long long)length;
- (void)transfer:(CKTransferRecord *)transfer progressedTo:(NSNumber *)percent;
- (void)transfer:(CKTransferRecord *)transfer receivedError:(NSError *)error;
- (void)transferDidFinish:(CKTransferRecord *)transfer error:(NSError *)error;
@end


// Attributes for which there isn't a corresponding NSFileManager key
extern NSString *cxFilenameKey;
extern NSString *cxSymbolicLinkTargetKey;

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

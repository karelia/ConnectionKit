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
#import "AbstractConnectionProtocol.h" // protocols can't be forward-declared without warning in gcc 4.0

/*!	AbstractConnection is a convenience superclass that connections can descend from; it takes care of some of the core functionality.
Connection instances do not need to inherit from this superclass, they can just implement the protocol instead.
It also functions as a registry for automatic subclass detection.
*/

extern NSString *ConnectionErrorDomain;
enum { 
	ConnectionErrorParsingDirectoryListing = 6000, 
	ConnectionStreamError, 
	ConnectionErrorBadPassword, 
	ConnectionNoConnectionsAvailable,
	ConnectionNoUsernameOrPassword,
};
// Logging Domain Keys
extern NSString *ConnectionDomain;
extern NSString *TransportDomain; // used in custom stream classes
extern NSString *StateMachineDomain;
extern NSString *ParsingDomain;
extern NSString *ProtocolDomain;
extern NSString *ThreadingDomain;
extern NSString *StreamDomain;
extern NSString *InputStreamDomain;
extern NSString *OutputStreamDomain;
extern NSString *SSLDomain;
extern NSString *EditingDomain;

typedef enum {
	ConnectionNotConnectedState = 0,
	ConnectionIdleState,
	ConnectionSentUsernameState,
	ConnectionSentAccountState,	
	ConnectionSentPasswordState,	// 5
	ConnectionAwaitingCurrentDirectoryState,
	ConnectionOpeningDataStreamState,
	ConnectionAwaitingDirectoryContentsState,
	ConnectionChangingDirectoryState,  
	ConnectionCreateDirectoryState,// 10
	ConnectionDeleteDirectoryState,
	ConnectionRenameFromState,		
	ConnectionRenameToState,
	ConnectionAwaitingRenameState,  
	ConnectionDeleteFileState,// 15
	ConnectionDownloadingFileState,
	ConnectionUploadingFileState,	
	ConnectionSentOffsetState,
	ConnectionSentQuitState,		
	ConnectionSentFeatureRequestState,// 20
	ConnectionSettingPermissionsState,
	ConnectionSentSizeState,		
	ConnectionChangedDirectoryState,
	ConnectionSentDisconnectState, 
	ConnectionCheckingFileExistenceState // 25
} ConnectionState;

typedef struct __flags {
	unsigned isConnected:1;
	
	// There are 21 callbacks & flags.
	// Need to keep NSObject Category, __flags list, setDelegate: updated
	
	unsigned permissions:1;
	unsigned badPassword:1;
	unsigned cancel:1; // deprecated
	unsigned didCancel:1;
	unsigned changeDirectory:1;
	unsigned createDirectory:1;
	unsigned deleteDirectory:1;
	unsigned deleteDirectoryInAncestor:1;
	unsigned deleteFileInAncestor:1;
	unsigned discoverFilesToDeleteInAncestor:1;
	unsigned discoverFilesToDeleteInDirectory:1;
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
	unsigned didAuthenticate:1;
	unsigned passphrase:1;
	
	unsigned padding:2;
} connectionFlags;

@class UKKQueue, RunLoopForwarder;

@interface AbstractConnection : NSObject <AbstractConnectionProtocol> 
{
	NSString *_name;
	NSString *_connectionHost;
	NSString *_connectionPort;
	NSString *_username;
	NSString *_password;

	ConnectionState _state;
	
	@protected
		
	RunLoopForwarder	*_forwarder;

	NSTextStorage *_transcript;
	id _delegate;

	connectionFlags _flags;
	
	UKKQueue *_editWatcher;
	NSMutableDictionary *_edits;
	AbstractConnection *_editingConnection;
	
	NSMutableDictionary *_properties;
	
	NSMutableDictionary *_cachedDirectoryContents;
}

+ (id <AbstractConnectionProtocol>)connectionWithName:(NSString *)name
												 host:(NSString *)host
												 port:(NSString *)port
											 username:(NSString *)username
											 password:(NSString *)password
												error:(NSError **)error;

+ (id <AbstractConnectionProtocol>)connectionWithURL:(NSURL *)url error:(NSError **)error;

+ (NSString *)urlSchemeForConnectionName:(NSString *)name port:(NSString *)port;

// Convenience Superclass methods for basic getting & setting

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

- (void)setState:(ConnectionState)state;
- (ConnectionState)state;
// convience method to access the state
#define GET_STATE _state
- (NSString *)stateName:(int)state;

- (void)setDelegate:(id)delegate;	//we do not retain the delegate
- (id)delegate;

/* Properties used:
	RecursiveDirectoryDeletionTranscript is used by connections that recursively delete a directory
	FileCheckingTranscript is used by connections that check for a files existence
*/
- (void)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (void)removePropertyForKey:(NSString *)key;

// Subclass registration
+ (void)registerConnectionClass:(Class)inClass forTypes:(NSArray *)types;
+ (NSArray *)registeredConnectionTypes;
+ (NSMutableArray *)connectionTypes;
+ (NSString *)registeredPortForConnectionType:(NSString *)type;

// Transcript support
- (void)setTranscript:(NSTextStorage *)transcript;
- (NSTextStorage *)transcript;
- (void)appendToTranscript:(NSAttributedString *)str;

+ (NSDictionary *)sentAttributes;
+ (NSDictionary *)receivedAttributes;
+ (NSDictionary *)dataAttributes;

// we cache directory contents so when changing to an existing directory we show the 
// last cached version and issue a new listing. You should keep a current path in your delegate
// and ignore a listing if the path returned is not your current one. THis is where a user
// can click through a cached directory structure and then the new listings are returned but they are
// already in a different directory.
- (void)cacheDirectory:(NSString *)path withContents:(NSArray *)contents;
- (NSArray *)cachedContentsWithDirectory:(NSString *)path;
- (void)clearDirectoryCache;

@end

@interface AbstractConnection (PrivateSubclassSupport)
- (void)threadedConnect;
- (void)threadedDisconnect;
- (void)threadedForceDisconnect;
- (void)threadedCancelTransfer;
- (void)threadedCancelAll;
@end

extern NSString *ConnectionAwaitStateKey;
extern NSString *ConnectionSentStateKey;
extern NSString *ConnectionCommandKey;

@interface NSString (AbstractConnectionExtras)
- (NSString *)stringByAppendingDirectoryTerminator;
@end

@interface NSInvocation (AbstractConnectionExtras)
+ (NSInvocation *)invocationWithSelector:(SEL)aSelector 
								  target:(id)aTarget 
							   arguments:(NSArray *)anArgumentArray;
@end

@interface NSFileManager (AbstractConnectionExtras)
+ (NSArray *)attributedFilesFromListing:(NSString *)line;
+ (void)parsePermissions:(NSString *)perm withAttributes:(NSMutableDictionary *)attributes;
@end

@interface NSCalendarDate (AbstractConnectionExtras)
+ (NSCalendarDate *)getDateFromMonth:(NSString *)month day:(NSString *)day yearOrTime:(NSString *)yearOrTime;
@end

@interface NSHost (IPV4)
- (NSString *)ipv4Address;
@end

@interface NSArray (AbstractConnectionExtras)
- (NSArray *)filteredArrayByRemovingHiddenFiles;
@end


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

#import <Foundation/Foundation.h>
#import "CKConnectionProtocol.h" // protocols can't be forward-declared without warning in gcc 4.0

#import "CKConnectionRegistry.h"
#import "CKConnectionClientProtocol.h"


/*!	CKAbstractConnection is a convenience superclass that connections can descend from; it takes care of some of the core functionality.
 Connection instances do not need to inherit from this superclass, they can just implement the protocol instead.
 */

extern NSString *CKConnectionErrorDomain;
enum { 
    CKConnectionErrorParsingDirectoryListing = 6000, 
    CKConnectionStreamError, 
    CKConnectionErrorBadPassword, 
    CKConnectionNoConnectionsAvailable,
    CKConnectionNoUsernameOrPassword,
};


// Logging Domain Keys
extern NSString *CKConnectionDomain;
extern NSString *CKTransportDomain; // used in custom stream classes
extern NSString *CKStateMachineDomain;
extern NSString *CKParsingDomain;
extern NSString *CKProtocolDomain;
extern NSString *CKThreadingDomain;
extern NSString *CKStreamDomain;
extern NSString *CKInputStreamDomain;
extern NSString *CKOutputStreamDomain;
extern NSString *CKSSLDomain;
extern NSString *CKEditingDomain;


typedef enum {
	CKConnectionNotConnectedState = 0,
	CKConnectionIdleState,
	CKConnectionSentUsernameState,
	CKConnectionSentAccountState,	
	CKConnectionSentPasswordState,	// 5
	CKConnectionAwaitingCurrentDirectoryState,
	CKConnectionOpeningDataStreamState,
	CKConnectionAwaitingDirectoryContentsState,
	CKConnectionChangingDirectoryState,  
	CKConnectionCreateDirectoryState,// 10
	CKConnectionDeleteDirectoryState,
	CKConnectionRenameFromState,		
	CKConnectionRenameToState,
	CKConnectionAwaitingRenameState,  
	CKConnectionDeleteFileState,// 15
	CKConnectionDownloadingFileState,
	CKConnectionUploadingFileState,	
	CKConnectionSentOffsetState,
	CKConnectionSentQuitState,		
	CKConnectionSentFeatureRequestState,// 20
	CKConnectionSettingPermissionsState,
	CKConnectionSentSizeState,		
	CKConnectionChangedDirectoryState,
	CKConnectionSentDisconnectState, 
	CKConnectionCheckingFileExistenceState // 25
} CKConnectionState;


@class UKKQueue, CKConnectionClient;


@interface CKAbstractConnection : NSObject <CKConnection> 
{
	CKConnectionState _state;
	
@protected
        
	
	BOOL	_isConnecting;	// YES once -connect has been called and before isConnected returns YES
    BOOL    _isConnected;
    BOOL    _inBulk;
		
	
	UKKQueue *_editWatcher;
	NSMutableDictionary *_edits;
	CKAbstractConnection *_editingConnection;
		
	NSMutableDictionary *_cachedDirectoryContents;
    
@private
    NSString            *_name;
    CKConnectionRequest *_request;
    id                  _delegate;
    
    CKConnectionClient  *_client;
}

+ (NSAttributedString *)attributedStringForString:(NSString *)string transcript:(CKTranscriptType)transcript;
+ (NSDictionary *)sentTranscriptStringAttributes;
+ (NSDictionary *)receivedTranscriptStringAttributes;
+ (NSDictionary *)dataTranscriptStringAttributes;

/*!
 @method port
 @abstract If the connection's URL has a port defined, it will be used. Otherwise,
 this method falls back to the default port for the connection class.
 @result The port the connection will use to connect on.
 */
- (NSInteger)port;

- (void)setState:(CKConnectionState)state;
- (CKConnectionState)state;
// convience method to access the state
#define GET_STATE _state
- (NSString *)stateName:(int)state;


// we cache directory contents so when changing to an existing directory we show the 
// last cached version and issue a new listing. You should keep a current path in your delegate
// and ignore a listing if the path returned is not your current one. THis is where a user
// can click through a cached directory structure and then the new listings are returned but they are
// already in a different directory.
- (void)cacheDirectory:(NSString *)path withContents:(NSArray *)contents;
- (NSArray *)cachedContentsWithDirectory:(NSString *)path;
- (void)clearDirectoryCache;

@end


/*  PrivateSubclassSupport and SubclassSupport are categories of methods that are intended for
 *  the user of subclasses only. You are strongly discouraged from accessing them from other
 *  situations. Documentation can be found with the methods in the implementation file.
 */

@interface CKAbstractConnection (PrivateSubclassSupport)
- (void)threadedConnect;
- (void)threadedDisconnect;
- (void)threadedForceDisconnect;
- (void)threadedCancelTransfer;
- (void)threadedCancelAll;

- (void)startBulkCommands;
- (void)endBulkCommands;
@end


@interface CKAbstractConnection (SubclassSupport)

// Client
- (id <CKConnectionClient>)client;

@end


extern NSString *CKConnectionAwaitStateKey;
extern NSString *CKConnectionSentStateKey;
extern NSString *CKConnectionCommandKey;


@interface NSInvocation (AbstractConnectionExtras)
+ (NSInvocation *)invocationWithSelector:(SEL)aSelector 
								  target:(id)aTarget 
							   arguments:(NSArray *)anArgumentArray;
@end


@interface NSHost (IPV4)
- (NSString *)ipv4Address;
@end



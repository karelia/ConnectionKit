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

#import "CKAbstractConnection.h"
#import "CKConnectionClient.h"

#import "CKTransferRecord.h"
#import "UKKQueue.h"

#import "CKConnectionThreadManager.h"
#import "InterThreadMessaging.h"

#import "NSString+Connection.h"
#import "NSURL+Connection.h"
#import "KTLog.h"


NSString *CKConnectionErrorDomain = @"ConnectionErrorDomain";

// Command Dictionary Keys
NSString *CKConnectionAwaitStateKey = @"ConnectionAwaitStateKey";
NSString *CKConnectionSentStateKey = @"ConnectionSentStateKey";
NSString *CKConnectionCommandKey = @"ConnectionCommandKey";

// Attributes for which there isn't a corresponding NSFileManager key
NSString *cxFilenameKey = @"cxFilenameKey";
NSString *cxSymbolicLinkTargetKey = @"cxSymbolicLinkTargetKey";

// User Info Error Keys
NSString *ConnectionHostKey = @"ConnectionHostKey";
NSString *ConnectionDirectoryExistsKey = @"ConnectionDirectoryExistsKey";
NSString *ConnectionDirectoryExistsFilenameKey = @"ConnectionDirectoryExistsFilenameKey";

// Logging Domains 
NSString *CKTransportDomain = @"Transport";
NSString *CKStateMachineDomain = @"State Machine";
NSString *CKParsingDomain = @"Parser";
NSString *CKProtocolDomain = @"Protocol";
NSString *CKConnectionDomain = @"Connection";
NSString *CKThreadingDomain = @"Threading";
NSString *CKStreamDomain = @"Stream";
NSString *CKInputStreamDomain = @"Input Stream";
NSString *CKOutputStreamDomain = @"Output Stream";
NSString *CKSSLDomain = @"SSL";
NSString *CKEditingDomain = @"Editing";


NSDictionary *sSentAttributes = nil;
NSDictionary *sReceivedAttributes = nil;
NSDictionary *sDataAttributes = nil;


@implementation CKAbstractConnection

+ (NSString *)name { return nil; }

+ (NSInteger)defaultPort { return 0; }

+ (NSArray *)URLSchemes { return nil; }

#pragma mark -
#pragma mark Transcript

/*	The string attributes to use for the different types of transcript logging
 */

+ (NSAttributedString *)attributedStringForString:(NSString *)string transcript:(CKTranscriptType)transcript
{
	NSDictionary *attributes = nil;
	
	switch (transcript)
	{
		case CKTranscriptSent:
			attributes = [self sentTranscriptStringAttributes];
			break;
		case CKTranscriptReceived:
			attributes = [self receivedTranscriptStringAttributes];
			break;
		case CKTranscriptData:
			attributes = [self dataTranscriptStringAttributes];
			break;
	}
	
	NSAttributedString *result = [NSAttributedString attributedStringWithString:string attributes:attributes];
	return result;
}

+ (NSDictionary *)sentTranscriptStringAttributes
{
    if (!sSentAttributes)
        sSentAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:[NSFont fontWithName:@"Courier" size:11], NSFontAttributeName, [NSColor redColor], NSForegroundColorAttributeName, nil];
    return sSentAttributes;
}

+ (NSDictionary *)receivedTranscriptStringAttributes
{
    if (!sReceivedAttributes)
        sReceivedAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:[NSFont fontWithName:@"Courier-Bold" size:11], NSFontAttributeName, [NSColor blackColor], NSForegroundColorAttributeName, nil];
    return sReceivedAttributes;
}

+ (NSDictionary *)dataTranscriptStringAttributes
{
    if (!sDataAttributes)
        sDataAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:[NSFont fontWithName:@"Courier" size:11], NSFontAttributeName, [NSColor blueColor], NSForegroundColorAttributeName, nil];
    return sDataAttributes;
}

#pragma mark -
#pragma mark Inheritable methods

- (id)initWithRequest:(CKConnectionRequest *)request
{
	NSParameterAssert(request);
    
    NSURL *URL = [request URL];
    NSParameterAssert(URL); // Not supplying a URL is programmer error
    
    // To start a connection we require the protocol to be one supported by the receiver. Subclasses may impose other restrictions.
    if (![URL scheme] || ![[[self class] URLSchemes] containsObject:[URL scheme]])
    {
        [self release];
        return nil;
    }
    
    
    if (self = [super init])
	{
		_request = [request copy];
        
        _client = [[CKConnectionClient alloc] initWithConnection:self];
        
		_edits = [[NSMutableDictionary dictionary] retain];
		_cachedDirectoryContents = [[NSMutableDictionary dictionary] retain];
		_isConnected = NO;
		_name = [@"Default" retain];
	}
	return self;
}

- (void)dealloc
{
	[_name release];
	[_request release];
    
    [_client release];
    
	[_cachedDirectoryContents release];
	[_edits release];
	[_editWatcher release];
	[_editingConnection forceDisconnect];
	[_editingConnection release];
	
	[super dealloc];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@ - %@", [super description], _name];
}

- (CKConnectionRequest *)request { return _request; }

- (NSInteger)port
{
	NSNumber *port = [[[self request] URL] port];
    return (port) ? [port intValue] : [[self class] defaultPort];
}

- (void)setState:(CKConnectionState)state
{
	_state = state;
}

- (CKConnectionState)state
{
	return _state;
}

- (NSString *)stateName:(int)state
{
	switch (state) {
		case CKConnectionNotConnectedState: return @"ConnectionNotConnectedState";
		case CKConnectionIdleState: return @"ConnectionIdleState";
		case CKConnectionSentUsernameState: return @"ConnectionSentUsernameState";
		case CKConnectionSentAccountState: return @"ConnectionSentAccountState";	
		case CKConnectionSentPasswordState: return @"ConnectionSentPasswordState";
		case CKConnectionAwaitingCurrentDirectoryState: return @"ConnectionAwaitingCurrentDirectoryState";
		case CKConnectionOpeningDataStreamState: return @"ConnectionOpeningDataStreamState";
		case CKConnectionAwaitingDirectoryContentsState: return @"ConnectionAwaitingDirectoryContentsState";
		case CKConnectionChangingDirectoryState: return @"ConnectionChangingDirectoryState";  
		case CKConnectionCreateDirectoryState: return @"ConnectionCreateDirectoryState";
		case CKConnectionDeleteDirectoryState: return @"ConnectionDeleteDirectoryState";
		case CKConnectionRenameFromState: return @"ConnectionRenameFromState";		
		case CKConnectionRenameToState: return @"ConnectionRenameToState";
		case CKConnectionAwaitingRenameState: return @"ConnectionAwaitingRenameState";  
		case CKConnectionDeleteFileState: return @"ConnectionDeleteFileState";
		case CKConnectionDownloadingFileState: return @"ConnectionDownloadingFileState";
		case CKConnectionUploadingFileState: return @"ConnectionUploadingFileState";	
		case CKConnectionSentOffsetState: return @"ConnectionSentOffsetState";
		case CKConnectionSentQuitState: return @"ConnectionSentQuitState";		
		case CKConnectionSentFeatureRequestState: return @"ConnectionSentFeatureRequestState";
		case CKConnectionSettingPermissionsState: return @"ConnectionSettingPermissionsState";
		case CKConnectionSentSizeState: return @"ConnectionSentSizeState";		
		case CKConnectionChangedDirectoryState: return @"CKConnectionChangedDirectoryState";
		case CKConnectionSentDisconnectState: return @"CKConnectionSentDisconnectState";
		default: return @"Unknown State";
	}
}

- (void)setDelegate:(id)del
{
	_delegate = del;
    [_client setDelegate:del];
}

- (id)delegate
{
	return _delegate;
}

- (void)cacheDirectory:(NSString *)path withContents:(NSArray *)contents
{
	path = [path stringByStandardizingURLComponents];
	[_cachedDirectoryContents setObject:contents forKey:path];
}

- (NSArray *)cachedContentsWithDirectory:(NSString *)path
{
	path = [path stringByStandardizingURLComponents];
	return [_cachedDirectoryContents objectForKey:path];
}

- (void)clearDirectoryCache
{
	[_cachedDirectoryContents removeAllObjects];
}


#pragma mark -
#pragma mark Placeholder implementations

- (void)connect
{
	if (!_isConnecting && ![self isConnected])
	{
		_isConnecting = YES;
		[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedConnect];
	}
}

/*	Subclasses are expected to implement their own connection code before calling this method to send the callback
 */
- (void)threadedConnect
{
	_isConnected = YES;
	_isConnecting = NO;
	
	// Inform delegate
    [[self client] connectionDidConnectToHost:[[[self request] URL] host] error:nil];
}

- (BOOL)isConnected { return _isConnected; }

- (void)disconnect
{
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedDisconnect];
}

- (void)threadedDisconnect
{
	_isConnected = NO;
    [[self client] connectionDidDisconnectFromHost:[[[self request] URL] host]];
}

- (void)forceDisconnect
{
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedForceDisconnect];
}

- (void)threadedForceDisconnect
{
	_isConnected = NO;
	[[self client] connectionDidDisconnectFromHost:[[[self request] URL] host]];
}


- (void)cleanupConnection
{
	NSLog (@"base class clean up, do we have to clean anything?");
}

#define SUBCLASS_RESPONSIBLE @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"%@ must implement %@", [self className], NSStringFromSelector(_cmd)] userInfo:nil];

- (void)changeToDirectory:(NSString *)dirPath
{
    SUBCLASS_RESPONSIBLE
}

- (NSString *)currentDirectory
{
	SUBCLASS_RESPONSIBLE
}

- (void)createDirectory:(NSString *)dirPath
{
	SUBCLASS_RESPONSIBLE
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions
{
	SUBCLASS_RESPONSIBLE
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path
{
	SUBCLASS_RESPONSIBLE
}

- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	SUBCLASS_RESPONSIBLE
}

- (void)recursivelyRenameS3Directory:(NSString *)fromDirectoryPath to:(NSString *)toDirectoryPath;
{
	SUBCLASS_RESPONSIBLE
}

- (void)deleteFile:(NSString *)path
{
	SUBCLASS_RESPONSIBLE
}

- (void)deleteDirectory:(NSString *)dirPath
{
	SUBCLASS_RESPONSIBLE
}

- (void)recursivelyDeleteDirectory:(NSString *)path;
{
	SUBCLASS_RESPONSIBLE
}

- (CKTransferRecord *)uploadFile:(NSString *)localPath 
						  toFile:(NSString *)remotePath 
			checkRemoteExistence:(BOOL)flag 
						delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (CKTransferRecord *)recursiveRecordWithPath:(NSString *)path root:(CKTransferRecord *)root
{
	NSString *first = [path firstPathComponent];
	if ([[root name] isEqualToString:first] || [[root path] isEqualToString:@"/"])
	{
		CKTransferRecord *child = nil;
		NSEnumerator *e = [[root contents] objectEnumerator];
		CKTransferRecord *cur;
		if (![[root path] isEqualToString:@"/"])
		{
			path = [path stringByDeletingFirstPathComponent];
		}
		if ([path isEqualToString:@"/"])
		{
			return root;
		}
		
		while ((cur = [e nextObject]))
		{
			child = [self recursiveRecordWithPath:path root:cur];
			if (child)
			{
				return child;
			}
		}
		
		// if we get here we need to create the record		
		CKTransferRecord *tmp = root;
		while (![path isEqualToString:@"/"])
		{
			cur = [CKTransferRecord recordWithName:[path firstPathComponent] size:0];
			[tmp addContent:cur];
			tmp = cur;
			path = [path stringByDeletingFirstPathComponent];
		}
		return cur;
	}
	return nil;
}

- (void)_mergeRecord:(CKTransferRecord *)rec into:(CKTransferRecord *)root
{
	CKTransferRecord *parent = [self recursiveRecordWithPath:[[rec name] stringByDeletingLastPathComponent] root:root];
	[rec setName:[[rec name] lastPathComponent]];		
	[parent addContent:rec];
}

- (CKTransferRecord *)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath root:(CKTransferRecord *)root rootPath:(NSString *)rootPath ignoreHiddenFiles:(BOOL)ignoreHiddenFilesFlag
{
	NSFileManager *fm = [NSFileManager defaultManager];
	CKTransferRecord *record;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL isDir;
	
	//create this directory
	[self createDirectory:remotePath];
	
	NSEnumerator *e = [[fm contentsOfDirectoryAtPath:localPath error:NULL] objectEnumerator];
	NSString *path;
	NSUInteger numberOfSubRecordsAdded = 0;
	while ((path = [e nextObject]))
	{
		path = [localPath stringByAppendingPathComponent:path];
		if (ignoreHiddenFilesFlag && [[path lastPathComponent] hasPrefix:@"."])
			continue;
		
		numberOfSubRecordsAdded++;
		
		if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir)
		{
			[self recursivelyUpload:path 
								 to:[remotePath stringByAppendingPathComponent:[path lastPathComponent]] 
							   root:root 
						   rootPath:rootPath
				  ignoreHiddenFiles:ignoreHiddenFilesFlag];
		}
		else
		{
			NSString *remote = [remotePath stringByAppendingPathComponent:[path lastPathComponent]];
			record = [self uploadFile:path
							   toFile:remote
				 checkRemoteExistence:NO
							 delegate:nil];
			if (![[root path] isEqualToString:@"/"])
			{
				[self _mergeRecord:record into:root];
			}
			else
			{
				CKTransferRecord *parent = [self recursiveRecordWithPath:[[record name] stringByDeletingLastPathComponent] root:root];
				root = parent;
				[root setName:[[root name] lastPathComponent]];		
				[record setName:[[record name] lastPathComponent]];		
				[root addContent:record];
			}
		}
	}
	
	if (numberOfSubRecordsAdded == 0)
	{
		CKTransferRecord *record = [CKTransferRecord recordWithName:remotePath size:4];
		if (![[root path] isEqualToString:@"/"])
		{
			[self _mergeRecord:record into:root];
		}
		else
		{
			CKTransferRecord *parent = [self recursiveRecordWithPath:[[record name] stringByDeletingLastPathComponent] root:root];
			root = parent;
			[root setName:[[root name] lastPathComponent]];		
			[record setName:[[record name] lastPathComponent]];		
			[root addContent:record];
		}		
		[record transferDidFinish:record error:nil];
	}
	
	[pool release];
	return root;
}

- (CKTransferRecord *)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath
{
	return [self recursivelyUpload:localPath to:remotePath ignoreHiddenFiles:NO];
}

- (CKTransferRecord *)recursivelyUpload:(NSString *)localPath to:(NSString *)remotePath ignoreHiddenFiles:(BOOL)ignoreHiddenFilesFlag
{
	CKTransferRecord *root = [CKTransferRecord rootRecordWithPath:remotePath];
	[root setUpload:YES];
	NSFileManager *fm = [NSFileManager defaultManager];
	
	CKTransferRecord *record;
	BOOL isDir;
	
	[self startBulkCommands];
	
	if ([fm fileExistsAtPath:localPath isDirectory:&isDir] && !isDir)
	{
		NSString *remote = [remotePath stringByAppendingPathComponent:[localPath lastPathComponent]];
		record = [self uploadFile:localPath
						   toFile:remote
			 checkRemoteExistence:NO
						 delegate:nil];
		if (![[root path] isEqualToString:@"/"])
		{
			[self _mergeRecord:record into:root];
		}
		else
		{
			root = record;
			[root setUpload:YES];
			[root setName:[[root name] lastPathComponent]];		
		}
	}
	else
	{
		[self createDirectory:remotePath];
		root = [self recursivelyUpload:localPath 
									to:[remotePath stringByAppendingPathComponent:[localPath lastPathComponent]] 
								  root:root 
							  rootPath:remotePath
					 ignoreHiddenFiles:ignoreHiddenFilesFlag];
	}
	[self endBulkCommands];
	return root;
}

- (CKTransferRecord *)resumeUploadFile:(NSString *)localPath 
								toFile:(NSString *)remotePath 
							fileOffset:(unsigned long long)offset
							  delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (CKTransferRecord *)uploadFromData:(NSData *)data
							  toFile:(NSString *)remotePath 
				checkRemoteExistence:(BOOL)flag
							delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (CKTransferRecord *)resumeUploadFromData:(NSData *)data
									toFile:(NSString *)remotePath 
								fileOffset:(unsigned long long)offset
								  delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (CKTransferRecord *)downloadFile:(NSString *)remotePath 
					   toDirectory:(NSString *)dirPath 
						 overwrite:(BOOL)flag
						  delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (CKTransferRecord *)resumeDownloadFile:(NSString *)remotePath
							 toDirectory:(NSString *)dirPath
							  fileOffset:(unsigned long long)offset
								delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (CKTransferRecord *)recursivelyDownload:(NSString *)remotePath
									   to:(NSString *)localPath
								overwrite:(BOOL)flag
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

- (BOOL)isBusy
{
	return NO;
}

- (unsigned)numberOfTransfers
{
	return 0;
}

- (void)cancelTransfer
{
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedCancelTransfer];
}

- (void)threadedCancelTransfer
{
	
}

- (void)cancelAll
{
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] threadedCancelAll];
}

- (void)threadedCancelAll
{
	
}

- (long long)transferSpeed
{
	return 0;
}

- (double)uploadSpeed
{
	return 0;
}

- (double)downloadSpeed
{
	return 0;
}

- (void)directoryContents
{
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	SUBCLASS_RESPONSIBLE
}

- (void)startBulkCommands
{
	_inBulk = YES;
}

- (void)endBulkCommands
{
	_inBulk = NO;
}

- (NSString *)rootDirectory
{
	return nil;
}

- (void)checkExistenceOfPath:(NSString *)path
{
	@throw [NSException exceptionWithName:NSInternalInconsistencyException
								   reason:@"CKAbstractConnection does not implement checkExistanceOfPath:"
								 userInfo:nil];
}

- (void)editFile:(NSString *)remotePath 
{
	NSString *localEditable = [NSTemporaryDirectory() stringByAppendingPathComponent:[remotePath lastPathComponent]];
	[_edits setObject:remotePath forKey:localEditable];
	if (!_editingConnection)
	{
		_editingConnection = [self copy];
		[_editingConnection setName:@"editing"];
		[_editingConnection setDelegate:self];
		[_editingConnection connect];
	}
	[_editingConnection downloadFile:remotePath toDirectory:[localEditable stringByDeletingLastPathComponent] overwrite:YES delegate:nil];
}

- (void)setName:(NSString *)name
{
	if (name != _name)
	{
		[_name autorelease];
		_name = [name copy];
	}
}

- (NSString *)name;
{
	return _name;
}

#pragma mark -
#pragma mark UKKQueue Delegate Methods

- (void)watcher:(id<UKFileWatcher>)kq receivedNotification:(NSString*)nm forPath:(NSString*)fpath
{
	if ([nm isEqualToString:UKFileWatcherAttributeChangeNotification]) //UKFileWatcherWriteNotification does not get called because of atomicity of file writing (i believe)
	{
		KTLog(CKEditingDomain, KTLogDebug, @"File changed: %@... uploading to server", fpath);
		[self uploadFile:fpath toFile:[_edits objectForKey:fpath] checkRemoteExistence:NO delegate:nil];
	}
}

#pragma mark -
#pragma mark Editing Connection Delegate Methods

- (void)connection:(id <CKConnection>)con didDisconnectFromHost:(NSString *)host
{
	if (con == _editingConnection)
	{
		[_editingConnection release];
		_editingConnection = nil;
	}
}

- (void)connection:(id <CKConnection>)con download:(NSString *)path progressedTo:(NSNumber *)percent
{
	[[self client] download:path didProgressToPercent:percent];
}

- (void)connection:(id <CKConnection>)con download:(NSString *)path receivedDataOfLength:(unsigned long long)length
{
	[[self client] download:path didReceiveDataOfLength:length];
}

- (void)connection:(id <CKConnection>)con downloadDidBegin:(NSString *)remotePath
{
	[[self client] downloadDidBegin:remotePath];
}

- (void)connection:(id <CKConnection>)con downloadDidFinish:(NSString *)remotePath error:(NSError *)error
{
	[[self client] downloadDidFinish:remotePath error:error];
    
    
	KTLog(CKEditingDomain, KTLogDebug, @"Downloaded file %@... watching for changes", remotePath);
	NSEnumerator *e = [_edits keyEnumerator];
	NSString *key, *cur;
	
	while ((key = [e nextObject]))
	{
		cur = [_edits objectForKey:key];
		if ([cur isEqualToString:remotePath])
		{
			if (!_editWatcher)
			{
				_editWatcher = [[UKKQueue alloc] init];
				[_editWatcher setDelegate:self];
			}
			[_editWatcher addPathToQueue:key];
			KTLog(CKEditingDomain, KTLogDebug, @"Opening file for editing %@", key);
			[[NSWorkspace sharedWorkspace] openFile:key];
		}
	}
	
}

- (void)connection:(id <CKConnection>)con upload:(NSString *)remotePath progressedTo:(NSNumber *)percent
{
	[[self client] upload:remotePath didProgressToPercent:percent];
}

- (void)connection:(id <CKConnection>)con upload:(NSString *)remotePath sentDataOfLength:(unsigned long long)length
{
	[[self client] upload:remotePath didSendDataOfLength:length];
}

- (void)connection:(id <CKConnection>)con uploadDidBegin:(NSString *)remotePath
{
    [[self client] uploadDidBegin:remotePath];
}

- (void)connection:(id <CKConnection>)con uploadDidFinish:(NSString *)remotePath error:(NSError *)error
{
    [[self client] uploadDidFinish:remotePath error:error];
}

- (void)connection:(id <CKConnection>)connection appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript;
{
	[[self client] appendString:string toTranscript:transcript];
}

@end


#pragma mark -


@implementation CKAbstractConnection (SubclassSupport)

#pragma mark -
#pragma mark Client

/*  CKAbstractConnection subclasses should never communicate with their delegate directly, it's too
 *  tricky. Instead, send the corresponding message to the client and it will be handled appropriately.
 */
- (id <CKConnectionClient>)client
{
    return _client;
}

@end


#pragma mark -


@implementation NSInvocation (AbstractConnectionExtras)

+ (NSInvocation *)invocationWithSelector:(SEL)aSelector target:(id)aTarget arguments:(NSArray *)anArgumentArray
{
    NSMethodSignature *methodSignature = [aTarget methodSignatureForSelector:aSelector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    if ( nil != invocation )
    {
        [invocation setSelector:aSelector];
        [invocation setTarget:aTarget];
        if ( (nil != anArgumentArray) && ([anArgumentArray count] > 0) )
        {
            NSEnumerator *e = [anArgumentArray objectEnumerator];
            id argument;
            int argumentIndex = 2; // arguments start at index 2 per NSInvocation.h
            while ( argument = [e nextObject] )
            {
                if ( [argument isMemberOfClass:[NSNull class]] )
                {
                    [invocation setArgument:nil atIndex:argumentIndex];
                }
                else
                {
                    [invocation setArgument:&argument atIndex:argumentIndex];
                }
                argumentIndex++;
            }
            [invocation retainArguments];
        }
    }
	
    return invocation;
}

@end


@implementation NSHost (IPV4)
- (NSString *)ipv4Address
{
	NSEnumerator *e = [[self addresses] objectEnumerator];
	NSString *cur;
	
	while (cur = [e nextObject]) {
		if ([cur rangeOfString:@"."].location != NSNotFound)
			return cur;
	}
	return nil;
}
@end


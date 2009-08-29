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

#import "CKConnectionThreadManager.h"


#import "NSString+Connection.h"
#import "NSURL+Connection.h"
#import "KTLog.h"

NSString *CKConnectionErrorDomain = @"ConnectionErrorDomain";

// Command Dictionary Keys
NSString *CKConnectionAwaitStateKey = @"ConnectionAwaitStateKey";
NSString *CKConnectionSentStateKey = @"ConnectionSentStateKey";
NSString *CKConnectionCommandKey = @"ConnectionCommandKey";

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

//User Defaults
NSString *CKDoesNotCacheDirectoryListingsKey = @"CKDoesNotCacheDirectoryListings";
NSString *CKDoesNotRefreshCachedListingsKey = @"CKDoesNotRefreshCachedListings";


NSDictionary *sSentAttributes = nil;
NSDictionary *sReceivedAttributes = nil;
NSDictionary *sDataAttributes = nil;

@interface CKAbstractConnection (Private)
- (CKTransferRecord *)_recursivelyUploadDirectoryAtLocalPath:(NSString *)localPath
										   toRemoteDirectory:(NSString *)remoteDirectoryPath
												parentRecord:(CKTransferRecord *)parentRecord
										   ignoreHiddenItems:(BOOL)ignoreHiddenItemsFlag;
@end


@implementation CKAbstractConnection

+ (CKProtocol)protocol { return 0; }

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
        sSentAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
						   [NSFont fontWithName:@"Courier" size:11], NSFontAttributeName, 
						   [NSColor redColor], NSForegroundColorAttributeName, nil];
    return sSentAttributes;
}

+ (NSDictionary *)receivedTranscriptStringAttributes
{
    if (!sReceivedAttributes)
        sReceivedAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
							   [NSFont fontWithName:@"Courier-Bold" size:11], NSFontAttributeName, 
							   [NSColor blackColor], NSForegroundColorAttributeName, nil];
    return sReceivedAttributes;
}

+ (NSDictionary *)dataTranscriptStringAttributes
{
    if (!sDataAttributes)
        sDataAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
						   [NSFont fontWithName:@"Courier" size:11], NSFontAttributeName,
						   [NSColor blueColor], NSForegroundColorAttributeName, nil];
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
        
		_properties = [[NSMutableDictionary dictionary] retain];
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
	[_properties release];
	
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
	switch (state)
	{
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

- (void)setProperty:(id)property forKey:(id)key
{
	[_properties setObject:property forKey:key];
}

- (id)propertyForKey:(id)propertyKey
{
	return [_properties objectForKey:propertyKey];
}

- (void)removePropertyForKey:(id)key
{
	[_properties removeObjectForKey:key];
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

- (void)startBulkCommands
{
	_inBulk = YES;
}

- (void)endBulkCommands
{
	_inBulk = NO;
}

#pragma mark -
#pragma mark Core

#pragma mark Connecting/Disconnecting
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
	NSLog(@"base class clean up, do we have to clean anything?");
}

#define SUBCLASS_RESPONSIBLE @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"%@ must implement %@", [self className], NSStringFromSelector(_cmd)] userInfo:nil];

#pragma mark File/Directory Management
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

- (void)directoryContents
{
	SUBCLASS_RESPONSIBLE
}

- (void)contentsOfDirectory:(NSString *)dirPath
{
	SUBCLASS_RESPONSIBLE
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

#pragma mark Renaming
- (void)rename:(NSString *)fromPath to:(NSString *)toPath
{
	SUBCLASS_RESPONSIBLE
}

- (void)recursivelyRenameS3Directory:(NSString *)fromDirectoryPath to:(NSString *)toDirectoryPath;
{
	SUBCLASS_RESPONSIBLE
}

#pragma mark Deletion
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

#pragma mark Uploading
- (CKTransferRecord *)uploadLocalItem:(NSString *)localPath
					toRemoteDirectory:(NSString *)remoteDirectoryPath
					ignoreHiddenItems:(BOOL)ignoreHiddenItemsFlag
{
	NSParameterAssert(localPath);
	NSParameterAssert(remoteDirectoryPath);
	NSAssert([remoteDirectoryPath hasPrefix:@"/"], @"remoteDirectoryPath must be an absolute path!");
	
	//Expand any tilde's in the localPath
	localPath = [localPath stringByExpandingTildeInPath];
	//Resolve localPath, if it's a symbolic link.
	localPath = [localPath stringByResolvingSymlinksInPath];
	
	//Ensure we actually have something to upload
	BOOL isDirectory = NO;
	if (![[NSFileManager defaultManager] fileExistsAtPath:localPath isDirectory:&isDirectory])
		return nil;

	NSString *destinationRemotePath = [remoteDirectoryPath stringByAppendingPathComponent:[localPath lastPathComponent]];
	if (!isDirectory)
	{
		//Don't upload hidden files if we're not supposed to.
		if (ignoreHiddenItemsFlag && [[localPath lastPathComponent] hasPrefix:@"."])
			return nil;
		
		//We're uploading a file.
		return [self _uploadFile:localPath
						 toFile:destinationRemotePath
		   checkRemoteExistence:NO
					   delegate:nil];
	}
	
	//We're uploading a directory
	return [self _recursivelyUploadDirectoryAtLocalPath:localPath
									  toRemoteDirectory:destinationRemotePath
										   parentRecord:nil //there is no parent, as this first call is the root record!
									  ignoreHiddenItems:ignoreHiddenItemsFlag];
}

- (CKTransferRecord *)_recursivelyUploadDirectoryAtLocalPath:(NSString *)localPath
										   toRemoteDirectory:(NSString *)remoteDirectoryPath
												parentRecord:(CKTransferRecord *)parentRecord
										   ignoreHiddenItems:(BOOL)ignoreHiddenItemsFlag
{
	NSParameterAssert(localPath);
	NSParameterAssert(remoteDirectoryPath);
	
	/* Encapsulate the method with its own autorelease pool to quickly deallocate all autoreleased memory */
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[self createDirectory:remoteDirectoryPath];
	//Make a record for this directory, and add it as a child of the parent
	CKTransferRecord *thisDirectoryRecord = [CKTransferRecord uploadRecordForConnection:self
																		sourceLocalPath:localPath
																  destinationRemotePath:remoteDirectoryPath
																				   size:0 
																			isDirectory:YES];
	if (parentRecord)
		[parentRecord addChild:thisDirectoryRecord];
	
    NSError *error = nil;
	NSEnumerator *directoryContentsEnumerator = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:localPath error:&error] objectEnumerator];
	NSString *thisFilename;
	while ((thisFilename = [directoryContentsEnumerator nextObject]))
	{
		//Don't upload hidden files if we're not supposed to.
		if (ignoreHiddenItemsFlag && [thisFilename hasPrefix:@"."])
			continue;
		
		NSString *thisLocalPath = [localPath stringByAppendingPathComponent:thisFilename];
		NSString *thisRemotePath = [remoteDirectoryPath stringByAppendingPathComponent:thisFilename];
		
		BOOL thisItemIsADirectory = NO;
		[[NSFileManager defaultManager] fileExistsAtPath:thisLocalPath isDirectory:&thisItemIsADirectory];
		
		if (thisItemIsADirectory)
		{
			[self _recursivelyUploadDirectoryAtLocalPath:thisLocalPath
									   toRemoteDirectory:thisRemotePath
											parentRecord:thisDirectoryRecord
									   ignoreHiddenItems:ignoreHiddenItemsFlag];
			continue;
		}
		
		//We're uploading a file
		CKTransferRecord *thisItemUploadRecord = [self _uploadFile:thisLocalPath
															toFile:thisRemotePath
											  checkRemoteExistence:NO
														  delegate:nil];
		[thisDirectoryRecord addChild:thisItemUploadRecord];
	}
	
	//Since thisDirectoryRecord was autoreleased, we must retain it to avoid having it released.
	[thisDirectoryRecord retain];
	
	//Drain the pool and release it.
	[pool release];

	return [thisDirectoryRecord autorelease];
}

- (CKTransferRecord *)_uploadFile:(NSString *)localPath 
						   toFile:(NSString *)remotePath 
			 checkRemoteExistence:(BOOL)flag 
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

- (CKTransferRecord *)resumeUploadFile:(NSString *)localPath 
								toFile:(NSString *)remotePath 
							fileOffset:(unsigned long long)offset
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

/*
- (CKTransferRecord *)recursivelyUpload:(NSString *)localPath
									 to:(NSString *)remotePath
								   root:(CKTransferRecord *)root
							   rootPath:(NSString *)rootPath
					  ignoreHiddenFiles:(BOOL)ignoreHiddenFilesFlag
{
	NSFileManager *fm = [NSFileManager defaultManager];
	CKTransferRecord *record;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL isDir;
	
	//create this directory
	[self createDirectory:remotePath];
	
	NSEnumerator *e = [[fm directoryContentsAtPath:localPath] objectEnumerator];
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
			if ([[root path] isEqualToString:@"/"])
			{
				CKTransferRecord *parent = [self recursiveRecordWithPath:[[record name] stringByDeletingLastPathComponent] root:root];
				root = parent;
				[root setName:[[root name] lastPathComponent]];		
				[record setName:[[record name] lastPathComponent]];		
				[root addContent:record];
			}
			else
			{
				[self _mergeRecord:record into:root];
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
		if ([[root path] isEqualToString:@"/"])
		{
			root = record;
			[root setUpload:YES];
			[root setName:[[root name] lastPathComponent]];		
		}
		else
		{
			[self _mergeRecord:record into:root];
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
*/

#pragma mark Downloading
- (CKTransferRecord *)downloadFile:(NSString *)remotePath 
					   toDirectory:(NSString *)dirPath 
						 overwrite:(BOOL)flag
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

- (CKTransferRecord *)resumeDownloadFile:(NSString *)remotePath
							 toDirectory:(NSString *)dirPath
							  fileOffset:(unsigned long long)offset
								delegate:(id)delegate
{
	SUBCLASS_RESPONSIBLE
	return nil;
}

#pragma mark Accessors
- (BOOL)isBusy
{
	return NO;
}

- (unsigned)numberOfTransfers
{
	return 0;
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


#pragma mark Cancellation
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


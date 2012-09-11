//
//  CKUploader.m
//  Connection
//
//  Created by Mike Abdullah on 14/11/2011.
//  Copyright (c) 2011 Karelia Software. All rights reserved.
//

#import "CKUploader.h"

#import "CKConnectionRegistry.h"
#import "UKMainThreadProxy.h"

#import <CURLHandle/CURLFTPSession.h>
#import "CK2SFTPSession.h"
#import "CKWebDAVConnection.h"


@interface CKSFTPUploader : CKUploader <CK2SFTPSessionDelegate, NSURLAuthenticationChallengeSender>
{
@private
    CK2SFTPSession      *_session;
    NSOperationQueue    *_queue;
    NSOperationQueue    *_startupQueue;
    
    NSURLAuthenticationChallenge    *_challenge;
    NSURLAuthenticationChallenge    *_mainThreadChallenge;
}

@property(nonatomic, retain, readonly) CK2SFTPSession *SFTPSession;

@end


#pragma mark -


@interface CKFTPUploader : CKUploader <CURLFTPSessionDelegate, NSURLAuthenticationChallengeSender>
{
@private
    CURLFTPSession      *_session;
    NSURL               *_URL;
    NSOperationQueue    *_queue;
    BOOL                _started;
    
    NSURLAuthenticationChallenge    *_challenge;
}

@property(nonatomic, retain, readonly) CURLFTPSession *FTPSession;

@end


#pragma mark -


@interface CKLocalFileUploader : CKUploader <NSStreamDelegate>
{
  @private
    NSURL   *_baseURL;
    
    NSMutableArray  *_queue;
    
    CKTransferRecord    *_currentTransferRecord;
    NSOutputStream      *_writingStream;
    NSInputStream       *_inputStream;
    NSMutableData       *_buffer;
    NSURL               *_URLForWritingTo;
}

- (void)addOperation:(NSOperation *)operation;
@end


#pragma mark -


@implementation CKUploader

#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request filePosixPermissions:(unsigned long)customPermissions options:(CKUploadingOptions)options;
{
    if (self = [self init])
    {
        _request = [request copy];
        _permissions = customPermissions;
        _options = options;
        
        _connection = [[[CKConnectionRegistry sharedConnectionRegistry] connectionWithRequest:request] retain];
        [_connection setDelegate:self];
        
        _rootRecord = [[CKTransferRecord rootRecordWithPath:[[request URL] path]] retain];
        _baseRecord = [_rootRecord retain];
    }
    return self;
}

+ (CKUploader *)uploaderWithRequest:(NSURLRequest *)request
               filePosixPermissions:(NSNumber *)customPermissions
                            options:(CKUploadingOptions)options;
{
    NSParameterAssert(request);
    
    NSString *scheme = [[request URL] scheme];
    
    Class class;
    if ([scheme isEqualToString:@"sftp"] || [scheme isEqualToString:@"ssh"])
    {
        class = [CKSFTPUploader class];
    }
    else if ([scheme isEqualToString:@"ftp"] && [[NSUserDefaults standardUserDefaults] boolForKey:@"useCURLForFTP"])
    {
        class = [CKFTPUploader class];
    }
    else if ([scheme isEqualToString:@"file"])
    {
        class = [CKLocalFileUploader class];
    }
    else
    {
        class = [self class];
    }
    
    return [[[class alloc] initWithRequest:request
                      filePosixPermissions:(customPermissions ? [customPermissions unsignedLongValue] : 0644)
                                   options:options] autorelease];
}

- (void)dealloc
{
    [_connection setDelegate:nil];
    
    [_request release];
    [_connection release];
    [_rootRecord release];
    [_baseRecord release];
    
    [super dealloc];
}

#pragma mark Properties

@synthesize delegate = _delegate;

@synthesize options = _options;
@synthesize rootTransferRecord = _rootRecord;
@synthesize baseTransferRecord = _baseRecord;

- (unsigned long)posixPermissionsForPath:(NSString *)path isDirectory:(BOOL)directory;
{
    unsigned long result = _permissions;
    if (directory) result = [[self class] posixPermissionsForDirectoryFromFilePermissions:result];
    return result;
}

+ (unsigned long)posixPermissionsForDirectoryFromFilePermissions:(unsigned long)filePermissions;
{
    return (filePermissions | 0111);
}

#pragma mark Publishing

/*  Creates the specified directory including any parent directories that haven't already been queued for creation.
 *  Returns a CKTransferRecord used to represent the directory during publishing.
 */
- (CKTransferRecord *)createDirectoryAtPath:(NSString *)path;
{
    NSParameterAssert(path);
    NSAssert([NSThread isMainThread], @"CKUploader can only be used on main thread");
    
    
    if (!(_options & CKUploadingDryRun)) [_connection connect];	// ensure we're connected
    
    
    if ([path isEqualToString:@"/"] || [path isEqualToString:@""]) // The root for absolute and relative paths
    {
        return [self rootTransferRecord];
    }
    
    
    // Ensure the parent directory is created first
    NSString *parentDirectoryPath = [path stringByDeletingLastPathComponent];
    CKTransferRecord *parent = [self createDirectoryAtPath:parentDirectoryPath];
    
    
    // Create the directory if it hasn't been already
    CKTransferRecord *result = nil;
    int i;
    for (i = 0; i < [[parent contents] count]; i++)
    {
        CKTransferRecord *aRecord = [[parent contents] objectAtIndex:i];
        if ([[aRecord name] isEqualToString:[path lastPathComponent]])
        {
            result = aRecord;
            break;
        }
    }
    
    if (!result)
    {
        // This code will not set permissions for the document root or its parent directories as the
        // document root is created before this code gets called
        [_connection createDirectoryAtPath:path
                          posixPermissions:[NSNumber numberWithUnsignedLong:[self posixPermissionsForPath:path isDirectory:YES]]];
        
        result = [CKTransferRecord recordWithName:[path lastPathComponent] size:0];
        [parent addContent:result];
    }
    
    return result;
}

- (void)willUploadToPath:(NSString *)path;
{
    [self createDirectoryAtPath:[path stringByDeletingLastPathComponent]];
    
    if (_options & CKUploadingDeleteExistingFileFirst)
	{
		[_connection deleteFile:path];
	}
}

- (void)didEnqueueUpload:(CKTransferRecord *)record toPath:(NSString *)path
{
    _hasUploads = YES;
    
    // Need to use -setName: otherwise the record will have the full path as its name
    [record setName:[path lastPathComponent]];
    
    CKTransferRecord *parent = [self createDirectoryAtPath:[path stringByDeletingLastPathComponent]];
    [parent addContent:record];
}

- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path;
{
    [self willUploadToPath:path];
    
    CKTransferRecord *result = [_connection uploadData:data
                                                toPath:path
                                      posixPermissions:[NSNumber numberWithUnsignedLong:[self posixPermissionsForPath:path isDirectory:NO]]];
    
    [self didEnqueueUpload:result toPath:path];
    return result;
}

- (CKTransferRecord *)uploadFileAtURL:(NSURL *)url toPath:(NSString *)path;
{
    [self willUploadToPath:path];
    
    CKTransferRecord *result = [_connection uploadFileAtURL:url
                                                toPath:path
                                           posixPermissions:[NSNumber numberWithUnsignedLong:[self posixPermissionsForPath:path isDirectory:NO]]];
    
    [self didEnqueueUpload:result toPath:path];
    return result;
}

- (void)finishUploading;
{
    if (!_hasUploads)   // tell the delegate right away since there's nothing to do
    {
        [[self delegate] uploaderDidFinishUploading:self];
    }
    
    [_connection disconnect];   // will inform delegate once disconnected
}

- (void)cancel;
{
    [_connection forceDisconnect];
    [_connection setDelegate:nil];
}

#pragma mark Connection Delegate

- (void)connection:(id <CKPublishingConnection>)con didDisconnectFromHost:(NSString *)host;
{
    if (!_connection) return; // we've already finished in which case
    
    
    // Case 39234: It looks like ConnectionKit is sending this delegate method in the event of the
    // data connection closing (or it might even be the command connection), probably due to a
    // period of inactivity. In such a case, it's really not a cause to consider publishing
    // finished! To see if I am right on this, we will log that such a scenario occurred for now.
    // Mike.
    
    /*if ([self status] == KTPublishingEngineStatusUploading &&
                                                            ![con isConnected] &&
                                                            [[(CKAbstractQueueConnection *)con commandQueue] count] == 0)
    {
        [self finishPublishing:YES error:nil];
    }
    else
    {
        NSLog(@"%@ delegate method received, but connection still appears to be publishing", NSStringFromSelector(_cmd));
    }*/
    
    
    // If no uploads, delegate has already been informed. And if so, the connection is unlikely to need to disconnect. But you never know, it might have been connected accidentally
    if (_hasUploads)    
    {
        [[self delegate] uploaderDidFinishUploading:self];
    }
}

- (void)connection:(id<CKPublishingConnection>)con didReceiveError:(NSError *)error;
{
    NSInteger code = [error code];
    
    if ([[error userInfo] objectForKey:ConnectionDirectoryExistsKey]) 
	{
		return; //don't alert users to the fact it already exists, silently fail
	}
	else if (code == 550 || [[[error userInfo] objectForKey:@"protocol"] isEqualToString:@"createDirectory:"] )
	{
		return;
	}
	else if ([con isKindOfClass:[CKWebDAVConnection class]] && 
			 ([[[error userInfo] objectForKey:@"directory"] isEqualToString:@"/"] || code == 409 || code == 204 || code == 404 || code == 405))
	{
		// web dav returns a 409 if we try to create / .... which is fair enough!
		// web dav returns a 204 if a file to delete is missing.
		// 404 if the file to delete doesn't exist
        // 405 if creating a directory that already exists
		
		return;
	}
	else
	{
		[[self delegate] uploader:self didFailWithError:error];
	}
}

- (void)connection:(id <CKPublishingConnection>)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // Hand off to the delegate for auth
    id <CKUploaderDelegate> delegate = [self delegate];
    if (delegate)
    {
        [[self delegate] uploader:self didReceiveAuthenticationChallenge:challenge];
    }
    else
    {
        if ([challenge previousFailureCount] == 0)
        {
            NSURLCredential *credential = [challenge proposedCredential];
            if (!credential)
            {
                credential = [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:[challenge protectionSpace]];
            }
            
            if (credential)
            {
                [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
                return;
            }
        }
        
        [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
    }
}

- (void)connection:(id<CKPublishingConnection>)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [[self delegate] uploader:self didCancelAuthenticationChallenge:challenge];
}

- (void)connection:(id <CKPublishingConnection>)con uploadDidBegin:(NSString *)remotePath;
{
    [[self delegate] uploader:self didBeginUploadToPath:remotePath];
}

- (void)connection:(id <CKPublishingConnection>)connection appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript;
{
	[[self delegate] uploader:self appendString:string toTranscript:transcript];
}

@end


#pragma mark -


@interface CKWriteContentsOfURLToSFTPHandleOperation : NSOperation
{
@private
    NSURL               *_URL;
    NSString            *_path;
    CKSFTPUploader      *_engine;
    CKTransferRecord    *_record;
}

- (id)initWithURL:(NSURL *)URL path:(NSString *)path uploader:(CKSFTPUploader *)uploader transferRecord:(CKTransferRecord *)record;

@end


#pragma mark -


@implementation CKSFTPUploader

#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request filePosixPermissions:(unsigned long)customPermissions options:(CKUploadingOptions)options;
{
    if (self = [super initWithRequest:request filePosixPermissions:customPermissions options:options])
    {
        // HACK clear out super's connection ref
        [self setValue:nil forKey:@"connection"];
        
        _queue = [[NSOperationQueue alloc] init];
        [_queue setMaxConcurrentOperationCount:1];
        [_queue setSuspended:YES];  // we'll resume once authenticated
        
        _session = [[CK2SFTPSession alloc] initWithURL:[request URL] delegate:self startImmediately:NO];
    }
    
    return self;
}

- (void)finishUploading;
{
    [super finishUploading];
    
    
    // Disconnect once all else is done
    NSOperation *closeOp = [[NSInvocationOperation alloc] initWithTarget:self
                                                                selector:@selector(threaded_finish)
                                                                  object:nil];
    
    NSArray *operations = [_queue operations];
    for (NSOperation *anOp in operations)
    {
        [closeOp addDependency:anOp];
    }
    
    [_queue addOperation:closeOp];
    [closeOp release];
    
}

- (void)threaded_finish;
{
    [[(id)[self delegate] mainThreadProxy] uploaderDidFinishUploading:self];
    
    [_session cancel];
    [_session release]; _session = nil;
}

- (void)cancel;
{
    // Stop any pending ops
    [_queue cancelAllOperations];
    
    // Close the connection as quick as possible
    NSOperation *closeOp = [[NSInvocationOperation alloc] initWithTarget:[self SFTPSession]
                                                                selector:@selector(cancel)
                                                                  object:nil];
    
    [closeOp setQueuePriority:NSOperationQueuePriorityVeryHigh];
    [_queue addOperation:closeOp];
    [closeOp release];
    
    // Clear out ivars, the actual objects will get torn down as the queue finishes its work
    [_queue release]; _queue = nil;
    [_session release]; _session = nil;
}

- (void)dealloc;
{
    [_session release];
    [_queue release];
    [_startupQueue release];
    
    [super dealloc];
}

#pragma mark Upload

- (void)didEnqueueUpload:(CKTransferRecord *)record toPath:(NSString *)path
{
    if (!_startupQueue && !([self options] & CKUploadingDryRun))
    {
        _startupQueue = [[NSOperationQueue alloc] init];
        NSOperation *op = [[NSInvocationOperation alloc] initWithTarget:[self SFTPSession] selector:@selector(start) object:nil];
        [_startupQueue addOperation:op];
        [op release];
    }
    
    [super didEnqueueUpload:record toPath:path];
}

- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path;
{
    CKTransferRecord *result = nil;
    
    if ([self SFTPSession])
    {
        result = [CKTransferRecord recordWithName:[path lastPathComponent] size:[data length]];
        
        
        NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(threaded_writeData:toPath:transferRecord:)
                                                                 target:self
                                                              arguments:[NSArray arrayWithObjects:data, path, result, nil]];
        
        NSInvocationOperation *op = [[NSInvocationOperation alloc] initWithInvocation:invocation];
        [_queue addOperation:op];
        [op release];
        
        
        
        [self didEnqueueUpload:result toPath:path];
    }
    
    return result;
}

- (CKTransferRecord *)uploadFileAtURL:(NSURL *)localURL toPath:(NSString *)path
{
    // Cheat and send non-file URLs direct
    if (![localURL isFileURL]) return [self uploadData:[NSData dataWithContentsOfURL:localURL] toPath:path];
    
    
    CKTransferRecord *result = nil;
    
    if ([self SFTPSession])
    {
        NSNumber *size = [[[NSFileManager defaultManager] attributesOfItemAtPath:[localURL path] error:NULL] objectForKey:NSFileSize];
        
        if (size)   // if size can't be determined, no chance of being able to upload
        {
            result = [CKTransferRecord recordWithName:[path lastPathComponent] size:[size unsignedLongLongValue]];
            [self didEnqueueUpload:result toPath:path];  // so record has correct path
            
            
            NSOperation *op = [[CKWriteContentsOfURLToSFTPHandleOperation alloc] initWithURL:localURL
                                                                                        path:path
                                                                                    uploader:self
                                                                              transferRecord:result];
            [_queue addOperation:op];
            [op release];
            
            
            
        }
    }
    
    return result;
}

- (BOOL)threaded_createDirectoryAtPath:(NSString *)path error:(NSError **)outError;
{
    CK2SFTPSession *sftpSession = [self SFTPSession];
    NSParameterAssert(sftpSession);
    
    
    NSError *error;
    BOOL result = [sftpSession createDirectoryAtPath:path
                         withIntermediateDirectories:YES
                                                mode:[self posixPermissionsForPath:path isDirectory:YES]
                                               error:&error];
    
    
    if (!result)
    {
        if (outError) *outError = error;
        
        // It's possible directory creation failed because there's already a FILE by the same name…
        if ([[error domain] isEqualToString:CK2LibSSH2SFTPErrorDomain] &&
            [error code] == LIBSSH2_FX_FAILURE)
        {
            NSString *failedPath = [[error userInfo] objectForKey:NSFilePathErrorKey];  // might be a parent dir
            if (failedPath)
            {
                // …so try to destroy that file…
                if ([sftpSession removeFileAtPath:failedPath error:outError])
                {
                    // …then create the directory
                    if ([sftpSession createDirectoryAtPath:failedPath
                               withIntermediateDirectories:YES
                                                      mode:[self posixPermissionsForPath:failedPath isDirectory:YES]
                                                     error:outError])
                    {
                        // And finally, might still need to make some child dirs
                        if ([failedPath isEqualToString:path])
                        {
                            result = YES;
                        }
                        else
                        {
                            result = [self threaded_createDirectoryAtPath:path error:outError];
                        }
                    }
                }
            }
        }
    }
    
    return result;
}

- (CK2SFTPFileHandle *)threaded_openHandleAtPath:(NSString *)path error:(NSError **)outError;
{
    CK2SFTPSession *sftpSession = [self SFTPSession];
    NSParameterAssert(sftpSession);
    
    
    NSError *error;
    CK2SFTPFileHandle *result = [sftpSession openHandleAtPath:path
                                                        flags:LIBSSH2_FXF_WRITE|LIBSSH2_FXF_CREAT|LIBSSH2_FXF_TRUNC
                                                         mode:[self posixPermissionsForPath:path isDirectory:NO]
                                                        error:&error];
    
    if (!result)
    {
        if (outError) *outError = error;
        
        if ([[error domain] isEqualToString:CK2LibSSH2SFTPErrorDomain] &&
            [error code] == LIBSSH2_FX_NO_SUCH_FILE)
        {
            // Parent directory probably doesn't exist, so create it
            BOOL madeDir = [self threaded_createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                                                          error:outError];
            
            if (madeDir)
            {
                result = [sftpSession openHandleAtPath:path
                                                 flags:LIBSSH2_FXF_WRITE|LIBSSH2_FXF_CREAT|LIBSSH2_FXF_TRUNC
                                                  mode:[self posixPermissionsForPath:path isDirectory:NO]
                                                 error:outError];
            }
        }
    }
    
    if (result)
    {
        [[(id)[self delegate] mainThreadProxy] uploader:self didBeginUploadToPath:path];
    }
    
    return result;
}

- (void)threaded_writeData:(NSData *)data toPath:(NSString *)path transferRecord:(CKTransferRecord *)record;
{
    CK2SFTPSession *sftpSession = [self SFTPSession];
    NSParameterAssert(sftpSession);
    
    NSError *error;
    CK2SFTPFileHandle *handle = [self threaded_openHandleAtPath:path error:&error];
    
    if (handle)
    {
        [[self mainThreadProxy] transferDidBegin:record];
        
        BOOL result = [handle writeData:data error:&error];
        [handle closeFile];         // don't really care if this fails
        
        if (result)
        {
            // Handle servers which ignore initial permissions
            result = [sftpSession setPermissions:[self posixPermissionsForPath:path isDirectory:NO] forItemAtPath:path error:&error];
        }
        
        if (!result) handle = nil;  // so error gets sent
    }
    
    [[record mainThreadProxy] transferDidFinish:record
                                                                error:(handle ? nil : error)];
}

- (void)transferDidBegin:(CKTransferRecord *)record;
{
    [record transferDidBegin:record];
    //[[self delegate] publishingEngine:self didBeginUploadToPath:[record path]];
}

#pragma mark SFTP session

@synthesize SFTPSession = _session;

- (void)SFTPSessionDidInitialize:(CK2SFTPSession *)session;
{
    [_queue setSuspended:NO];
}

- (void)SFTPSession:(CK2SFTPSession *)session didFailWithError:(NSError *)error;
{
    [[self mainThreadProxy] connection:nil didReceiveError:error];
}

- (void)SFTPSession:(CK2SFTPSession *)session didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if ([challenge previousFailureCount] == 0)
    {
        NSData *fingerprint = [session hostkeyHashForType:LIBSSH2_HOSTKEY_HASH_SHA1];
        
        [self SFTPSession:session appendStringToTranscript:[NSString stringWithFormat:
                                                            @"Fingerprint: %@",
                                                            fingerprint]
                 received:YES];
    }
    
    _challenge = [challenge retain];
    
    _mainThreadChallenge = [[NSURLAuthenticationChallenge alloc] initWithAuthenticationChallenge:challenge sender:self];
    [[self mainThreadProxy] connection:nil didReceiveAuthenticationChallenge:_mainThreadChallenge];
    [_mainThreadChallenge release]; // delegate will hold onto it we hope!
}

- (void)SFTPSession:(CK2SFTPSession *)session didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [[self mainThreadProxy] connection:nil didCancelAuthenticationChallenge:_mainThreadChallenge];
}

- (void)SFTPSession:(CK2SFTPSession *)session appendStringToTranscript:(NSString *)string received:(BOOL)received;
{
    [[(NSObject *)[self delegate] mainThreadProxy] uploader:self
                                               appendString:string
                                               toTranscript:(received ? CKTranscriptReceived : CKTranscriptSent)];
}

#pragma mark NSURLAuthenticationChallengeSender

- (void)threaded_useCredentialForCurrentAuthenticationChallenge:(NSURLCredential *)credential;
{
    NSURLAuthenticationChallenge *realChallenge = _challenge;
    _challenge = nil;   // gets released in a moment; just want to clear out the ivar right now
    
    [[realChallenge sender] useCredential:credential forAuthenticationChallenge:realChallenge];
    [realChallenge release];
}

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSInvocationOperation *op = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(threaded_useCredentialForCurrentAuthenticationChallenge:) object:credential];
    
    NSOperationQueue *queue = ([_queue isSuspended] ? _startupQueue : _queue);
    [queue addOperation:op];
    [op release];
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSInvocationOperation *op = [[NSInvocationOperation alloc] initWithTarget:[_challenge sender] selector:_cmd object:_challenge];
    NSOperationQueue *queue = ([_queue isSuspended] ? _startupQueue : _queue);
    [queue addOperation:op];
    [op release];
    
    [_challenge release]; _challenge = nil;
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSInvocationOperation *op = [[NSInvocationOperation alloc] initWithTarget:[_challenge sender] selector:_cmd object:_challenge];
    NSOperationQueue *queue = ([_queue isSuspended] ? _startupQueue : _queue);
    [queue addOperation:op];
    [op release];
    
    [_challenge release]; _challenge = nil;
}

@end


#pragma mark -


@implementation CKWriteContentsOfURLToSFTPHandleOperation

- (id)initWithURL:(NSURL *)URL path:(NSString *)path uploader:(CKSFTPUploader *)uploader transferRecord:(CKTransferRecord *)record;
{
    if (self = [self init])
    {
        _URL = [URL copy];
        _path = [path copy];   // copy now since it's not threadsafe
        _engine = [uploader retain];
        _record = [record retain];
    }
    
    return self;
}

- (void)dealloc;
{
    [_URL release];
    [_path release];
    [_engine release];
    [_record release];
    
    [super dealloc];
}

- (void)main
{
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:[_URL path]];
    
    if (handle)
    {
        NSError *error;
        CK2SFTPFileHandle *sftpHandle = [_engine threaded_openHandleAtPath:_path error:&error];
        
        if (sftpHandle)
        {
            [[_engine mainThreadProxy] transferDidBegin:_record];
            
            while (YES)
            {
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                {{
                    if ([self isCancelled]) break;
                    
                    NSData *data = [handle readDataOfLength:CK2SFTPPreferredChunkSize];
                    if (![data length]) break;
                    if ([self isCancelled]) break;
                    
                    if (![sftpHandle writeData:data error:&error])
                    {
                        [sftpHandle closeFile]; // don't care if it fails
                        sftpHandle = nil;   // so error gets sent
                        
                        // clean up memory stuff
                        [error retain];
                        [pool release];
                        [error autorelease];
                        break;
                    }
                    
                    [[_record mainThreadProxy] transfer:_record transferredDataOfLength:[data length]];
                }}
                [pool release];
            }
        }
        
        [handle closeFile];
        [sftpHandle closeFile];
        
        if (![self isCancelled] && sftpHandle)
        {
            // Handle servers which ignore initial permissions setting
            CK2SFTPSession *session = [_engine SFTPSession];
            NSAssert(session, @"Need session to set permissions");
            
            BOOL result = [session setPermissions:[_engine posixPermissionsForPath:_path isDirectory:NO]
                                    forItemAtPath:_path
                                            error:&error];
            if (!result) sftpHandle = nil;
        }
        
        [[_record mainThreadProxy] transferDidFinish:_record error:(sftpHandle ? nil : error)];
    }
    else
    {
        [[_record mainThreadProxy] transferDidFinish:_record error:nil];
    }
}

@end


#pragma mark -


@implementation CKFTPUploader

#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request filePosixPermissions:(unsigned long)customPermissions options:(CKUploadingOptions)options;
{
    if (self = [super initWithRequest:request filePosixPermissions:customPermissions options:options])
    {
        // HACK clear out super's connection ref
        [self setValue:nil forKey:@"connection"];
        
        _URL = [[request URL] copy];
        
        _queue = [[NSOperationQueue alloc] init];
        [_queue setMaxConcurrentOperationCount:1];
        [_queue setSuspended:YES];  // we'll resume once authenticated
        
        _session = [[CURLFTPSession alloc] initWithRequest:request];
        [_session setDelegate:self];
    }
    
    return self;
}

- (void)finishUploading;
{
    [super finishUploading];
    
    
    // Disconnect once all else is done
    NSOperation *closeOp = [[NSInvocationOperation alloc] initWithTarget:self
                                                                selector:@selector(threaded_finish)
                                                                  object:nil];
    
    NSArray *operations = [_queue operations];
    for (NSOperation *anOp in operations)
    {
        [closeOp addDependency:anOp];
    }
    
    [_queue addOperation:closeOp];
    [closeOp release];
    
}

- (void)threaded_finish;
{
    [[(id)[self delegate] mainThreadProxy] uploaderDidFinishUploading:self];
    
    [_session release]; _session = nil;
}

- (void)cancel;
{
    // Stop any ops
    [_queue cancelAllOperations];
    [_session cancel];
    
    // Clear out ivars, the actual objects will get torn down as the queue finishes its work
    [_queue release]; _queue = nil;
    [_session release]; _session = nil;
}

- (void)dealloc;
{
    [_session setDelegate:nil];
    [_session release];
    [_URL release];
    [_queue release];
    
    [super dealloc];
}

#pragma mark Upload

- (void)didEnqueueUpload:(CKTransferRecord *)record toPath:(NSString *)path
{
    if (!_started && !([self options] & CKUploadingDryRun))
    {
        NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:[_URL host]
                                                                            port:[[_URL port] integerValue]
                                                                        protocol:NSURLProtectionSpaceFTP
                                                                           realm:nil
                                                            authenticationMethod:NSURLAuthenticationMethodDefault];
        
        NSURLCredential *credential = [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:space];
        
        _challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                                proposedCredential:credential
                                                              previousFailureCount:0
                                                                   failureResponse:nil
                                                                             error:nil
                                                                            sender:self];
        [space release];
        
        [[self delegate] uploader:self didReceiveAuthenticationChallenge:_challenge];
        _started = YES;
    }
    
    [super didEnqueueUpload:record toPath:path];
}

- (void)uploadToPath:(NSString *)path
              record:(CKTransferRecord *)record
          usingBlock:(BOOL (^)(NSError **outError, void (^progressBlock)(NSUInteger bytesWritten)))uploadBlock;
{
    [_queue addOperationWithBlock:^{
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [[self delegate] uploader:self didBeginUploadToPath:path];
            [record transferDidBegin:record];
        }];
        
        NSError *error;
        BOOL result = uploadBlock(&error, ^(NSUInteger bytesWritten) {
            
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [record transfer:record transferredDataOfLength:bytesWritten];
            }];
        });
        
        if (result)
        {
            error = nil;    // so block can reference it
        }
        else
        {
            NSString *description = ([error respondsToSelector:@selector(debugDescription)] ?
                                     [error performSelector:@selector(debugDescription)] :
                                     [error description]);
            
            [self FTPSession:[self FTPSession] didReceiveDebugInfo:description ofType:CKTranscriptReceived];
        }
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [record transferDidFinish:record error:error];
        }];
    }];
        
    [self didEnqueueUpload:record toPath:path];
}

- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path;
{
    CKTransferRecord *result = nil;
    
    if ([self FTPSession])
    {
        result = [CKTransferRecord recordWithName:[path lastPathComponent] size:[data length]];
        
        [self uploadToPath:path record:result usingBlock:^BOOL(NSError **outError, void (^progressBlock)(NSUInteger bytesWritten)) {
            
            return [[self FTPSession] createFileAtPath:path
                                              contents:data
                           withIntermediateDirectories:YES
                                                 error:outError];
        }];
    }
    
    return result;
}

- (CKTransferRecord *)uploadFileAtURL:(NSURL *)localURL toPath:(NSString *)path
{
    CKTransferRecord *record = nil;
    
    if ([self FTPSession])
    {
        NSNumber *size;
        if (![localURL getResourceValue:&size forKey:NSURLFileSizeKey error:NULL]) return nil;
        
        record = [CKTransferRecord recordWithName:[path lastPathComponent] size:[size unsignedLongLongValue]];
        
        [self uploadToPath:path record:record usingBlock:^BOOL(NSError **outError, void (^progressBlock)(NSUInteger bytesWritten)) {
            
            return [[self FTPSession] createFileAtPath:path withContentsOfURL:localURL withIntermediateDirectories:YES error:outError progressBlock:progressBlock];
        }];
    }
    
    return record;
}

#pragma mark FTP Session

@synthesize FTPSession = _session;

- (void)FTPSession:(CURLFTPSession *)session didReceiveDebugInfo:(NSString *)string ofType:(curl_infotype)type;
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [[self delegate] uploader:self
                     appendString:string
                     toTranscript:(type == CURLINFO_HEADER_IN ? CKTranscriptReceived : CKTranscriptSent)];
    }];
}

#pragma mark NSURLAuthenticationChallengeSender

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSParameterAssert(challenge == _challenge);
    _challenge = nil;   // will release in a bit
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        [_session useCredential:credential];
        
        NSError *error;
        NSString *path = [_session homeDirectoryPath:&error];
        
        // Somewhat of a HACK: if the error is with SSL, log it and then carry on
        if (!path && [error code] == CURLE_SSL_CACERT && [[error domain] isEqualToString:CURLcodeErrorDomain])
        {
            [self FTPSession:_session
         didReceiveDebugInfo:[NSString stringWithFormat:@"Falling back to plain FTP after TLS/SSL error: %@", [error localizedDescription]]
                      ofType:CURLINFO_HEADER_IN];
            
            NSMutableURLRequest *request = [[_session baseRequest] mutableCopy];
            [request curl_setDesiredSSLLevel:CURLUSESSL_NONE];
            [_session setBaseRequest:request];
            
            path = [_session homeDirectoryPath:&error];
        }
        
        if (path)
        {
            [[NSURLCredentialStorage sharedCredentialStorage] setDefaultCredential:credential forProtectionSpace:[challenge protectionSpace]];
            [_queue setSuspended:NO];
        }
        else if ([[error domain] isEqualToString:NSURLErrorDomain] && [error code] == NSURLErrorUserAuthenticationRequired)
        {
            _challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:[challenge protectionSpace]
                                                                    proposedCredential:credential
                                                                  previousFailureCount:([challenge previousFailureCount] + 1)
                                                                       failureResponse:nil
                                                                                 error:error
                                                                                sender:self];
            
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [[self delegate] uploader:self didReceiveAuthenticationChallenge:_challenge];
            }];
        }
        else
        {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [[self delegate] uploader:self didFailWithError:error];
            }];
        }
        
        [challenge release];
    });
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [self useCredential:nil forAuthenticationChallenge:challenge];
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSParameterAssert(challenge == _challenge);
    [_challenge release]; _challenge = nil;
    
    [[self delegate] uploader:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                                        code:NSURLErrorUserCancelledAuthentication
                                                                    userInfo:nil]];
}

@end


#pragma mark -


@implementation CKLocalFileUploader

#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request filePosixPermissions:(unsigned long)customPermissions options:(CKUploadingOptions)options;
{
    if (self = [super initWithRequest:request filePosixPermissions:customPermissions options:options])
    {
        // HACK clear out super's connection ref
        [self setValue:nil forKey:@"connection"];
        
        _baseURL = [[request URL] copy];
        _queue = [[NSMutableArray alloc] init];
    }
    
    return self;
}

- (void)finishUploading;
{
    [self addOperation:[NSBlockOperation blockOperationWithBlock:^{
        [[self delegate] uploaderDidFinishUploading:self];
    }]];
}

- (void)cancelCurrentOperation;
{
    // Stop any ops
    [_writingStream close];
    [_inputStream close];
    
    [_writingStream release]; _writingStream = nil;
    [_inputStream release]; _inputStream = nil;
}

- (void)cancel;
{
    [self cancelCurrentOperation];
    [_queue release]; _queue = nil;
}

- (void)dealloc;
{
    [_baseURL release];
    [_queue release];
    [_currentTransferRecord release];
    [_inputStream release];
    [_writingStream release];
    [_URLForWritingTo release];
    
    [super dealloc];
}

#pragma mark Upload

- (void)setupOutputStream;
{
    // Need to pass an absolute URL to NSOutputStream for it to work proper-like. http://openradar.appspot.com/radar?id=1643404
    NSAssert(_URLForWritingTo, @"Can't write to nil!");
    [_writingStream release]; _writingStream = [[NSOutputStream alloc] initWithURL:[_URLForWritingTo absoluteURL] append:NO];
    
    [_writingStream setDelegate:self];
    [_writingStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [_writingStream open];
}

- (CKTransferRecord *)createFileAtPath:(NSString *)path withDataStream:(NSInputStream *)stream size:(unsigned long long)size;
{
    NSParameterAssert(stream);
    
    CKTransferRecord *result = [CKTransferRecord recordWithName:[path lastPathComponent] size:size];
    
    [self addOperation:[NSBlockOperation blockOperationWithBlock:^{
        
        NSAssert(_inputStream == nil, @"Can only create one file at a time");
        
        _currentTransferRecord = [result retain];
        
        _inputStream = [stream retain];
        [_inputStream setDelegate:self];
        [_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        [_inputStream open];
        
        NSURL *outputURL = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:path relativeToURL:_baseURL];
        [_URLForWritingTo release]; _URLForWritingTo = [outputURL copy];
        [self setupOutputStream];
        
        [[self delegate] uploader:self didBeginUploadToPath:path];
        [_currentTransferRecord transferDidBegin:_currentTransferRecord];
    }]];
    
    [self didEnqueueUpload:result toPath:path];
    return result;
}

- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path;
{
    NSParameterAssert(data);
    return [self createFileAtPath:path withDataStream:[NSInputStream inputStreamWithData:data] size:[data length]];
}

- (CKTransferRecord *)uploadFileAtURL:(NSURL *)localURL toPath:(NSString *)path
{
    NSParameterAssert(localURL);
    
    NSNumber *size;
    if (![localURL getResourceValue:&size forKey:NSURLFileSizeKey error:NULL]) return nil;
    
    NSInputStream *stream = [[NSInputStream alloc] initWithURL:localURL];
    if (!stream)
    {
        NSData *data = [[NSData alloc] initWithContentsOfURL:localURL];
        if (!data) return nil;
        
        stream = [[NSInputStream alloc] initWithData:data];
        [data release];
    }
    
    CKTransferRecord *result = [self createFileAtPath:path withDataStream:stream size:[size unsignedLongLongValue]];
    [stream release];
    return result;
}

#pragma mark Queue

- (void)addOperation:(NSOperation *)operation;
{
    [_queue addObject:operation];
    if ([_queue count] == 1)
    {
        // Defer starting the op so that caller can process the transfer record
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [operation start];
        }];
    }
}

- (void)finishCurrentOperationWithError:(NSError *)error;
{
    [self cancelCurrentOperation];
    
    [_currentTransferRecord transferDidFinish:_currentTransferRecord error:error];
    [_currentTransferRecord release]; _currentTransferRecord = nil;
    
    [_queue removeObjectAtIndex:0];
    if ([_queue count]) [[_queue objectAtIndex:0] start];
}

- (BOOL)writeAsMuchOfBufferAsSpaceAvailableAllows
{
    NSInteger written = [_writingStream write:[_buffer bytes] maxLength:[_buffer length]];
    if (written < 0)
    {
        // Bail out with error
        [self finishCurrentOperationWithError:[_writingStream streamError]];
        return NO;
    }
    
    [_buffer replaceBytesInRange:NSMakeRange(0, written) withBytes:NULL length:0];
    
    [_currentTransferRecord transfer:_currentTransferRecord transferredDataOfLength:written];
    
    return YES;
}

- (BOOL)finishCurrentOperationIfWritingIsFinished
{
    if (_inputStream == nil && [_buffer length] == 0)
    {
        unsigned long permissions = [self posixPermissionsForPath:nil isDirectory:NO];
        
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:permissions]
                                                               forKey:NSFilePosixPermissions];
        
        NSError *error;
        BOOL permissionsSuccess = [[NSFileManager defaultManager] setAttributes:attributes
                                                                   ofItemAtPath:[_URLForWritingTo path]
                                                                          error:&error];
        
        if (permissionsSuccess) error = nil;
        [self finishCurrentOperationWithError:nil];
        return YES;
    }
    
    return NO;
}

- (void)finishReading;
{
    [_buffer setLength:0];
    [_inputStream close];
    [_inputStream release]; _inputStream = nil;
    [self finishCurrentOperationIfWritingIsFinished];
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    if (eventCode & NSStreamEventErrorOccurred)
    {
        if (aStream == _writingStream)
        {
            // If it's because the parent folder doesn't exist yet, create it and retry
            NSError *error = [aStream streamError];
            if ([[error domain] isEqualToString:NSPOSIXErrorDomain] && [error code] == ENOENT)
            {
                NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                            [NSNumber numberWithUnsignedLong:[self posixPermissionsForPath:nil isDirectory:YES]],
                                            NSFilePosixPermissions,
                                            nil];
                
                NSURL *directoryURL = [_URLForWritingTo URLByDeletingLastPathComponent];
                BOOL success = NO;
                
                if ([NSFileManager instancesRespondToSelector:@selector(createDirectoryAtURL:withIntermediateDirectories:attributes:error:)])
                {
                    success = [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL
                                                       withIntermediateDirectories:YES
                                                                        attributes:attributes
                                                                             error:NULL];
                }
                else if ([directoryURL isFileURL])
                {
                    success = [[NSFileManager defaultManager] createDirectoryAtPath:[directoryURL path]
                                                        withIntermediateDirectories:YES
                                                                         attributes:attributes
                                                                              error:NULL];
                }
                
                if (success)
                {
                    [self setupOutputStream];
                    return;
                }
            }
        }
        
        
        // Report error
        [self finishCurrentOperationWithError:[aStream streamError]];
        return;
    }
    
    // Write out any remainder of the buffer
    if ([_writingStream hasSpaceAvailable] && [_buffer length])
    {
        [self writeAsMuchOfBufferAsSpaceAvailableAllows];
        
        // If the buffer is still full, write again when ready
        if ([_buffer length]) return;
        
        // That might have been the end of the file being written. If so, onto the next op!
        if ([self finishCurrentOperationIfWritingIsFinished]) return;
    }
    
    if ([_inputStream hasBytesAvailable] && [_writingStream hasSpaceAvailable])
    {
        // Prepare the buffer
        if (!_buffer) _buffer = [[NSMutableData alloc] init];
        [_buffer setLength:1024*1024];
        
        // Read a chunk of data
        NSInteger read = [_inputStream read:[_buffer mutableBytes] maxLength:[_buffer length]];
        if (read > 0)
        {
            // Clear out any wasted space in the buffer, then write it
            [_buffer replaceBytesInRange:NSMakeRange(read, [_buffer length] - read)
                               withBytes:NULL length:0];
            
            [self writeAsMuchOfBufferAsSpaceAvailableAllows];
        }
        else if (read == 0)
        {
            [self finishReading];
        }
        else
        {
            [self finishCurrentOperationWithError:[_inputStream streamError]];
        }
    }
    else if (aStream == _inputStream && [aStream streamStatus] == NSStreamStatusAtEnd)
    {
        // Streaming from NSData doesn't seem to ever give us a read return value of 0; instead get notified of the stream ending
        [self finishReading];
    }
}

@end


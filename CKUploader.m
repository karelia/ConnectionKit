//
//  CKUploader.m
//  Connection
//
//  Created by Mike Abdullah on 14/11/2011.
//  Copyright (c) 2011 Karelia Software. All rights reserved.
//

#import "CKUploader.h"

#import "CKConnectionRegistry.h"
#import "CKFileConnection.h"
#import "UKMainThreadProxy.h"

#import "CK2SFTPSession.h"


@interface CKSFTPUploader : CKUploader <CK2SFTPSessionDelegate>
{
@private
    CK2SFTPSession      *_session;
    NSOperationQueue    *_queue;
    BOOL                _sessionStarted;
}

@property(nonatomic, retain, readonly) CK2SFTPSession *SFTPSession;

@end


#pragma mark -


@implementation CKUploader

#pragma mark Lifecycle

- (id)initWithRequest:(CKConnectionRequest *)request filePosixPermissions:(unsigned long)customPermissions options:(CKUploadingOptions)options;
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

+ (CKUploader *)uploaderWithRequest:(CKConnectionRequest *)request
               filePosixPermissions:(NSNumber *)customPermissions
                            options:(CKUploadingOptions)options;
{
    NSParameterAssert(request);
    
    Class class = ([[[request URL] scheme] isEqualToString:@"sftp"] ? [CKSFTPUploader class] : [self class]);
    
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

@synthesize rootTransferRecord = _rootRecord;
@synthesize baseTransferRecord = _baseRecord;

- (unsigned long)posixPermissionsForPath:(NSString *)path isDirectory:(BOOL)directory;
{
    unsigned long result = _permissions;
    if (directory) result = (result | 0111);
    return result;
}

#pragma mark Publishing

/*  Creates the specified directory including any parent directories that haven't already been queued for creation.
 *  Returns a CKTransferRecord used to represent the directory during publishing.
 */
- (CKTransferRecord *)createDirectoryAtPath:(NSString *)path;
{
    NSParameterAssert(path);
    
    
    if ([path isEqualToString:@"/"] || [path isEqualToString:@""]) // The root for absolute and relative paths
    {
        return [self rootTransferRecord];
    }
    
    
    [_connection connect];	// ensure we're connected
    
    
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
    [_connection disconnect];
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
    
    [[self delegate] uploaderDidFinishUploading:self];
}

- (void)connection:(id<CKPublishingConnection>)con didReceiveError:(NSError *)error;
{
    if ([[error userInfo] objectForKey:ConnectionDirectoryExistsKey]) 
	{
		return; //don't alert users to the fact it already exists, silently fail
	}
	else if ([error code] == 550 || [[[error userInfo] objectForKey:@"protocol"] isEqualToString:@"createDirectory:"] )
	{
		return;
	}
	else if ([con isKindOfClass:NSClassFromString(@"WebDAVConnection")] && 
			 ([[[error userInfo] objectForKey:@"directory"] isEqualToString:@"/"] || [error code] == 409 || [error code] == 204 || [error code] == 404))
	{
		// web dav returns a 409 if we try to create / .... which is fair enough!
		// web dav returns a 204 if a file to delete is missing.
		// 404 if the file to delete doesn't exist
		
		return;
	}
	else if ([error code] == kSetPermissions) // File connection set permissions failed ... ignore this (why?)
	{
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

- (void)connection:(id <CKPublishingConnection>)connection appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript;
{
	[[self delegate] uploader:self appendString:string toTranscript:transcript];
}

@end


#pragma mark -


@interface SVWriteContentsOfURLToSFTPHandleOperation : NSOperation
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

- (id)initWithRequest:(CKConnectionRequest *)request filePosixPermissions:(unsigned long)customPermissions options:(CKUploadingOptions)options;
{
    if (self = [super initWithRequest:request filePosixPermissions:customPermissions options:options])
    {
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
    
    [super dealloc];
}

#pragma mark Upload

- (void)didEnqueueUpload:(CKTransferRecord *)record toDirectory:(CKTransferRecord *)parent;
{
    [parent addContent:record];
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

- (CKTransferRecord *)uploadContentsOfURL:(NSURL *)localURL toPath:(NSString *)path
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
            
            
            NSOperation *op = [[SVWriteContentsOfURLToSFTPHandleOperation alloc] initWithURL:localURL
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
    
    
    [sftpSession start];
    
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
    [sftpSession start];
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
    [[self delegate] uploader:self didFailWithError:error];
}

- (void)SFTPSession:(CK2SFTPSession *)session didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if ([challenge previousFailureCount] == 0)
    {
        NSData *fingerprint = [session hostkeyHashForType:LIBSSH2_HOSTKEY_HASH_SHA1];
        
        [self SFTPSession:session appendStringToTranscript:[NSString stringWithFormat:
                                                            @"Fingerprint: %@",
                                                            fingerprint]];
    }
    
    [[self mainThreadProxy] connection:nil didReceiveAuthenticationChallenge:challenge];
}

- (void)SFTPSession:(CK2SFTPSession *)session appendStringToTranscript:(NSString *)string;
{
    [[(NSObject *)[self delegate] mainThreadProxy] uploader:self appendString:string toTranscript:CKTranscriptSent];
}

@end


#pragma mark -


@implementation SVWriteContentsOfURLToSFTPHandleOperation

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
                @try
                {
                    if ([self isCancelled]) break;
                    
                    NSData *data = [handle readDataOfLength:CK2SFTPPreferredChunkSize];
                    if (![data length]) break;
                    if ([self isCancelled]) break;
                    
                    if (![sftpHandle writeData:data error:&error])
                    {
                        [sftpHandle closeFile]; // don't care if it fails
                        sftpHandle = nil;   // so error gets sent
                        break;
                    }
                    
                    [[_record mainThreadProxy] transfer:_record transferredDataOfLength:[data length]];
                }
                @finally
                {
                    [pool release];
                }
            }
        }
        
        [handle closeFile];
        [sftpHandle closeFile];
        
        [[_record mainThreadProxy] transferDidFinish:_record error:(sftpHandle ? nil : error)];
    }
    else
    {
        [[_record mainThreadProxy] transferDidFinish:_record error:nil];
    }
}

@end


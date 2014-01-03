//
//  CKUploader.m
//  Connection
//
//  Created by Mike Abdullah on 14/11/2011.
//  Copyright (c) 2011 Karelia Software. All rights reserved.
//

#import "CKUploader.h"

#import "CK2FileOperation.h"

#import <CURLHandle/CURLHandle.h>


@implementation CKUploader

#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request options:(CKUploadingOptions)options delegate:(id<CKUploaderDelegate>)delegate;
{
    if (self = [self init])
    {
        _request = [request copy];
        _options = options;
        _delegate = [delegate retain];
        _suspended = NO;
        
        if (!(_options & CKUploadingDryRun))
        {
            // Marshall all callbacks onto main queue, primarily for historical reasons, but also serialisation
            _fileManager = [CK2FileManager fileManagerWithDelegate:self
                                                     delegateQueue:[NSOperationQueue mainQueue]];
            [_fileManager retain];
        }
        
        _queue = [[NSMutableArray alloc] init];
        _recordsByOperation = [[NSMutableDictionary alloc] init];
        _rootRecord = [[CKTransferRecord rootRecordWithPath:[[request URL] path]] retain];
        _baseRecord = [_rootRecord retain];
    }
    return self;
}

+ (CKUploader *)uploaderWithRequest:(NSURLRequest *)request options:(CKUploadingOptions)options delegate:(id<CKUploaderDelegate>)delegate;
{
    NSParameterAssert(request);

    return [[[self alloc] initWithRequest:request options:options delegate:delegate] autorelease];
}

- (void)didBecomeInvalid;
{
    id <CKUploaderDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(uploaderDidBecomeInvalid:)])
    {
        [self.delegate uploaderDidBecomeInvalid:self];
    }
    
    [_delegate release]; _delegate = nil;
}

- (void)dealloc
{
    NSAssert(_queue.count == 0, @"%@ is being deallocated while there are still queued operations", self);
    [_fileManager setDelegate:nil];
    
    [_request release];
    [_fileManager release];
    [_rootRecord release];
    [_baseRecord release];
    [_recordsByOperation release];
    
    [super dealloc];
}

#pragma mark Properties

@synthesize delegate = _delegate;
@synthesize baseRequest = _request;
@synthesize options = _options;
@synthesize rootTransferRecord = _rootRecord;
@synthesize baseTransferRecord = _baseRecord;

- (NSNumber *)posixPermissionsForPath:(NSString *)path isDirectory:(BOOL)directory;
{
    NSNumber *result = (directory ?
                        self.baseRequest.curl_newDirectoryPermissions :
                        self.baseRequest.curl_newFilePermissions);
    return result;
}

#pragma mark Publishing

- (void)removeItemAtURL:(NSURL *)url;
{
    [self removeItemAtURL:url reportError:YES];
}

- (void)removeItemAtURL:(NSURL *)url reportError:(BOOL)reportError;
{
    __block CK2FileOperation *op = [_fileManager removeOperationWithURL:url completionHandler:^(NSError *error) {
        [self operation:op didFinish:(reportError ? error : nil)];
    }];
    
    [self addOperation:op];
}

- (CKTransferRecord *)uploadToURL:(NSURL *)url fromData:(NSData *)data;
{
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [self posixPermissionsForPath:[_fileManager.class pathOfURL:url] isDirectory:NO],
                                NSFilePosixPermissions,
                                nil];
    
    CK2FileOperation *op = [_fileManager createFileOperationWithURL:url
                                                           fromData:data
                                        withIntermediateDirectories:YES
                                                  openingAttributes:attributes
                                                  completionHandler:NULL];
    
    return [self uploadToURL:url usingOperation:op];
}

- (CKTransferRecord *)uploadToURL:(NSURL *)url fromFile:(NSURL *)fileURL;
{
    NSNumber *size;
    if (![fileURL getResourceValue:&size forKey:NSURLFileSizeKey error:NULL]) size = nil;
    
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [self posixPermissionsForPath:[_fileManager.class pathOfURL:url] isDirectory:NO],
                                NSFilePosixPermissions,
                                nil];
    
    CK2FileOperation *op = [_fileManager createFileOperationWithURL:url
                                                           fromFile:fileURL
                                        withIntermediateDirectories:YES
                                                  openingAttributes:attributes
                                                  completionHandler:NULL];
    
    return [self uploadToURL:url usingOperation:op];
}

static void *sOperationStateObservationContext = &sOperationStateObservationContext;

- (CKTransferRecord *)uploadToURL:(NSURL *)url usingOperation:(CK2FileOperation *)operation;
{
    NSParameterAssert(operation);
    
    // Create transfer record
    if (_options & CKUploadingDeleteExistingFileFirst)
	{
        // The file might not exist, so will fail in that case. We don't really care since should a deletion fail for a good reason, that ought to then cause the actual upload to fail
        [self removeItemAtURL:url reportError:NO];
	}
    
    CKTransferRecord *result = [self makeTransferRecordWithURL:url operation:operation];
    [_recordsByOperation setObject:result forKey:operation];
    
    
    // Enqueue upload
    [self addOperation:operation];
    
    
    // Notify delegate
    [self didAddTransferRecord:result];
    
    return result;
}

- (void)didAddTransferRecord:(CKTransferRecord *)record;
{
    id <CKUploaderDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(uploader:didAddTransferRecord:)])
    {
        [delegate uploader:self didAddTransferRecord:record];
    }
}

- (void)finishOperationsAndInvalidate;
{
    if (_invalidated) return;
    _invalidated = YES;
    
    // Now transfer records have all their content
    [self.rootTransferRecord markContentsAsComplete];
    
    if (!_queue.count)
    {
        // Slightly delay delivery so it's similar to if there were operations
        // in the queue
        [_fileManager.delegateQueue addOperationWithBlock:^{
            [self didBecomeInvalid];
        }];
    }
}

- (void)invalidateAndCancel;
{
    [self.operations makeObjectsPerformSelector:@selector(cancel)];
    [self finishOperationsAndInvalidate];
}

#pragma mark Queue

- (NSArray *)operations; { return [[_queue copy] autorelease]; }

- (CK2FileOperation *)currentOperation; { return [_queue firstObject]; }

- (void)addOperation:(CK2FileOperation *)operation;
{
    NSAssert([NSThread isMainThread], @"-addOperation: is only safe to call on the main thread");
    
    // No more operations can go on once finishing up
    if (_invalidated) [NSException raise:NSInvalidArgumentException format:@"%@ has been invalidated", self];
    
    // Watch for it to complete
    [operation addObserver:self forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:sOperationStateObservationContext];
    
    // Add to the queue
    [_queue addObject:operation];
    if (_queue.count == 1)
    {
        [self startNextOperationIfNotSuspended];
        [self retain];  // keep alive until queue is empty
    }
}

- (void)removeOperationAndStartNextIfAppropriate:(CK2FileOperation *)operation;
{
    NSParameterAssert(operation);
    NSAssert([NSThread isMainThread], @"-%@ is only safe to call on the main thread", NSStringFromSelector(_cmd));
    
    // We assume the operation is only in the queue the once, and most likely near the front
    NSUInteger index = [_queue indexOfObject:operation];
    if (index != NSNotFound) [_queue removeObjectAtIndex:index];
    
    // If was the current op, time to start the next
    if (index == 0) [self startNextOperationIfNotSuspended];
}

- (void)startNextOperationIfNotSuspended;
{
    if (self.suspended) return;
    
    while (_queue.count)
    {
        CK2FileOperation *operation = [_queue objectAtIndex:0];
        if (operation.state == CK2FileOperationStateSuspended)
        {
            [operation resume];
            return;
        }
        else
        {
            // Something other than us must have started the op
            [_queue removeObjectAtIndex:0];
        }
    }
    
    [self release]; // once the queue is empty, can be deallocated
    
    if (_invalidated) [self didBecomeInvalid];
}

- (void)operation:(CK2FileOperation *)operation didFinish:(NSError *)error;
{
    NSAssert([NSThread isMainThread], @"Operation broke threading contract");
    NSParameterAssert(operation);
    
        // Tell the record & delegate it's finished
        CKTransferRecord *record = [_recordsByOperation objectForKey:operation];
        [record transferDidFinish:record error:error];
        
        id <CKUploaderDelegate> delegate = self.delegate;
        
        if (record && [delegate respondsToSelector:@selector(uploader:transferRecord:didCompleteWithError:)])
        {
            [delegate uploader:self transferRecord:record didCompleteWithError:error];
        }
        
        [self removeOperationAndStartNextIfAppropriate:operation];
}

#pragma mark Transfer Records

- (CKTransferRecord *)makeTransferRecordWithURL:(NSURL *)url operation:(CK2FileOperation *)operation;
{
    NSString *path = [CK2FileManager pathOfURL:url];
    
    CKTransferRecord *result = [CKTransferRecord recordWithName:path.lastPathComponent
                                                uploadOperation:operation];
    
    CKTransferRecord *parent = [self directoryTransferRecordWithURL:[url URLByDeletingLastPathComponent]];
    [parent addContent:result];
    
    return result;
}

- (CKTransferRecord *)directoryTransferRecordWithURL:(NSURL *)url;
{
    NSParameterAssert(url);
    NSAssert([NSThread isMainThread], @"CKUploader can only be used on main thread");
    
    
    NSString *path = [CK2FileManager pathOfURL:url];
    if ([path isEqualToString:@"/"] || [path isEqualToString:@""]) // The root for absolute and relative paths
    {
        return [self rootTransferRecord];
    }
    
    
    // Recursively find a record we do have!
    NSURL *parentDirectoryURL = [url URLByDeletingLastPathComponent];
    CKTransferRecord *parent = [self directoryTransferRecordWithURL:parentDirectoryURL];
    
    
    // Create the record if it hasn't been already
    CKTransferRecord *result = nil;
    for (CKTransferRecord *aRecord in [parent contents])
    {
        if ([[aRecord name] isEqualToString:[path lastPathComponent]])
        {
            result = aRecord;
            break;
        }
    }
    
    if (!result)
    {
        result = [CKTransferRecord recordWithName:[path lastPathComponent] uploadOperation:nil];
        [parent addContent:result];
        [self didAddTransferRecord:result];
    }
    
    return result;
}

#pragma mark Suspending Operations

@synthesize suspended = _suspended;
- (void)setSuspended:(BOOL)suspended;
{
    if (suspended == _suspended) return;
    _suspended = suspended;
    
    if (!suspended)
    {
        CK2FileOperation *firstOp = _queue.firstObject;
        if (firstOp.state == CK2FileOperationStateSuspended)
        {
            [self startNextOperationIfNotSuspended];
        }
    }
}

#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == sOperationStateObservationContext)
    {
        CK2FileOperation *op = object;
        CK2FileOperationState state = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
        
        if (state == CK2FileOperationStateCompleted)
        {
            [op removeObserver:self forKeyPath:keyPath];
            [self operation:op didFinish:op.error];
        }
        else if (state == CK2FileOperationStateRunning)
        {
            NSAssert([NSThread isMainThread], @"Only want to notify delegate on the main thread");
            
            CKTransferRecord *record = [_recordsByOperation objectForKey:op];
            [record transferDidBegin:record];
            if (record) [self.delegate uploader:self didBeginUploadToPath:record.path];
        }
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark CK2FileManager Delegate

- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLRequest *))completionHandler;
{
    // Apply any customisations
    // Only allow SSL security to be *up*graded
    NSURLRequest *base = self.baseRequest;
    NSMutableURLRequest *customized = [request mutableCopy];
    
    [base.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *aField, NSString *aValue, BOOL *stop) {
        
        if (![customized valueForHTTPHeaderField:aField])
        {
            [customized setValue:aValue forHTTPHeaderField:aField];
        }
    }];
    
    curl_usessl level = base.curl_desiredSSLLevel;
    if (level > customized.curl_desiredSSLLevel) [customized curl_setDesiredSSLLevel:level];
    
    completionHandler(customized);
    [customized release];
}

- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(CK2AuthChallengeDisposition, NSURLCredential *))completionHandler;
{
    // Hand off to the delegate for auth
    id <CKUploaderDelegate> delegate = [self delegate];
    if (delegate)
    {
        [delegate uploader:self didReceiveChallenge:challenge completionHandler:completionHandler];
    }
    else
    {
        completionHandler(CK2AuthChallengePerformDefaultHandling, nil);
    }
}

- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation didWriteBodyData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesSent totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToSend;
{
        CKTransferRecord *record = [_recordsByOperation objectForKey:operation];
        NSAssert(record, @"Unknown operation");
        [record transfer:record transferredDataOfLength:bytesWritten];
        
        if ([self.delegate respondsToSelector:@selector(uploader:transferRecord:didWriteBodyData:totalBytesWritten:totalBytesExpectedToWrite:)])
        {
            [self.delegate uploader:self
                     transferRecord:record
                   didWriteBodyData:bytesWritten
                  totalBytesWritten:totalBytesSent
          totalBytesExpectedToWrite:totalBytesExpectedToSend];
        }
}

- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CK2TranscriptType)transcript;
{
    [[self delegate] uploader:self appendString:info toTranscript:transcript];
}

@end


//
//  CKUploader.m
//  Connection
//
//  Created by Mike Abdullah on 14/11/2011.
//  Copyright (c) 2011 Karelia Software. All rights reserved.
//

#import "CKUploader.h"

#import "CK2FileOperation.h"


@implementation CKUploader

#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request filePosixPermissions:(unsigned long)customPermissions options:(CKUploadingOptions)options;
{
    if (self = [self init])
    {
        _request = [request copy];
        _permissions = customPermissions;
        _options = options;
        
        if (!(_options & CKUploadingDryRun))
        {
            _fileManager = [[CK2FileManager alloc] init];
            _fileManager.delegate = self;
        }
        
        _queue = [[NSMutableArray alloc] init];
        _recordsByOperation = [[NSMutableDictionary alloc] init];
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
    
    return [[[self alloc] initWithRequest:request
                     filePosixPermissions:(customPermissions ? [customPermissions unsignedLongValue] : 0644)
                                  options:options] autorelease];
}

- (void)dealloc
{
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

@synthesize options = _options;
@synthesize rootTransferRecord = _rootRecord;
@synthesize baseTransferRecord = _baseRecord;

- (NSURLRequest *)request; { return _request; }

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

- (void)removeFileAtPath:(NSString *)path;
{
    [self removeFileAtPath:path reportError:YES];
}

- (void)removeFileAtPath:(NSString *)path reportError:(BOOL)reportError;
{
    [self addOperationWithBlock:^{
                
        return [_fileManager removeItemAtURL:[self URLForPath:path] completionHandler:^(NSError *error) {
            
            [self operation:nil didFinish:(reportError ? error : nil)];
        }];
    }];
}

- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path;
{
    NSDictionary *attributes = @{ NSFilePosixPermissions : @([self posixPermissionsForPath:path isDirectory:NO]) };
    
    CK2FileOperation *op = [_fileManager createFileOperationWithURL:[self URLForPath:path]
                                                           fromData:data
                                        withIntermediateDirectories:YES
                                                  openingAttributes:attributes
                                                  completionHandler:NULL];
    
    return [self uploadToPath:path usingOperation:op];
}

- (CKTransferRecord *)uploadFileAtURL:(NSURL *)localURL toPath:(NSString *)path;
{
    NSNumber *size;
    if (![localURL getResourceValue:&size forKey:NSURLFileSizeKey error:NULL]) size = nil;
    
    NSDictionary *attributes = @{ NSFilePosixPermissions : @([self posixPermissionsForPath:path isDirectory:NO]) };
    
    CK2FileOperation *op = [_fileManager createFileOperationWithURL:[self URLForPath:path]
                                                           fromFile:localURL
                                        withIntermediateDirectories:YES
                                                  openingAttributes:attributes
                                                  completionHandler:NULL];
    
    return [self uploadToPath:path usingOperation:op];
}

- (CKTransferRecord *)uploadToPath:(NSString *)path usingOperation:(CK2FileOperation *)operation;
{
    NSParameterAssert(operation);
    
    // Create transfer record
    if (_options & CKUploadingDeleteExistingFileFirst)
	{
        // The file might not exist, so will fail in that case. We don't really care since should a deletion fail for a good reason, that ought to then cause the actual upload to fail
        [self removeFileAtPath:path reportError:NO];
	}
    
    CKTransferRecord *result = [self makeTransferRecordWithPath:path operation:operation];
    [_recordsByOperation setObject:result forKey:operation];
    
    
    // Enqueue upload
    [self addOperationWithBlock:^{
        
        if (!self.isCancelled)
        {
            [operation resume];
            [result transferDidBegin:result];
            [self.delegate uploader:self didBeginUploadToPath:path];
        }
        
        return operation;
    }];
    
    
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

- (NSURL *)URLForPath:(NSString *)path;
{
    return [CK2FileManager URLWithPath:path relativeToURL:[self request].URL];
}

- (void)finishUploading;
{
    [self addOperationWithBlock:^CK2FileOperation* {
        
        NSAssert(!self.isCancelled, @"Shouldn't be able to finish once cancelled!");
        [[self delegate] uploaderDidFinishUploading:self];
        [self operation:nil didFinish:nil];
        return nil;
    }];
    
    _isFinishing = YES;
}

#pragma mark Queue

- (void)cancel;
{
    _isCancelled = YES;
    [self.currentOperation cancel];
    [_queue makeObjectsPerformSelector:_cmd];
    [_queue release]; _queue = nil;
}

- (BOOL)isCancelled; { return _isCancelled; }

- (CK2FileOperation *)currentOperation; { return _currentOperation; }

- (void)addOperationWithBlock:(CK2FileOperation* (^)(void))block;
{
    NSAssert([NSThread isMainThread], @"-addOperation: is only safe to call on the main thread");
    
    // No more operations can go on once finishing up
    if (_isFinishing) return;
    
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        
        NSAssert(_currentOperation == nil, @"Seems like an op is starting before another has finished");
        _currentOperation = [block() retain];
    }];
    
    [_queue addObject:operation];
    if ([_queue count] == 1)
    {
        [operation start];
    }
}

- (void)operation:(CK2FileOperation *)operation didFinish:(NSError *)error;
{
    // This method gets called on all sorts of threads, so marshall back to main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        
        // Tell the record it's finished
        if (operation)
        {
            CKTransferRecord *record = [_recordsByOperation objectForKey:operation];
            [record transferDidFinish:record error:error];
        }
        
        
        [_currentOperation release]; _currentOperation = nil;
        
        if (error)
        {
            if ([self.delegate respondsToSelector:@selector(uploader:shouldProceedAfterError:)])
            {
                if (![self.delegate uploader:self shouldProceedAfterError:error])
                {
                    [self.delegate uploader:self didFailWithError:error];
                    [self cancel];
                }
            }
            else
            {
                [self.delegate uploader:self didFailWithError:error];
                [self cancel];
            }
        }
        
        [_queue removeObjectAtIndex:0];
        if ([_queue count])
        {
            [[_queue objectAtIndex:0] start];
        }
    });
}

#pragma mark Transfer Records

- (CKTransferRecord *)makeTransferRecordWithPath:(NSString *)path operation:(CK2FileOperation *)operation;
{
    CKTransferRecord *result = [CKTransferRecord recordWithName:[path lastPathComponent] uploadOperation:operation];
    
    CKTransferRecord *parent = [self directoryTransferRecordWithPath:[path stringByDeletingLastPathComponent]];
    [parent addContent:result];
    
    return result;
}

- (CKTransferRecord *)directoryTransferRecordWithPath:(NSString *)path;
{
    NSParameterAssert(path);
    NSAssert([NSThread isMainThread], @"CKUploader can only be used on main thread");
    
    
    if ([path isEqualToString:@"/"] || [path isEqualToString:@""]) // The root for absolute and relative paths
    {
        return [self rootTransferRecord];
    }
    
    
    // Recursively find a record we do have!
    NSString *parentDirectoryPath = [path stringByDeletingLastPathComponent];
    CKTransferRecord *parent = [self directoryTransferRecordWithPath:parentDirectoryPath];
    
    
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

#pragma mark CK2FileManager Delegate

- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(CK2AuthChallengeDisposition, NSURLCredential *))completionHandler;
{
    // Hand off to the delegate for auth, on the main queue as it expects
    dispatch_async(dispatch_get_main_queue(), ^{
        
        id <CKUploaderDelegate> delegate = [self delegate];
        if (delegate)
        {
            [delegate uploader:self didReceiveChallenge:challenge completionHandler:completionHandler];
        }
        else
        {
            completionHandler(CK2AuthChallengePerformDefaultHandling, nil);
        }
    });
}

- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation didWriteBodyData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesSent totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToSend;
{
    dispatch_async(dispatch_get_main_queue(), ^{
        CKTransferRecord *record = [_recordsByOperation objectForKey:operation];
        NSAssert(record, @"Unknown operation");
        [record transfer:record transferredDataOfLength:bytesWritten];
    });
}

- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CK2TranscriptType)transcript;
{
	dispatch_async(dispatch_get_main_queue(), ^{
        [[self delegate] uploader:self appendString:info toTranscript:transcript];
    });
}

- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation didCompleteWithError:(NSError *)error;
{
    [self operation:operation didFinish:error];
}

@end


//
//  CKUploader.m
//  Connection
//
//  Created by Mike Abdullah on 14/11/2011.
//  Copyright (c) 2011 Karelia Software. All rights reserved.
//

#import "CKUploader.h"


@interface CKUploaderOperation : NSOperation
{
    id  (^_block)(void);
    id  _fileOp;
}

- initWithBlock:(id (^)(void))block __attribute((nonnull));

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
        _maxConcurrentOperationCount = 1;
        _options = options;
        
        if (!(_options & CKUploadingDryRun))
        {
            _fileManager = [[CK2FileManager alloc] init];
            _fileManager.delegate = self;
        }
        
        _queue = [[NSMutableArray alloc] init];
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
    
    [super dealloc];
}

#pragma mark Properties

@synthesize delegate = _delegate;

@synthesize options = _options;

@synthesize maxConcurrentOperationCount = _maxConcurrentOperationCount;
- (NSUInteger)effectiveConcurrentOperationCount;
{
    NSUInteger result = self.maxConcurrentOperationCount;
    
    // Reign in count when:
    // * Using CURLHandle sync backend
    // * Deleting files before uploading; have no dependency system to handle that
    if (result > 1)
    {
        if (self.options & CKUploadingDeleteExistingFileFirst)
        {
            result = 1;
        }
        else
        {
            NSString *scheme = _request.URL.scheme;
            if ([scheme caseInsensitiveCompare:@"ftp"] == NSOrderedSame || [scheme caseInsensitiveCompare:@"sftp"] == NSOrderedSame)
            {
                result = 1;
            }
        }
    }
    
    return result;
}

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
    __block CKUploaderOperation *op = [[CKUploaderOperation alloc] initWithBlock:^id{
        
        return [_fileManager removeItemAtURL:[self URLForPath:path] completionHandler:^(NSError *error) {
            
            [self operation:op didFinish:(reportError ? error : nil)];
        }];
    }];
    
    [self addOperation:op];
    [op release];
}

- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path;
{
    __block CKTransferRecord *record = [self transferRecordWithPath:path size:data.length usingBlock:^id {
        
        NSDictionary *attributes = @{ NSFilePosixPermissions : @([self posixPermissionsForPath:path isDirectory:NO]) };
        
        id op = [_fileManager createFileAtURL:[self URLForPath:path] contents:data withIntermediateDirectories:YES openingAttributes:attributes progressBlock:^(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToSend) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [record transfer:record transferredDataOfLength:bytesWritten];
            });
            
        } completionHandler:^(NSError *error) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [record transferDidFinish:record error:error];
            });
            
            [self operation:[record propertyForKey:@"uploadOperation"] didFinish:error];
        }];
        
        NSAssert(op, @"Failed to create upload operation");
        
        if (!self.isCancelled)
        {
            [record transferDidBegin:record];
            [self.delegate uploader:self didBeginUploadToPath:path];
        }
        
        return op;
    }];
    
    [self addOperation:[record propertyForKey:@"uploadOperation"]];
    return record;
}

- (CKTransferRecord *)uploadFileAtURL:(NSURL *)localURL toPath:(NSString *)path;
{
    NSNumber *size;
    if (![localURL getResourceValue:&size forKey:NSURLFileSizeKey error:NULL]) size = nil;
    
    __block CKTransferRecord *record = [self transferRecordWithPath:path size:size.unsignedLongLongValue usingBlock:^id {
        
        NSDictionary *attributes = @{ NSFilePosixPermissions : @([self posixPermissionsForPath:path isDirectory:NO]) };
        
        id op = [_fileManager createFileAtURL:[self URLForPath:path] withContentsOfURL:localURL withIntermediateDirectories:YES openingAttributes:attributes progressBlock:^(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToSend) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [record transfer:record transferredDataOfLength:bytesWritten];
            });
            
        }  completionHandler:^(NSError *error) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [record transferDidFinish:record error:error];
            });
            
            [self operation:[record propertyForKey:@"uploadOperation"] didFinish:error];
        }];
        
        NSAssert(op, @"Failed to create upload operation");
        
        if (!self.isCancelled)
        {
            [record transferDidBegin:record];
            [self.delegate uploader:self didBeginUploadToPath:path];
        }
        
        return op;
    }];
    
    [self addOperation:[record propertyForKey:@"uploadOperation"]];
    return record;
}

- (CKTransferRecord *)transferRecordWithPath:(NSString *)path size:(unsigned long long)size usingBlock:(id (^)(void))block;
{
    // Create transfer record
    if (_options & CKUploadingDeleteExistingFileFirst)
	{
        // The file might not exist, so will fail in that case. We don't really care since should a deletion fail for a good reason, that ought to then cause the actual upload to fail
        [self removeFileAtPath:path reportError:NO];
	}
    
    CKTransferRecord *result = [self makeTransferRecordWithPath:path size:size];
    
    
    // Enqueue upload
    CKUploaderOperation *op = [[CKUploaderOperation alloc] initWithBlock:block];
    [result setProperty:op forKey:@"uploadOperation"];
    [op release];
    
    
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
    if (_isFinishing || _isCancelled) return;
    
    _isFinishing = YES;
    if (_queue.count == 0)
    {
        NSAssert(!self.isCancelled, @"Shouldn't be able to finish once cancelled!");
        [[self delegate] uploaderDidFinishUploading:self];
    }
}

#pragma mark Queue

- (void)cancel;
{
    _isCancelled = YES;
    [_queue makeObjectsPerformSelector:_cmd];
    [_queue release]; _queue = nil;
}

- (BOOL)isCancelled; { return _isCancelled; }

// The block must return the operation vended to it by CK2FileManager
- (void)addOperationWithBlock:(id (^)(void))block;
{
    CKUploaderOperation *operation = [[CKUploaderOperation alloc] initWithBlock:block];
    [self addOperation:operation];
    [operation release];
}

- (void)addOperation:(CKUploaderOperation *)operation;
{
    NSAssert([NSThread isMainThread], @"-addOperation: is only safe to call on the main thread");
    
    // No more operations can go on once finishing up
    if (_isFinishing) return;
    
    [_queue addObject:operation];
    
    if ([_queue count] <= self.effectiveConcurrentOperationCount)
    {
        [operation start];
    }
}

- (void)operation:(CKUploaderOperation *)operation didFinish:(NSError *)error;
{
    // This method gets called on all sorts of threads, so marshall back to main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        
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
        
        NSUInteger index = [_queue indexOfObject:operation];
        NSAssert(index != NSNotFound, @"Finished operation should be in the queue");
        [_queue removeObjectAtIndex:index];
        
        // Dequeue next op
        // TODO: Check for ops which should have been started but haven't?
        NSUInteger maxOps = self.effectiveConcurrentOperationCount;
        if (_queue.count >= maxOps)
        {
            [[_queue objectAtIndex:(maxOps - 1)] start];
        }
        else if (_isFinishing && _queue.count == 0)
        {
            NSAssert(!self.isCancelled, @"Shouldn't be able to finish once cancelled!");
            [[self delegate] uploaderDidFinishUploading:self];
        }
    });
}

#pragma mark Transfer Records

- (CKTransferRecord *)makeTransferRecordWithPath:(NSString *)path size:(unsigned long long)size
{
    CKTransferRecord *result = [CKTransferRecord recordWithName:[path lastPathComponent] size:size];
    
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
        result = [CKTransferRecord recordWithName:[path lastPathComponent] size:0];
        [parent addContent:result];
        [self didAddTransferRecord:result];
    }
    
    return result;
}

#pragma mark CK2FileManager Delegate

- (void)fileManager:(CK2FileManager *)manager operation:(id)operation didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(CK2AuthChallengeDisposition, NSURLCredential *))completionHandler;
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

- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CK2TranscriptType)transcript;
{
	dispatch_async(dispatch_get_main_queue(), ^{
        [[self delegate] uploader:self appendString:info toTranscript:transcript];
    });
}

@end


#pragma mark -


@implementation CKUploaderOperation

- initWithBlock:(id (^)(void))block;
{
    NSParameterAssert(block);
    if (self = [self init])
    {
        _block = [block copy];
    }
    return self;
}

- (void)main;
{
    if (self.isCancelled) return;
    _fileOp = [_block() retain];
}

- (void)cancel;
{
    [super cancel];
    [_fileOp cancel];
}

- (void)dealloc;
{
    [_block release];
    [_fileOp release];
    
    [super dealloc];
}

@end

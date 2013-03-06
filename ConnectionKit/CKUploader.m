//
//  CKUploader.m
//  Connection
//
//  Created by Mike Abdullah on 14/11/2011.
//  Copyright (c) 2011 Karelia Software. All rights reserved.
//

#import "CKUploader.h"


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

- (CKTransferRecord *)willUploadToPath:(NSString *)path size:(unsigned long long)size;
{
    if (_options & CKUploadingDeleteExistingFileFirst)
	{
        // The file might not exist, so will fail in that case. We don't really care since should a deletion fail for a good reason, that ought to then cause the actual upload to fail
        [self removeFileAtPath:path reportError:NO];
	}
    
    return [self makeTransferRecordWithPath:path size:size];
}

- (void)removeFileAtPath:(NSString *)path;
{
    [self removeFileAtPath:path reportError:YES];
}

- (void)removeFileAtPath:(NSString *)path reportError:(BOOL)reportError;
{
    [self addOperationWithBlock:^{
        
        NSURL *url = [CK2FileManager URLWithPath:path relativeToURL:[self request].URL];
        
        return [_fileManager removeItemAtURL:url completionHandler:^(NSError *error) {
            
            [self operationDidFinish:(reportError ? error : nil)];
        }];
    }];
}

- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path;
{
    CKTransferRecord *result = [self willUploadToPath:path size:data.length];
    
    [self addOperationWithBlock:^{
        
        NSURL *url = [CK2FileManager URLWithPath:path relativeToURL:[self request].URL];
        NSDictionary *attributes = @{ NSFilePosixPermissions : @([self posixPermissionsForPath:path isDirectory:NO]) };
        
        id op = [_fileManager createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:attributes progressBlock:^(NSUInteger bytesWritten, NSUInteger previousAttemptCount) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [result transfer:result transferredDataOfLength:bytesWritten];
            });
            
        } completionHandler:^(NSError *error) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [result transferDidFinish:result error:error];
            });
            
            [self operationDidFinish:error];
        }];
        
        NSAssert(op, @"Failed to create upload operation");
        
        if (!self.isCancelled)
        {
            [result transferDidBegin:result];
            [self.delegate uploader:self didBeginUploadToPath:path];
        }
        
        return op;
    }];
    
    return result;
}

- (CKTransferRecord *)uploadFileAtURL:(NSURL *)localURL toPath:(NSString *)path;
{
    NSNumber *size;
    if (![localURL getResourceValue:&size forKey:NSURLFileSizeKey error:NULL]) size = nil;
    
    CKTransferRecord *result = [self willUploadToPath:path size:size.unsignedLongLongValue];
    
    [self addOperationWithBlock:^{
        
        NSURL *remoteURL = [CK2FileManager URLWithPath:path relativeToURL:[self request].URL];
        NSDictionary *attributes = @{ NSFilePosixPermissions : @([self posixPermissionsForPath:path isDirectory:NO]) };
        
        id op = [_fileManager createFileAtURL:remoteURL withContentsOfURL:localURL withIntermediateDirectories:YES openingAttributes:attributes progressBlock:^(NSUInteger bytesWritten, NSUInteger previousAttemptCount) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [result transfer:result transferredDataOfLength:bytesWritten];
            });
            
        }  completionHandler:^(NSError *error) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [result transferDidFinish:result error:error];
            });
            
            [self operationDidFinish:error];
        }];
        
        NSAssert(op, @"Failed to create upload operation");
        
        if (!self.isCancelled)
        {
            [result transferDidBegin:result];
            [self.delegate uploader:self didBeginUploadToPath:path];
        }
        
        return op;
    }];
    
    return result;
}

- (void)finishUploading;
{
    [self addOperationWithBlock:^id{
        
        NSAssert(!self.isCancelled, @"Shouldn't be able to finish once cancelled!");
        [[self delegate] uploaderDidFinishUploading:self];
        [self operationDidFinish:nil];
        return nil;
    }];
    
    _isFinishing = YES;
}

#pragma mark Queue

- (void)cancel;
{
    _isCancelled = YES;
    [_fileManager cancelOperation:self.currentOperation];
    [_queue makeObjectsPerformSelector:_cmd];
    [_queue release]; _queue = nil;
}

- (BOOL)isCancelled; { return _isCancelled; }

- (id)currentOperation; { return _currentOperation; }

// The block must return the operation vended to it by CK2FileManager
- (void)addOperationWithBlock:(id (^)(void))block;
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

- (void)operationDidFinish:(NSError *)error;
{
    // This method gets called on all sorts of threads, so marshall back to main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        
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
    }
    
    return result;
}

#pragma mark CK2FileManager Delegate

- (void)fileManager:(CK2FileManager *)manager didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    // Hand off to the delegate for auth, on the main queue as it expects
    dispatch_async(dispatch_get_main_queue(), ^{
        
        id <CKUploaderDelegate> delegate = [self delegate];
        if (delegate)
        {
            [delegate uploader:self didReceiveAuthenticationChallenge:challenge];
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
    });
}

- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript;
{
	dispatch_async(dispatch_get_main_queue(), ^{
        [[self delegate] uploader:self appendString:info toTranscript:transcript];
    });
}

@end


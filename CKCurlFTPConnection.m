//
//  CKSFTPConnection.m
//  Sandvox
//
//  Created by Mike on 25/10/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import "CKCurlFTPConnection.h"

#import "UKMainThreadProxy.h"

#import <sys/dirent.h>


@interface CKCurlFTPConnection () <CURLHandleDelegate, NSURLAuthenticationChallengeSender>
@end


#pragma mark -


@implementation CKCurlFTPConnection

+ (void)load
{
    [[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forName:@"FTP" URLScheme:@"ftp"];
}

+ (NSArray *)URLSchemes { return [NSArray arrayWithObjects:@"ftp", @"ftp", nil]; }

#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request;
{
    if (self = [self init])
    {
        _session = [[CURLFTPSession alloc] initWithRequest:request];
        if (!_session)
        {
            [self release]; return nil;
        }
        [_session setDelegate:self];
        
        _request = [request copy];
        
        _queue = [[NSOperationQueue alloc] init];
        [_queue setMaxConcurrentOperationCount:1];
    }
    return self;
}

- (void)dealloc;
{
    [_request release];
    [_credential release];
    [_session release];
    [_queue release];
    [_currentDirectory release];
    
    [super dealloc];
}

#pragma mark Delegate

@synthesize delegate = _delegate;

#pragma mark Queue

- (void)enqueueOperation:(NSOperation *)operation;
{
    // Assume that only _session targeted invocations are async
    [_queue addOperation:operation];
}

#pragma mark Connection

- (void)connect;
{
    NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:[[_request URL] host]
                                                                        port:[[[_request URL] port] integerValue]
                                                                    protocol:[[_request URL] scheme]
                                                                       realm:nil
                                                        authenticationMethod:nil];
    
    _challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space proposedCredential:nil previousFailureCount:0 failureResponse:nil error:nil sender:self];
    [space release];
    
    [[self delegate] connection:self didReceiveAuthenticationChallenge:_challenge];
}

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if (challenge != _challenge) return;
    
    [_session useCredential:credential];
    
    if ([[self delegate] respondsToSelector:@selector(connection:didConnectToHost:error:)])
    {
        [[self delegate] connection:self didConnectToHost:[[_request URL] host] error:nil];
    }
}

- (void)disconnect;
{
    NSInvocationOperation *op = [[NSInvocationOperation alloc] initWithTarget:self
                                                                     selector:@selector(forceDisconnect)
                                                                       object:nil];
    [self enqueueOperation:op];
    [op release];
}

- (void)forceDisconnect
{
    // Cancel all in queue
    [_queue cancelAllOperations];
    
    NSOperation *op = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(threaded_disconnect) object:nil];
    [self enqueueOperation:op];
    [op release];
}

- (void)threaded_disconnect;
{
    if ([[self delegate] respondsToSelector:@selector(connection:didDisconnectFromHost:)])
    {
        id proxy = [[UKMainThreadProxy alloc] initWithTarget:[self delegate]];
        [proxy connection:self didDisconnectFromHost:[[_request URL] host]];
        [proxy release];
    }
}

- (void)SFTPSession:(CK2SFTPSession *)session didFailWithError:(NSError *)error;
{
    id proxy = [[UKMainThreadProxy alloc] initWithTarget:[self delegate]];
    [proxy connection:self didReceiveError:error];
    [proxy release];
}

- (void)SFTPSession:(CK2SFTPSession *)session didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [[self delegate] connection:self didReceiveAuthenticationChallenge:challenge];
}

- (void)SFTPSession:(CK2SFTPSession *)session didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [[self delegate] connection:self didCancelAuthenticationChallenge:challenge];
}

- (void)FTPSession:(CURLFTPSession *)session didReceiveDebugInfo:(NSString *)string ofType:(curl_infotype)type;
{
    if (![self delegate]) return;
    
    id proxy = [[UKMainThreadProxy alloc] initWithTarget:[self delegate]];
    [proxy connection:self appendString:string toTranscript:(type == CURLINFO_HEADER_IN ? CKTranscriptReceived : CKTranscriptSent)];
    [proxy release];
}

#pragma mark Requests

- (void)cancelAll { }

- (NSString *)canonicalPathForPath:(NSString *)path;
{
    // Heavily based on +ks_stringWithPath:relativeToDirectory: in KSFileUtilities
    
    if ([path isAbsolutePath]) return path;
    
    NSString *directory = [self currentDirectory];
    if (!directory) return path;
    
    NSString *result = [directory stringByAppendingPathComponent:path];
    return result;
}

- (CKTransferRecord *)uploadFileAtURL:(NSURL *)url toPath:(NSString *)path posixPermissions:(NSNumber *)permissions;
{
    return [self uploadData:[NSData dataWithContentsOfURL:url] toPath:path posixPermissions:permissions];
}

- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path posixPermissions:(NSNumber *)permissions;
{
    NSParameterAssert(data);
    
    CKTransferRecord *result = [CKTransferRecord recordWithName:[path lastPathComponent] size:[data length]];
    //CFDictionarySetValue((CFMutableDictionaryRef)_transferRecordsByRequest, request, result);
    
    path = [self canonicalPathForPath:path];
    
    
    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(threaded_writeData:toPath:transferRecord:permissions:)
                                                             target:self
                                                          arguments:[NSArray arrayWithObjects:data, path, result, permissions, nil]];
    
    NSInvocationOperation *op = [[NSInvocationOperation alloc] initWithInvocation:invocation];
    [self enqueueOperation:op];
    [op release];
    
    
    return result;
}

- (void)threaded_writeData:(NSData *)data toPath:(NSString *)path transferRecord:(CKTransferRecord *)record permissions:(NSNumber *)permissions;
{
    NSError *error;
    BOOL result = [_session createFileAtPath:path contents:data permissions:permissions error:&error];
        
    if ([[self delegate] respondsToSelector:@selector(connection:uploadDidFinish:error:)])
    {
        id proxy = [[UKMainThreadProxy alloc] initWithTarget:[self delegate]];
        [proxy connection:self uploadDidFinish:path error:(result ? nil : error)];
        [proxy release];
    }
}

- (void)createDirectoryAtPath:(NSString *)path posixPermissions:(NSNumber *)permissions;
{
    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(threaded_createDirectoryAtPath:permissions:)
                                                             target:self
                                                          arguments:[NSArray arrayWithObjects:path, permissions, nil]];
    
    NSInvocationOperation *op = [[NSInvocationOperation alloc] initWithInvocation:invocation];
    [self enqueueOperation:op];
    [op release];
}

- (void)threaded_createDirectoryAtPath:(NSString *)path permissions:(NSNumber *)permissions;
{
    NSError *error;
    BOOL result = [_session createDirectoryAtPath:path error:&error];
    if (result)
    {
        error = nil;
    }
}

- (void)deleteFile:(NSString *)path
{
    path = [self canonicalPathForPath:path];
    
    NSOperation *op = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(threaded_removeFileAtPath:) object:path];
    [self enqueueOperation:op];
    [op release];
}

- (void)threaded_removeFileAtPath:(NSString *)path;
{
    NSError *error;
    BOOL result = [_session removeFileAtPath:path error:&error];
    if (result) error = nil;
    
    id proxy = [[UKMainThreadProxy alloc] initWithTarget:[self delegate]];
    [proxy connection:self didDeleteFile:path error:error];
    [proxy release];
}

- (void)directoryContents
{ 
    NSOperation *op = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(threaded_directoryContents:) object:[self currentDirectory]];
    [self enqueueOperation:op];
    [op release];
}
- (void)threaded_directoryContents:(NSString *)path;
{
    NSError *error;
    NSMutableArray *result = [[_session parsedResourceListingsOfDirectory:path error:&error] mutableCopy];
    
    // Convert from CFFTP's format to ours
    for (NSUInteger i = 0; i < [result count]; i++)
    {
        NSDictionary *aListing = [result objectAtIndex:i];
        
        NSString *type = NSFileTypeUnknown;
        switch ([[aListing objectForKey:(NSString *)kCFFTPResourceType] integerValue])
        {
            case DT_CHR:
                type = NSFileTypeCharacterSpecial;
                break;
            case DT_DIR:
                type = NSFileTypeDirectory;
                break;
            case DT_BLK:
                type = NSFileTypeBlockSpecial;
                break;
            case DT_REG:
                type = NSFileTypeRegular;
                break;
            case DT_LNK:
                type = NSFileTypeSymbolicLink;
                break;
            case DT_SOCK:
                type = NSFileTypeSocket;
                break;
        }
        
        NSDictionary *attributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                                    [aListing objectForKey:(NSString *)kCFFTPResourceName], cxFilenameKey,
                                    type, NSFileType,
                                    nil];
        [result replaceObjectAtIndex:i withObject:attributes];
        [attributes release];
    }
    
    if (result) error = nil;    // cause CK handles errors in a crazy way
    
    id proxy = [[UKMainThreadProxy alloc] initWithTarget:[self delegate]];
    [proxy connection:self didReceiveContents:result ofDirectory:path error:error];
    [proxy release];
    [result release];
}

#pragma mark Current Directory

@synthesize currentDirectory = _currentDirectory;

- (void)changeToDirectory:(NSString *)dirPath
{
    [self setCurrentDirectory:dirPath];
    
    NSOperation *op = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(threaded_changedToDirectory:) object:dirPath];
    [self enqueueOperation:op];
    [op release];
}

- (void)threaded_changedToDirectory:(NSString *)dirPath;
{
    if ([[self delegate] respondsToSelector:@selector(connection:didChangeToDirectory:error:)])
    {
        id proxy = [[UKMainThreadProxy alloc] initWithTarget:[self delegate]];
        [proxy connection:self didChangeToDirectory:dirPath error:nil];
        [proxy release];
    }
}

- commandQueue { return nil; }
- (void)cleanupConnection { }

#pragma mark Delegate

- (void)handle:(CURLHandle *)handle didReceiveResponse:(NSURLResponse *)response;
{
    
}

- (void)handle:(CURLHandle *)handle didReceiveData:(NSData *)data;
{
    
}

@end

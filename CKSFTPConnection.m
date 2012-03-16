//
//  CKSFTPConnection.m
//  Sandvox
//
//  Created by Mike on 25/10/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import "CKSFTPConnection.h"
#import "CK2SFTPSession.h"

#import "UKMainThreadProxy.h"


@interface CKSFTPConnection () <CK2SFTPSessionDelegate>
@end


#pragma mark -


@implementation CKSFTPConnection

+ (void)load
{
    [[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forName:@"SFTP" URLScheme:@"sftp"];
}

+ (NSArray *)URLSchemes { return [NSArray arrayWithObjects:@"sftp", @"ssh", nil]; }

#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request;
{
    if (self = [self init])
    {
        _session = [[CK2SFTPSession alloc] initWithURL:[request URL] delegate:self startImmediately:NO];
        _url = [[request URL] copy];
        
        _queue = [[NSOperationQueue alloc] init];
        [_queue setMaxConcurrentOperationCount:1];
    }
    return self;
}

- (void)dealloc;
{
    [_url release];
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

- (CK2SFTPSession *)SFTPSession; { return _session; }

- (void)connect;
{
    NSOperation *op = [[NSInvocationOperation alloc] initWithTarget:[self SFTPSession] selector:@selector(start) object:nil];
    [self enqueueOperation:op];
    [op release];
}

- (void)SFTPSessionDidInitialize:(CK2SFTPSession *)session;
{
    // Store current directory ready for when somebody (*cough* open panel) asks for it
    [self setCurrentDirectory:[session currentDirectoryPath:NULL]];
    
    if ([[self delegate] respondsToSelector:@selector(connection:didConnectToHost:error:)])
    {
        [[self delegate] connection:self didConnectToHost:[_url host] error:nil];
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
        [proxy connection:self didDisconnectFromHost:[_url host]];
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

- (void)SFTPSession:(CK2SFTPSession *)session appendStringToTranscript:(NSString *)string received:(BOOL)received;
{
    if (![self delegate]) return;
    
    id proxy = [[UKMainThreadProxy alloc] initWithTarget:[self delegate]];
    [proxy connection:self appendString:string toTranscript:(received ? CKTranscriptReceived : CKTranscriptSent)];
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
    CK2SFTPSession *sftpSession = [self SFTPSession];
    NSAssert(sftpSession, @"Trying to write data without having started session");
    
    unsigned long mode = (permissions ? [permissions unsignedLongValue] : 0644);
    
    NSError *error;
    CK2SFTPFileHandle *handle = [sftpSession openHandleAtPath:path flags:(LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT) mode:mode error:&error];
    
    if (handle)
    {
        BOOL result = [handle writeData:data error:&error];
        [handle closeFile];         // don't really care if this fails
        if (!result) handle = nil;  // so error gets sent
    }
    
    if (handle) error = nil;    // don't confuse CK!
    
    
    id proxy = [[UKMainThreadProxy alloc] initWithTarget:[self delegate]];
    [proxy connection:self uploadDidFinish:path error:error];
    [proxy release];
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
    CK2SFTPSession *sftpSession = [self SFTPSession];
    NSAssert(sftpSession, @"Trying to write data without having started session");
    
    unsigned long mode = (permissions ? [permissions unsignedLongValue] : (0644 | 0111));
    
    NSError *error;
    [sftpSession createDirectoryAtPath:path mode:mode error:&error];
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
    BOOL result = [[self SFTPSession] removeFileAtPath:path error:&error];
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
    if (!path) path = @".";
    
    NSError *error;
    NSArray *result = [[self SFTPSession] attributesOfContentsOfDirectoryAtPath:path error:&error];
    if (result) error = nil;    // cause CK handles errors in a crazy way
    
    id proxy = [[UKMainThreadProxy alloc] initWithTarget:[self delegate]];
    [proxy connection:self didReceiveContents:result ofDirectory:path error:error];
    [proxy release];
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

@end

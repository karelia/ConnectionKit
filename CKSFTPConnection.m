//
//  CKSFTPConnection.m
//  Sandvox
//
//  Created by Mike on 25/10/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import "CKSFTPConnection.h"

#import "UKMainThreadProxy.h"

#import "KSPathUtilities.h"


@implementation CKSFTPConnection

+ (void)load
{
    [[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forName:@"SFTP" URLScheme:@"ssh"];
}

+ (NSArray *)URLSchemes { return [NSArray arrayWithObjects:@"ssh", @"sftp", nil]; }

#pragma mark Lifecycle

- (id)initWithRequest:(CKConnectionRequest *)request;
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
    [_url copy];
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

- (void)SFTPSession:(CK2SFTPSession *)session didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [[self delegate] connection:self didReceiveAuthenticationChallenge:challenge];
}

- (void)SFTPSession:(CK2SFTPSession *)session appendStringToTranscript:(NSString *)string;
{
    id proxy = [[UKMainThreadProxy alloc] initWithTarget:[self delegate]];
    [proxy connection:self appendString:string toTranscript:CKTranscriptReceived];
    [proxy release];
}

#pragma mark Requests

- (void)cancelAll { }

- (CKTransferRecord *)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag delegate:(id)delegate
{
    return [self uploadFromData:[NSData dataWithContentsOfFile:localPath]
                         toFile:remotePath
           checkRemoteExistence:flag
                       delegate:delegate];
}

- (CKTransferRecord *)uploadFromData:(NSData *)data toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag delegate:(id)delegate;
{
    OBPRECONDITION(data);
    
    CKTransferRecord *result = [CKTransferRecord recordWithName:[remotePath lastPathComponent] size:[data length]];
    //CFDictionarySetValue((CFMutableDictionaryRef)_transferRecordsByRequest, request, result);
    
    remotePath = [NSString ks_stringWithPath:remotePath relativeToDirectory:[self currentDirectory]];
    
    
    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(threaded_writeData:toPath:transferRecord:)
                                                             target:self
                                                          arguments:[NSArray arrayWithObjects:data, remotePath, result, nil]];
    
    NSInvocationOperation *op = [[NSInvocationOperation alloc] initWithInvocation:invocation];
    [self enqueueOperation:op];
    [op release];
    
    
    return result;
}

- (void)threaded_writeData:(NSData *)data toPath:(NSString *)path transferRecord:(CKTransferRecord *)record;
{
    CK2SFTPSession *sftpSession = [self SFTPSession];
    OBPRECONDITION(sftpSession);
    
    NSError *error;
    CK2SFTPFileHandle *handle = [sftpSession openHandleAtPath:path flags:(LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT) mode:0644 error:&error];
    
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

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions;
{
    return [self createDirectory:dirPath];
}

- (void)createDirectory:(NSString *)dirPath;
{
    NSInvocationOperation *op = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(threaded_createDirectoryAtPath:) object:dirPath];
    
    [self enqueueOperation:op];
    [op release];
}

- (void)threaded_createDirectoryAtPath:(NSString *)path;
{
    CK2SFTPSession *sftpSession = [self SFTPSession];
    OBPRECONDITION(sftpSession);
    
    NSError *error;
    [sftpSession createDirectoryAtPath:path mode:(0644 | 0111) error:&error];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path; { /* ignore! */ }

- (void)deleteFile:(NSString *)path
{
    path = [NSString ks_stringWithPath:path relativeToDirectory:[self currentDirectory]];
    
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

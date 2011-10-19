//
//  CK2WebDAVConnection.m
//  Sandvox
//
//  Created by Mike on 14/09/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import "CK2WebDAVConnection.h"

#import "KSPathUtilities.h"
#import "KSWorkspaceUtilities.h"


@implementation CK2WebDAVConnection

+ (void)load
{
    [[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forName:@"WebDAV" URLScheme:@"http"];
}

+ (NSArray *)URLSchemes { return NSARRAY(@"http", @"https"); }

#pragma mark Lifecycle

- (id)initWithRequest:(CKConnectionRequest *)request;
{
    if (self = [self init])
    {
        _session = [[DAVSession alloc] initWithRootURL:[request URL] delegate:self];
        _queue = [[NSMutableArray alloc] init];
        _transferRecordsByRequest = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc;
{
    [_session release];
    [_transferRecordsByRequest release];
    [_queue release];
    [_currentDirectory release];
    
    [super dealloc];
}

#pragma mark Delegate

@synthesize delegate = _delegate;

#pragma mark Queue

static void *sOpFinishObservationContext = &sOpFinishObservationContext;

- (void)runOperation:(NSOperation *)operation
{
    [operation addObserver:self forKeyPath:@"isFinished" options:0 context:sOpFinishObservationContext];
    [operation start];
}

- (void)enqueueOperation:(NSOperation *)operation;
{
    // Assume that only _session targeted invocations are async
    BOOL runNow = [_queue count] == 0;
    [_queue addObject:operation];
    
    if (runNow) [self runOperation:operation];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == sOpFinishObservationContext)
    {
        if ([object isFinished])
        {
            [object removeObserver:self forKeyPath:keyPath];
            [_queue removeObjectIdenticalTo:object];
            
            // Run next op
            if ([_queue count])
            {
                [self runOperation:[_queue objectAtIndex:0]];
            }
        }
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark Connection

- (DAVSession *)webDAVSession; { return _session; }

- (void)connect;
{
    if (!_connected)
    {
        _connected = YES;
        
        if ([[self delegate] respondsToSelector:@selector(connection:didConnectToHost:error:)])
        {
            [[self delegate] connection:self didConnectToHost:[[_session rootURL] host] error:nil];
        }
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
    if ([_queue count])
    {
        [_queue makeObjectsPerformSelector:@selector(cancel)];
        [_queue removeAllObjects];
    }
    
    
    if (_connected)
    {
        _connected = NO;
        
        if ([[self delegate] respondsToSelector:@selector(connection:didDisconnectFromHost:)])
        {
            [[self delegate] connection:self didDisconnectFromHost:[[[self webDAVSession] rootURL] host]];
        }
    }
}

- (BOOL)isConnected { return _connected; }

- (void)webDAVSession:(DAVSession *)session didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [[self delegate] connection:self didReceiveAuthenticationChallenge:challenge];
}

- (void)webDAVSession:(DAVSession *)session didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [[self delegate] connection:self didCancelAuthenticationChallenge:challenge];
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
    
    remotePath = [NSString ks_stringWithPath:remotePath relativeToDirectory:[self currentDirectory]];
    DAVPutRequest *request = [[DAVPutRequest alloc] initWithPath:remotePath session:[self webDAVSession] delegate:self];
    [request setData:data];
    
    NSString *type = [KSWORKSPACE ks_typeForFilenameExtension:[remotePath pathExtension]];
    [request setDataMIMEType:[KSWORKSPACE ks_MIMETypeForType:type]];
    
    [self enqueueOperation:request];
    
    CKTransferRecord *result = [CKTransferRecord recordWithName:[remotePath lastPathComponent] size:[data length]];
    CFDictionarySetValue((CFMutableDictionaryRef)_transferRecordsByRequest, request, result);
    [request release];
    return result;
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions;
{
    return [self createDirectory:dirPath];
}

- (void)createDirectory:(NSString *)dirPath;
{
    dirPath = [NSString ks_stringWithPath:dirPath relativeToDirectory:[self currentDirectory]];
    
    DAVMakeCollectionRequest *request = [[DAVMakeCollectionRequest alloc] initWithPath:dirPath
                                                                               session:[self webDAVSession]
                                                                              delegate:self];
    
    [self enqueueOperation:request];
    [request release];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path; { /* ignore! */ }

- (void)deleteFile:(NSString *)path
{
    path = [NSString ks_stringWithPath:path relativeToDirectory:[self currentDirectory]];
    DAVRequest *request = [[DAVDeleteRequest alloc] initWithPath:path session:[self webDAVSession] delegate:self];
    [self enqueueOperation:request];
    [request release];
}

- (void)directoryContents
{
    DAVListingRequest *request = [[DAVListingRequest alloc] initWithPath:[self currentDirectory]
                                                                 session:[self webDAVSession]
                                                                delegate:self];
    [self enqueueOperation:request];
    [request release];
}

#pragma mark Current Directory

@synthesize currentDirectory = _currentDirectory;

- (void)changeToDirectory:(NSString *)dirPath
{
    if ([_queue count])
    {
        NSInvocation *invocation = [NSInvocation
                                    invocationWithSelector:@selector(connection:didChangeToDirectory:error:)
                                    target:[self delegate]
                                    arguments:NSARRAY(self, dirPath, nil)];
        NSOperation *op = [[NSInvocationOperation alloc] initWithInvocation:invocation];
        [self enqueueOperation:op];
        [op release];
    }
    
    [self setCurrentDirectory:dirPath];
}

#pragma mark Request Delegate

- (void)requestDidBegin:(DAVRequest *)aRequest;
{
    if ([aRequest isKindOfClass:[DAVPutRequest class]] &&
        [[self delegate] respondsToSelector:@selector(connection:uploadDidBegin:)])
    {
        [[self delegate] connection:self uploadDidBegin:[aRequest path]];
    }
}

- (void)webDAVRequest:(DAVRequest *)aRequest didFinishWithResult:(id)result error:(NSError *)error;
{
    if ([aRequest isKindOfClass:[DAVPutRequest class]])
    {
        CKTransferRecord *record = [_transferRecordsByRequest objectForKey:aRequest];
        [record transferDidFinish:record error:error];
        [_transferRecordsByRequest removeObjectForKey:aRequest];
        
        if ([[self delegate] respondsToSelector:@selector(connection:uploadDidFinish:error:)])
        {
            [[self delegate] connection:self uploadDidFinish:[aRequest path] error:error];
        }
    }
    else if ([aRequest isKindOfClass:[DAVMakeCollectionRequest class]])
    {
        if ([[self delegate] respondsToSelector:@selector(connection:didCreateDirectory:error:)])
        {
            [[self delegate] connection:self didCreateDirectory:[aRequest path] error:nil];
        }
    }
    else if ([aRequest isKindOfClass:[DAVDeleteRequest class]])
    {
        if ([[self delegate] respondsToSelector:@selector(connection:didDeleteFile:error:)])
        {
            [[self delegate] connection:self didDeleteFile:[aRequest path] error:error];
        }
    }
    else if ([aRequest isKindOfClass:[DAVListingRequest class]])
    {
        if ([[self delegate] respondsToSelector:@selector(connection:didReceiveContents:ofDirectory:error:)])
        {
            NSString *directory = [aRequest path];
            NSMutableArray *contents = [[NSMutableArray alloc] initWithCapacity:[result count]];
            
            for (DAVResponseItem *aResponseItem in result)
            {
                NSMutableDictionary *attributes = [[aResponseItem fileAttributes] mutableCopy];
                if (!attributes) attributes = [[NSMutableDictionary alloc] initWithCapacity:1];
                
                NSString *path = [aResponseItem href];
                path = [[path ks_pathRelativeToDirectory:directory] ks_standardizedPOSIXPath];
                [attributes setObject:path forKey:cxFilenameKey];
                
                [contents addObject:attributes];
                [attributes release];
            }
            
            [[self delegate] connection:self
                     didReceiveContents:contents
                            ofDirectory:[aRequest path]
                                  error:nil];
            
            [contents release];
        }
    }
}

- (void)request:(DAVRequest *)aRequest didSucceedWithResult:(id)result;
{
    [self webDAVRequest:aRequest didFinishWithResult:result error:nil];   // CK uses nil errors to indicate success because it's dumb
}

- (void)request:(DAVRequest *)aRequest didFailWithError:(NSError *)error;
{
    [self webDAVRequest:aRequest didFinishWithResult:nil error:error];
}

- (void)webDAVRequest:(DAVRequest *)request didSendDataOfLength:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    CKTransferRecord *record = [_transferRecordsByRequest objectForKey:request];
    [record transfer:record transferredDataOfLength:bytesWritten];
}

- commandQueue { return nil; }
- (void)cleanupConnection { }

#pragma mark iDisk

+ (BOOL)getDotMacAccountName:(NSString **)account password:(NSString **)password
{
	BOOL result = NO;
    
	NSString *accountName = [[NSUserDefaults standardUserDefaults] objectForKey:@"iToolsMember"];
	if (accountName)
	{
		UInt32 length;
		void *buffer;
		
        const char *service = "iTools";
		const char *accountKey = (char *)[accountName UTF8String];
		OSStatus theStatus = SecKeychainFindGenericPassword(
                                                            NULL,
                                                            strlen(service), service,
                                                            strlen(accountKey), accountKey,
                                                            &length, &buffer,
                                                            NULL
                                                            );
		
		if (noErr == theStatus)
		{
			if (length > 0)
			{
				if (password) *password = [[[NSString alloc] initWithBytes:buffer length:length encoding:NSUTF8StringEncoding] autorelease];
			}
			else
			{
				if (password) *password = @""; // if we have noErr but also no length, password is empty
			}
            
			// release buffer allocated by SecKeychainFindGenericPassword
			theStatus = SecKeychainItemFreeContent(NULL, buffer);
			
			*account = accountName;
			result = YES;
		}
        else 
        {
            NSLog(@"SecKeychainFindGenericPassword failed %d", theStatus);
        }
	}
	
	return result;
}

@end

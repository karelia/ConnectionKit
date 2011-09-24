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

- (void)runInvocation:(NSInvocation *)invocation
{
    DAVRequest *target = [invocation target];
    [invocation invoke];
    
    if ([target isKindOfClass:[DAVRequest class]])
    {
        if ([target isKindOfClass:[DAVPutRequest class]] &&
            [[self delegate] respondsToSelector:@selector(connection:uploadDidBegin:)])
        {
            [[self delegate] connection:self uploadDidBegin:[target path]];
        }
    }
}

- (void)enqueueInvocation:(NSInvocation *)invocation;
{
    // Assume that only _session targeted invocations are async
    BOOL runNow = [_queue count] == 0;
    
    if (!runNow || [[invocation target] isKindOfClass:[DAVRequest class]])
    {
        [_queue addObject:invocation];
    }
    
    if (runNow) [self runInvocation:invocation];
}

- (void)enqueueRequest:(DAVRequest *)request;
{
    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(start)
                                                             target:request
                                                          arguments:nil];
    [invocation retainArguments];
    [self enqueueInvocation:invocation];
}

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
    [self enqueueInvocation:[NSInvocation invocationWithSelector:@selector(forceDisconnect)
                                                          target:self
                                                       arguments:nil]];
}

- (void)forceDisconnect
{
    // Cancel all in queue
    if ([_queue count])
    {
        NSInvocation *firstInvocation = [_queue objectAtIndex:0];
        id target = [firstInvocation target];
        if ([target isKindOfClass:[DAVRequest class]])
        {
            [target cancel];
        }
        
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
    
    [self enqueueRequest:request];
    
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
    
    [self enqueueRequest:request];
    [request release];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path; { /* ignore! */ }

- (void)deleteFile:(NSString *)path
{
    path = [NSString ks_stringWithPath:path relativeToDirectory:[self currentDirectory]];
    DAVRequest *request = [[DAVDeleteRequest alloc] initWithPath:path session:[self webDAVSession] delegate:self];
    [self enqueueRequest:request];
    [request release];
}

- (void)directoryContents
{
    DAVListingRequest *request = [[DAVListingRequest alloc] initWithPath:[self currentDirectory]
                                                                 session:[self webDAVSession]
                                                                delegate:self];
    [self enqueueRequest:request];
    [request release];
}

#pragma mark Current Directory

@synthesize currentDirectory = _currentDirectory;

- (void)changeToDirectory:(NSString *)dirPath
{
    if ([_queue count])
    {
        [self enqueueInvocation:[NSInvocation
                                 invocationWithSelector:@selector(connection:didChangeToDirectory:error:)
                                 target:[self delegate]
                                 arguments:NSARRAY(self, dirPath, nil)]];
    }
    
    [self setCurrentDirectory:dirPath];
}

#pragma mark Request Delegate

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
    
    
    // Move onto next request
    [_queue removeObjectAtIndex:0];
    while ([_queue count])
    {
        NSInvocation *next = [[_queue objectAtIndex:0] retain];
        [self runInvocation:next];
        id target = [next target];
        [next release];
        
        if ([target isKindOfClass:[DAVRequest class]])
        {
            break;   // async
        }
        else
        {
            if ([_queue count]) [_queue removeObjectAtIndex:0]; // running the invocation might empty the queue if it's a disconnect
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

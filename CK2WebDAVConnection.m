//
//  CK2WebDAVConnection.m
//  Sandvox
//
//  Created by Mike on 14/09/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import "CK2WebDAVConnection.h"

#import "KSPathUtilities.h"


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
        _URL = [[request URL] copy];
        _queue = [[NSMutableArray alloc] init];
        _transferRecordsByRequest = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc;
{
    [_URL release];
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
    [invocation invoke];
    
    if ([invocation target] == _session &&
        [invocation selector] == @selector(enqueueRequest:))
    {
        DAVRequest *request;
        [invocation getArgument:&request atIndex:2];
        
        if ([request isKindOfClass:[DAVPutRequest class]] &&
            [[self delegate] respondsToSelector:@selector(connection:uploadDidBegin:)])
        {
            [[self delegate] connection:self uploadDidBegin:[request path]];
        }
    }
}

- (void)enqueueInvocation:(NSInvocation *)invocation;
{
    // Assume that only _session targeted invocations are async
    BOOL runNow = [_queue count] == 0;
    
    if (!runNow || [invocation target] == _session)
    {
        [_queue addObject:invocation];
    }
    
    if (runNow) [self runInvocation:invocation];
}

- (void)enqueueRequest:(DAVRequest *)request;
{
    [self connect];
    
    [request setDelegate:self];
    
    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(enqueueRequest:)
                                                             target:_session
                                                          arguments:NSARRAY(request)];
    
    [self enqueueInvocation:invocation];
}

- (void)connect;
{
    if (!_session)
    {
        _session = [[DAVSession alloc] initWithRootURL:_URL delegate:self];
        
        if ([[self delegate] respondsToSelector:@selector(connection:didConnectToHost:error:)])
        {
            [[self delegate] connection:self didConnectToHost:[_URL host] error:nil];
        }
    }
}

- (void)disconnect;
{
    if ([[self delegate] respondsToSelector:@selector(connection:didDisconnectFromHost:)])
    {
        [self enqueueInvocation:[NSInvocation invocationWithSelector:@selector(connection:didDisconnectFromHost:)
                                                              target:[self delegate]
                                                           arguments:NSARRAY(self, [_URL host])]];
    }
}

- (void)forceDisconnect { }
- (BOOL)isConnected { return NO; }

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
    
    remotePath = [NSString ks_stringWithPath:remotePath relativeToDirectory:[self currentDirectoryPath]];
    DAVPutRequest *request = [[DAVPutRequest alloc] initWithPath:remotePath];
    [request setData:data];
    [self enqueueRequest:request];
    [request release];
    
    CKTransferRecord *result = [CKTransferRecord recordWithName:[remotePath lastPathComponent] size:[data length]];
    CFDictionarySetValue((CFMutableDictionaryRef)_transferRecordsByRequest, request, result);
    return result;
}

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions;
{
    return [self createDirectory:dirPath];
}

- (void)createDirectory:(NSString *)dirPath;
{
    dirPath = [NSString ks_stringWithPath:dirPath relativeToDirectory:[self currentDirectoryPath]];
    DAVMakeCollectionRequest *request = [[DAVMakeCollectionRequest alloc] initWithPath:dirPath];
    [self enqueueRequest:request];
    [request release];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path; { /* ignore! */ }

- (void)deleteFile:(NSString *)path
{
    path = [NSString ks_stringWithPath:path relativeToDirectory:[self currentDirectoryPath]];
    DAVRequest *request = [[DAVDeleteRequest alloc] initWithPath:path];
    [self enqueueRequest:request];
    [request release];
}

#pragma mark Current Directory

@synthesize currentDirectoryPath = _currentDirectory;

- (void)changeToDirectory:(NSString *)dirPath
{
    if ([_queue count])
    {
        [self enqueueInvocation:[NSInvocation
                                 invocationWithSelector:@selector(connection:didChangeToDirectory:error:)
                                 target:[self delegate]
                                 arguments:NSARRAY(self, dirPath, nil)]];
    }
    
    [self setCurrentDirectoryPath:dirPath];
}

#pragma mark Request Delegate

- (void)request:(DAVRequest *)aRequest didSucceedWithResult:(id)result;
{
    [self request:aRequest didFailWithError:nil];   // CK uses nil errors to indicate success because it's dumb
}

- (void)request:(DAVRequest *)aRequest didFailWithError:(NSError *)error;
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
    
    
    // Move onto next request
    [_queue removeObjectAtIndex:0];
    while ([_queue count])
    {
        NSInvocation *next = [_queue objectAtIndex:0];
        [self runInvocation:next];
        if ([next target] == _session)
        {
            break;   // async
        }
        else
        {
            [_queue removeObjectAtIndex:0];
        }    
    }
}

- commandQueue { return nil; }

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

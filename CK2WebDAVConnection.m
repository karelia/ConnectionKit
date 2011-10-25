//
//  CK2WebDAVConnection.m
//  Sandvox
//
//  Created by Mike on 14/09/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import "CK2WebDAVConnection.h"

#import <DAVKit/DAVKit.h>


@implementation CK2WebDAVConnection

+ (void)load
{
    [[CKConnectionRegistry sharedConnectionRegistry] registerClass:self forName:@"WebDAV" URLScheme:@"http"];
}

+ (NSArray *)URLSchemes { return NSARRAY(@"http", @"https"); }

- (id)initWithRequest:(CKConnectionRequest *)request;
{
    if (self = [self init])
    {
        _URL = [[request URL] copy];
    }
    return self;
}

@synthesize delegate = _delegate;

- (void)connect;
{
    if (!_session)
    {
        NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:[_URL host] port:[[_URL port] integerValue] protocol:[_URL scheme] realm:nil authenticationMethod:nil];
        
        _challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space proposedCredential:nil previousFailureCount:0 failureResponse:nil error:nil sender:self];
        [space release];
        
        [[self delegate] connection:self didReceiveAuthenticationChallenge:_challenge];
    }
}

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    OBPRECONDITION(challenge == _challenge);
    [_challenge release]; _challenge = nil;
    
    _session = [[DAVSession alloc] initWithRootURL:_URL credentials:credential];
    [_session setMaxConcurrentRequests:1];
    
    [[self delegate] connection:self didConnectToHost:[_URL host] error:nil];
}

- (void)cancelAll { }
- (void)forceDisconnect { }

- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions;
{
    return [self createDirectory:dirPath];
}

- (void)createDirectory:(NSString *)dirPath;
{
    DAVMakeCollectionRequest *request = [[DAVMakeCollectionRequest alloc] initWithPath:dirPath];
    [request setDelegate:self];
    [_session enqueueRequest:request];
    [request release];
}

- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path; { /* ignore! */ }
- (void)changeToDirectory:(NSString *)dirPath { }

- (void)request:(DAVRequest *)aRequest didSucceedWithResult:(id)result;
{
    [self request:aRequest didFailWithError:nil];   // CK uses nil errors to indiciate success because it's dumb
}

- (void)request:(DAVRequest *)aRequest didFailWithError:(NSError *)error;
{
    if ([aRequest isKindOfClass:[DAVMakeCollectionRequest class]])
    {
        if ([[self delegate] respondsToSelector:@selector(connection:didCreateDirectory:error:)])
        {
            [[self delegate] connection:self didCreateDirectory:[aRequest path] error:nil];
        }
    }
}

@end

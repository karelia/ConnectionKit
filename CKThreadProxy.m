//
//  CKThreadProxy.m
//  Connection
//
//  Created by Mike on 17/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKThreadProxy.h"

#import "CKFileTransferProtocol.h"


@interface CKAuthenticationChallengeSenderThreadProxy : NSProxy <NSURLAuthenticationChallengeSender>
{
  @public   // bit dodgy, but reasonable as this is a private class
    id                              _target;
    NSThread                        *_thread;
    NSURLAuthenticationChallenge    *_originalChallenge;
    NSURLAuthenticationChallenge    *_challenge;    // weak ref
}
@end


@implementation CKThreadProxy

#pragma mark Initialization & Deallocation

+ (id)CK_proxyWithTarget:(id <NSObject>)target thread:(NSThread *)thread
{
    NSParameterAssert(target);
    
    CKThreadProxy *result = [self alloc];
    result->_target = [target retain];
    
    if (!thread) thread = [NSThread mainThread];
    result->_thread = [thread retain];
    
    return [result autorelease];
}

- (void)dealloc
{
    [_thread release];
    [_target release];
    
    [super dealloc];
}

#pragma mark Method Forwarding

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    NSMethodSignature *result = [_target methodSignatureForSelector:aSelector];
    return result;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    [anInvocation retainArguments];
    [anInvocation performSelector:@selector(invokeWithTarget:)
                         onThread:_thread
                       withObject:_target
                    waitUntilDone:([[anInvocation methodSignature] methodReturnLength] > 0)];
}

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol
    didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    //  Set up a special thread proxy to handle the delegate's response to the challenge.
CKAuthenticationChallengeSenderThreadProxy *senderProxy = [CKAuthenticationChallengeSenderThreadProxy alloc];
    
    senderProxy->_target = [[challenge sender] retain];
    senderProxy->_thread = [[NSThread currentThread] retain];
    senderProxy->_originalChallenge = [challenge retain];
    
    NSURLAuthenticationChallenge *newChallenge =
    [[NSURLAuthenticationChallenge alloc] initWithAuthenticationChallenge:challenge sender:senderProxy];
    senderProxy->_challenge = newChallenge;
    [newChallenge autorelease];
    
    [senderProxy release];  // it will be retained by newChallenge
    
    
    // Forward the new challenge onto the target thread as usual
    NSMethodSignature *signature = [_target methodSignatureForSelector:_cmd];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setSelector:_cmd];
    [invocation setArgument:&protocol atIndex:2];
    [invocation setArgument:&newChallenge atIndex:3];
    
    [self forwardInvocation:invocation];
}

@end


#pragma mark -


@implementation CKAuthenticationChallengeSenderThreadProxy   // quite a mouthful!

- (void)dealloc
{
    [_thread release];
    [_target release];
    [_originalChallenge release];
    
    [super dealloc];
}

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSParameterAssert(challenge == _challenge);
    
    NSMethodSignature *signature = [_target methodSignatureForSelector:_cmd];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:_target];
    [invocation setSelector:_cmd];
    [invocation setArgument:&credential atIndex:2];
    [invocation setArgument:&_originalChallenge atIndex:3];
    [invocation retainArguments];
    
    [invocation performSelector:@selector(invoke) onThread:_thread withObject:nil waitUntilDone:NO];
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSParameterAssert(challenge == _challenge);
    [_target performSelector:_cmd onThread:_thread withObject:_originalChallenge waitUntilDone:NO];
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSParameterAssert(challenge == _challenge);
    [_target performSelector:_cmd onThread:_thread withObject:_originalChallenge waitUntilDone:NO];
}

@end


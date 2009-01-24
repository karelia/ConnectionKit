//
//  CKConnection+Private.m
//  Connection
//
//  Created by Mike on 24/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKConnection+Private.h"

#import "CKConnectionError.h"
#import "RunLoopForwarder.h"
#import "CKConnectionAuthentication+Internal.h"


@implementation CKConnectionProtocolClient

#pragma mark Init & Dealloc

- (id)initWithConnection:(CKConnection *)connection
{
    [super init];
    
    _connection = connection;   // weak ref
    
    _threadProxy = [[RunLoopForwarder alloc] init]; // TODO: replace RunLoopForwarder with an NSProxy derived class
    [_threadProxy setDelegate:connection];
    [_threadProxy setUseMainThread:YES];
    
    return self;
}

- (void)dealloc
{
    [_threadProxy release];
    [super dealloc];
}

#pragma mark Accessors

- (CKConnection *)connection { return _connection; }

- (CKConnectionProtocol *)connectionProtocol { return _protocol; }

- (void)setConnectionProtocol:(CKConnectionProtocol *)protocol
{
    // This method should only be called the once, while setting up the stack
    NSParameterAssert(protocol);
    NSAssert1(!_protocol, @"%@ already has a protocol associated with it", self);
    
    
    _protocol = protocol;   // weak ref
}

- (CKConnection *)connectionThreadProxy { return (CKConnection *)_threadProxy; }
    
#pragma mark Overall connection

/*  Sending a message directly from the worker thread to the delegate is a bad idea as it is
 *  possible the connection may have been cancelled by the time the message is delivered. Instead,
 *  deliver messages to ourself on the main thread and then forward them on to the delegate if
 *  appropriate.
 */

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didOpenConnectionAtPath:(NSString *)path
{
	NSAssert2(protocol == [self connectionProtocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    NSAssert([[self connection] status] == CKConnectionStatusOpening, @"The connection is not ready to be opened");  // This should never be called twice
    
    [[self connectionThreadProxy] connectionProtocol:protocol didOpenConnectionAtPath:path];
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didFailWithError:(NSError *)error;
{
	NSAssert2(protocol == [self connectionProtocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    [[self connectionThreadProxy] connectionProtocol:protocol didFailWithError:error];
}

#pragma mark Authorization

/*  Support method for filling an NSURLAuthenticationChallenge object. If no credential was supplied,
 *  looks for one from the connection's URL, and then falls back to using NSURLCredentialStorage.
 */
- (NSURLAuthenticationChallenge *)_fullAuthenticationChallengeForChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSURLAuthenticationChallenge *result = challenge;
    
    NSURLCredential *credential = [challenge proposedCredential];
    if (!credential)
    {
        NSURL *connectionURL = [[[self connection] connectionRequest] URL];
        
        NSString *user = [connectionURL user];
        if (user)
        {
            NSString *password = [connectionURL password];
            if (password)
            {
                credential = [[[NSURLCredential alloc] initWithUser:user password:password persistence:NSURLCredentialPersistenceNone] autorelease];
            }
            else
            {
                credential = [[[NSURLCredentialStorage sharedCredentialStorage] credentialsForProtectionSpace:[challenge protectionSpace]] objectForKey:user];
                if (!result)
                {
                    credential = [[[NSURLCredential alloc] initWithUser:user password:nil persistence:NSURLCredentialPersistenceNone] autorelease];
                }
            }
        }
        else
        {
            credential = [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:[challenge protectionSpace]];
        }
        
        
        // Create a new request with the credential
        if (credential)
        {
            result = [[NSURLAuthenticationChallenge alloc] initWithAuthenticationChallenge:challenge
                                                                        proposedCredential:credential];
            [result autorelease];
        }
    }
    
    return result;
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
	NSAssert2(protocol == [self connectionProtocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    NSAssert([[self connection] status] > CKConnectionStatusNotOpen, @"The connection has not started yet");  // Should only happen while running
    
    
    // Fill in missing credentials if possible
    NSURLAuthenticationChallenge *fullChallenge = challenge;
    if (![challenge proposedCredential])
    {
        fullChallenge = [self _fullAuthenticationChallengeForChallenge:challenge];
    }
    
    
    // Does the delegate support this? If not, handle it ourselves
    id delegate = [[self connection] delegate];
    if (delegate && [delegate respondsToSelector:@selector(connection:didReceiveAuthenticationChallenge:)])
    {
        // Set up a proxy -sender object to forward the request to the main thread
        CKAuthenticationChallengeSender *sender = [[CKAuthenticationChallengeSender alloc] initWithAuthenticationChallenge:challenge];
        NSURLAuthenticationChallenge *delegateChallenge = [[NSURLAuthenticationChallenge alloc] initWithAuthenticationChallenge:fullChallenge sender:sender];
        [sender release];
        
        [[self connectionThreadProxy] connectionProtocol:protocol
                       didReceiveAuthenticationChallenge:delegateChallenge];
        
        [delegateChallenge release];
    }
    else
    {
        NSURLCredential *credential = [fullChallenge proposedCredential];
        if ([credential user] && [credential hasPassword] && [challenge previousFailureCount] == 0)
        {
            [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
        }
        else
        {
            [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
        }
    }
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSAssert2(protocol == [self connectionProtocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    [[self connectionThreadProxy] connectionProtocol:protocol didCancelAuthenticationChallenge:challenge];
}

#pragma mark Operation

- (void)connectionProtocolDidFinishCurrentOperation:(CKConnectionProtocol *)protocol;
{
    NSAssert2(protocol == [self connectionProtocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    
    // For recursive directory creation that has successfully created a parent directory, proceed to
    // the next child directory
    CKConnectionOperation *operation = [[self connection] currentOperation];
    CKConnectionOperation *mainOperation = [operation mainOperation];
    BOOL reportSuccess = YES;
    
    if ([operation operationType] == CKConnectionOperationCreateDirectory && mainOperation)
    {
        NSString *finalPath = [mainOperation path];
        NSString *path = [operation path];
        if (![finalPath isEqualToString:path])
        {
            NSString *nextPath = [path stringByAppendingPathComponent:[[finalPath pathComponents] objectAtIndex:[[path pathComponents] count]]];
            
            CKConnectionOperation *newOp = [[CKConnectionOperation alloc]
                                            initCreateDirectoryOperationWithIdentifier:[operation identifier]
                                            path:nextPath
                                            recursive:NO
                                            mainOperation:mainOperation];
            [[self connection] setCurrentOperation:newOp];
            [newOp release];
            
            // Try the next operation
            reportSuccess = NO;
            [[self connectionProtocol] createDirectoryAtPath:nextPath];
        }
    }
    
    if (reportSuccess)
    {
        [[self connectionThreadProxy] connectionProtocolDidFinishCurrentOperation:protocol];
    }
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol currentOperationDidFailWithError:(NSError *)error;
{
    NSAssert2(protocol == [self connectionProtocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    
    // For recursive directory creation, try to create the parent directory rather than fail if possible.
    BOOL reportError = YES;
    CKConnectionOperation *operation = [[self connection] currentOperation];
    
    if ([operation operationType] == CKConnectionOperationCreateDirectory &&
        [operation isRecursive] &&
        [[error domain] isEqualToString:CKConnectionErrorDomain] &&
        [error code] == CKConnectionErrorFileDoesNotExist)
    {
        NSString *path = [[operation path] stringByDeletingLastPathComponent];
        if (![path isEqualToString:@"/"])
        {
            CKConnectionOperation *newOp = [[CKConnectionOperation alloc]
                                            initCreateDirectoryOperationWithIdentifier:[operation identifier]
                                            path:path
                                            recursive:YES
                                            mainOperation:([operation mainOperation] ? [operation mainOperation] : operation)];
            [[self connection] setCurrentOperation:newOp];
            [newOp release];
            
            // Try the new operation
            reportError = NO;
            [[self connectionProtocol] createDirectoryAtPath:path];
        }
    }
    
    if (reportError)
    {
        [[self connectionThreadProxy] connectionProtocol:protocol currentOperationDidFailWithError:error];
    }
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didDownloadData:(NSData *)data;
{
    NSAssert2(protocol == [self connectionProtocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    [[self connectionThreadProxy] connectionProtocol:protocol didDownloadData:data];
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didUploadDataOfLength:(NSUInteger)length;
{
    NSAssert2(protocol == [self connectionProtocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    [[self connectionThreadProxy] connectionProtocol:protocol didUploadDataOfLength:length];
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didLoadContentsOfDirectory:(NSArray *)contents;
{
    NSAssert2(protocol == [self connectionProtocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    [[self connectionThreadProxy] connectionProtocol:protocol didLoadContentsOfDirectory:contents];
}

#pragma mark Transcript

/*	Convenience method for sending a string to the delegate for appending to the transcript
 */
- (void)connectionProtocol:(CKConnectionProtocol *)protocol appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript
{
	NSAssert2(protocol == [self connectionProtocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    [[self connectionThreadProxy] connectionProtocol:protocol appendString:string toTranscript:transcript];
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol appendFormat:(NSString *)formatString toTranscript:(CKTranscriptType)transcript, ...
{
	va_list arguments;
	va_start(arguments, transcript);
	NSString *string = [[NSString alloc] initWithFormat:formatString arguments:arguments];
	va_end(arguments);
	
	[self connectionProtocol:protocol appendString:string toTranscript:transcript];
	[string release];
}

@end

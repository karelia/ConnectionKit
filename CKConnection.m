//
//  CKConnection.m
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKConnection.h"

#import "CKAuthenticationChallengeSender.h"
#import "CKConnectionError.h"
#import "CKConnectionProtocol1.h"
#import "CKConnectionOperation.h"
#import "CKConnectionThreadManager.h"

#import "NSInvocation+ConnectionKit.h"
#import "NSURLAuthentication+ConnectionKit.h"


NSString * const CKConnectionErrorDomain = @"ConnectionErrorDomain";


@interface CKConnection (Private)
- (CKConnectionProtocol *)protocol;
@end


@interface CKConnection (QueueInternal)
- (void)enqueueOperation:(CKConnectionOperation *)operation;
- (id)enqueueOperationWithInvocation:(NSInvocation *)invocation identifier:(id <NSObject>)identifier;
- (void)dequeueOperation;
@end


@interface CKConnection (ProtocolClientWorkerThread) <CKConnectionProtocolClient>
@end


#pragma mark -


@implementation CKConnection

#pragma mark Init & Dealloc

+ (CKConnection *)connectionWithConnectionRequest:(CKConnectionRequest *)request delegate:(id)delegate
{
    return [[[self alloc] initWithConnectionRequest:request delegate:delegate] autorelease];
}

/*  Should return nil if no protocol can be found
 */
- (id)initWithConnectionRequest:(CKConnectionRequest *)request delegate:(id)delegate
{
    [super init];
    
    Class protocolClass = [CKConnectionProtocol classForRequest:request];
    if (protocolClass)
    {
        _request = [request copy];
        _delegate = delegate;
        _queue = [[NSMutableArray alloc] init];
        
        // Start connection
        _protocol = [[protocolClass alloc] initWithRequest:[self connectionRequest] client:self];
        _status = CKConnectionStatusOpening;
        [[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:_protocol] startConnection];
    }
    else
    {
        [self release];
        self = nil;
    }
    
    return self;
}

- (void)dealloc
{
    NSAssert(!_currentOperationIdentifier, @"Deallocing connection mid-operation");
    NSAssert([_queue count] == 0, @"Dealling connection with items still on the queue");
    [_queue release];
    [_currentOperationIdentifier release];
    
    [_request release];
    [_protocol release];
    [_name release];
    
    [super dealloc];
}

#pragma mark Delegate

- (id)delegate { return _delegate; }

#pragma mark Accessors

- (CKConnectionRequest *)connectionRequest { return _request; }

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
    name = [name copy];
    [_name release];
    _name = name;
}

- (CKConnectionProtocol *)protocol
{
    return _protocol;   // _protocol is an id to provide less of a hint to external code
}

#pragma mark Connection

- (void)cancel
{
    _delegate = nil;    // It'll stop receiving messages
}

- (id)downloadContentsOfPath:(NSString *)path identifier:(id <NSObject>)identifier
{
    NSInvocation *invocation = [NSInvocation invocationWithTarget:[self protocol]
                                                         selector:@selector(downloadContentsOfFileAtPath:)];
    [invocation setArgument:&path atIndex:2];
    
    id result = [self enqueueOperationWithInvocation:invocation identifier:identifier];
    
    return result;
}

- (id)uploadData:(NSData *)data toPath:(NSString *)path identifier:(id <NSObject>)identifier
{
    NSInvocation *invocation = [NSInvocation invocationWithTarget:[self protocol]
                                                         selector:@selector(uploadData:toPath:)];
    [invocation setArgument:&data atIndex:2];
    [invocation setArgument:&path atIndex:3];
    
    id result = [self enqueueOperationWithInvocation:invocation identifier:identifier];
    return result;
}

- (id)listContentsOfDirectoryAtPath:(NSString *)path identifier:(id <NSObject>)identifier;
{
    NSInvocation *invocation = [NSInvocation invocationWithTarget:[self protocol]
                                                         selector:@selector(fetchContentsOfDirectoryAtPath:)];
    [invocation setArgument:&path atIndex:2];
    
    id result = [self enqueueOperationWithInvocation:invocation identifier:identifier];
    
    return result;
}

- (id)createDirectoryAtPath:(NSString *)path identifier:(id <NSObject>)identifier;
{
    NSInvocation *invocation = [NSInvocation invocationWithTarget:[self protocol]
                                                         selector:@selector(createDirectoryAtPath:)];
    [invocation setArgument:&path atIndex:2];
    
    id result = [self enqueueOperationWithInvocation:invocation identifier:identifier];
    
    return result;
}

- (id)moveItemAtPath:(NSString *)sourcePath toPath:(NSString *)destinationPath identifier:(id <NSObject>)identifier;
{
    NSInvocation *invocation = [NSInvocation invocationWithTarget:[self protocol]
                                                         selector:@selector(moveItemAtPath:toPath:)];
    [invocation setArgument:&sourcePath atIndex:2];
    [invocation setArgument:&destinationPath atIndex:3];
    
    id result = [self enqueueOperationWithInvocation:invocation identifier:identifier];
    return result;
}

- (id)setPermissions:(unsigned long)posixPermissions ofItemAtPath:(NSString *)path identifier:(id <NSObject>)identifier;
{
    NSInvocation *invocation = [NSInvocation invocationWithTarget:[self protocol]
                                                         selector:@selector(setPermissions:ofItemAtPath:)];
    [invocation setArgument:&posixPermissions atIndex:2];
    [invocation setArgument:&path atIndex:3];
    
    id result = [self enqueueOperationWithInvocation:invocation identifier:identifier];
    return result;
}

- (id)deleteItemAtPath:(NSString *)path identifier:(id <NSObject>)identifier;
{
    NSInvocation *invocation = [NSInvocation invocationWithTarget:[self protocol]
                                                         selector:@selector(deleteItemAtPath:)];
    [invocation setArgument:&path atIndex:2];
    
    id result = [self enqueueOperationWithInvocation:invocation identifier:identifier];
    
    return result;
}

@end


#pragma mark -


@implementation CKConnection (Queue)

/*  Adds the operation to the queue or starts it immediately if nothing else is in progress
 */
- (void)enqueueOperation:(CKConnectionOperation *)operation
{
    [_queue insertObject:operation atIndex:0];
    [self dequeueOperation];
}

/*  Convenience method to enqueue an operation for the specified invocaton
 */
- (id)enqueueOperationWithInvocation:(NSInvocation *)invocation identifier:(id <NSObject>)identifier
{
    id result = (identifier) ? identifier : [[[NSObject alloc] init] autorelease];
    
    CKConnectionOperation *operation = [[CKConnectionOperation alloc] initWithIdentifier:result
                                                                              invocation:invocation];
    [self enqueueOperation:operation];
    [operation release];
    
    return result;
}

/*  Starts the next operation if the connection is ready
 */
- (void)dequeueOperation
{
    if (!_currentOperationIdentifier && _status == CKConnectionStatusOpen)
    {
        // Remove from the queue
        CKConnectionOperation *operation = [[_queue lastObject] retain];
        if (operation)
        {
            [_queue removeLastObject];
            _currentOperationIdentifier = [[operation identifier] retain];
        
            // Inform delegate
            id delegate = [self delegate];
            if (delegate && [delegate respondsToSelector:@selector(connection:operationDidBegin:)])
            {
                [delegate connection:self operationDidBegin:_currentOperationIdentifier];
            }
            
            // invoke method on the worker thread
            [[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:[operation invocation]] invoke];
            [operation release];
        }
    }
}

- (id )currentOperationIdentifier { return _currentOperationIdentifier; }

- (void)currentOperationDidStop
{
    [_currentOperationIdentifier release];
    _currentOperationIdentifier = nil;
}

@end


#pragma mark -


@implementation CKConnection (ProtocolClientMainThread)

/*  These methods are invoked in response to a message to the protocol client. They happen on the
 *  main thread and are responsible for:
 *      A) informing the delegate
 *      B) dispatching the next operation
 */

- (void)protocolDidOpenConnectionAtPath:(NSString *)path
{
    _status = CKConnectionStatusOpen;
    
    // We're ready to start processing
    [self dequeueOperation];
    
    // Inform the delegate
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(connection:didOpenAtPath:)])
    {
        [delegate connection:self didOpenAtPath:path];
    }
}

- (void)protocolDidFailWithError:(NSError *)error
{
    // Inform the delegate
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(connection:didFailWithError:)])
    {
        [delegate performSelector:@selector(connection:didFailWithError:) withObject:self withObject:error];
    }
    
    // TODO: Stop any further processing of the queue, or messages to the delegate
}

#pragma mark Authorization

- (void)protocolDidReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    // Inform the delegate
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(connection:didReceiveAuthenticationChallenge:)])
    {
        [delegate performSelector:@selector(connection:didReceiveAuthenticationChallenge:)
                       withObject:self
                       withObject:challenge];
    }
}

- (void)protocolDidCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    
}

#pragma mark Operations

- (void)protocolCurrentOperationDidFinish
{
    // Inform the delegate
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(connection:operationDidFinish:)])
    {
        [delegate connection:self operationDidFinish:[self currentOperationIdentifier]];
    }
    
    
    // Move onto the next operation
    [self currentOperationDidStop];
    [self dequeueOperation];
}

- (void)protocolCurrentOperationDidFailWithError:(NSError *)error
{
    // Inform the delegate. Gives it a chance to e.g. cancel the connection in response
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(connection:operation:didFailWithError:)])
    {
        [delegate connection:self operation:[self currentOperationIdentifier] didFailWithError:error];
    }
    
    
    [self currentOperationDidStop];
    [self dequeueOperation];
}

- (void)protocolDidDownloadData:(NSData *)data
{
    // Inform the delegate. Gives it a chance to e.g. cancel the connection in response
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(connection:download:didReceiveData:)])
    {
        [delegate connection:self download:[self currentOperationIdentifier] didReceiveData:data];
    }
}

- (void)protocolDidUploadDataOfLength:(NSUInteger)length
{
    // Inform the delegate. Gives it a chance to e.g. cancel the connection in response
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(connection:upload:didSendDataOfLength:)])
    {
        [delegate connection:self upload:[self currentOperationIdentifier] didSendDataOfLength:length];
    }
}

- (void)protocolDidFetchContentsOfDirectory:(NSArray *)contents
{
    
}

@end


#pragma mark -


@implementation CKConnection (ProtocolClientWorkerThread)

/*  Sending a message directly from the worker thread to the delegate is a bad idea as it is
 *  possible the connection may have been cancelled by the time the message is delivered. Instead,
 *  deliver messages to ourself on the main thread and then forward them on to the delegate if
 *  appropriate.
 */

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didOpenConnectionAtPath:(NSString *)path
{
    if (protocol != [self protocol]) return;
    
    NSAssert(_status == CKConnectionStatusOpening, @"The connection is not ready to be opened");  // This should never be called twice
    
    
    [self performSelectorOnMainThread:@selector(protocolDidOpenConnectionAtPath:) withObject:path waitUntilDone:NO];
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didFailWithError:(NSError *)error;
{
    if (protocol != [self protocol]) return;
    
    
    [self performSelectorOnMainThread:@selector(protocolDidFailWithError:) withObject:error waitUntilDone:NO];
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
        NSURL *connectionURL = [[self connectionRequest] URL];
        
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
    if (protocol != [self protocol]) return;
    
    
    NSAssert(_status > CKConnectionStatusNotOpen, @"The connection has not started yet");  // Should only happen while running
    
    
    // Fill in missing credentials if possible
    NSURLAuthenticationChallenge *fullChallenge = challenge;
    if (![challenge proposedCredential])
    {
        fullChallenge = [self _fullAuthenticationChallengeForChallenge:challenge];
    }
    
    
    // Does the delegate support this? If not, handle it ourselves
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(connection:didReceiveAuthenticationChallenge:)])
    {
        // Set up a proxy -sender object to forward the request to the main thread
        CKAuthenticationChallengeSender *sender = [[CKAuthenticationChallengeSender alloc] initWithAuthenticationChallenge:challenge];
        NSURLAuthenticationChallenge *delegateChallenge = [[NSURLAuthenticationChallenge alloc] initWithAuthenticationChallenge:fullChallenge sender:sender];
        [sender release];
        
        [self performSelectorOnMainThread:@selector(protocolDidReceiveAuthenticationChallenge:)
                               withObject:delegateChallenge
                            waitUntilDone:NO];
        
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
    if (protocol != [self protocol]) return;
    
    
    [self performSelectorOnMainThread:@selector(protocolDidCancelAuthenticationChallenge:) withObject:challenge waitUntilDone:NO];
}

#pragma mark Operation

- (void)connectionProtocolDidFinishCurrentOperation:(CKConnectionProtocol *)protocol;
{
    if (protocol != [self protocol]) return;
    
    
    [self performSelectorOnMainThread:@selector(protocolCurrentOperationDidFinish) withObject:nil waitUntilDone:NO];
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol currentOperationDidFailWithError:(NSError *)error;
{
    if (protocol != [self protocol]) return;
    
    
    [self performSelectorOnMainThread:@selector(protocolCurrentOperationDidFailWithError:) withObject:error waitUntilDone:NO];
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didDownloadData:(NSData *)data;
{
    if (protocol != [self protocol]) return;
    
    
    [self performSelectorOnMainThread:@selector(protocolDidDownloadData:) withObject:data waitUntilDone:NO];
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didUploadDataOfLength:(NSUInteger)length;
{
    if (protocol != [self protocol]) return;
    
    
    NSInvocation *invocation = [NSInvocation invocationWithTarget:self selector:@selector(protocolDidUploadDataOfLength:)];
    [invocation setArgument:&length atIndex:2];
    [invocation retainArguments];
    
    [self performSelectorOnMainThread:@selector(invoke) withObject:invocation waitUntilDone:NO];
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didLoadContentsOfDirectory:(NSArray *)contents;
{
    if (protocol != [self protocol]) return;
    
    
    [self performSelectorOnMainThread:@selector(protocolDidFetchContentsOfDirectory:) withObject:contents waitUntilDone:NO];
}

#pragma mark Transcript

/*	Convenience method for sending a string to the delegate for appending to the transcript
 */
- (void)connectionProtocol:(CKConnectionProtocol *)protocol appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript
{
	if (protocol != [self protocol]) return;
    
    
    NSInvocation *invocation = [NSInvocation invocationWithTarget:self selector:@selector(protocolAppendString:toTranscript:)];
    [invocation setArgument:&string atIndex:2];
    [invocation setArgument:&transcript atIndex:3];
    [invocation retainArguments];
    
    [self performSelectorOnMainThread:@selector(invoke) withObject:invocation waitUntilDone:NO];
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol appendFormat:(NSString *)formatString toTranscript:(CKTranscriptType)transcript, ...
{
	if (protocol != [self protocol]) return;
    
    
    va_list arguments;
	va_start(arguments, transcript);
	NSString *string = [[NSString alloc] initWithFormat:formatString arguments:arguments];
	va_end(arguments);
	
	[self connectionProtocol:protocol appendString:string toTranscript:transcript];
	[string release];
}

@end

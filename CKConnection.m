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
- (void)dequeueOperation;
@end


@interface CKConnection (WorkerThread) <CKConnectionProtocolClient>
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
    NSAssert(!_currentOperation, @"Deallocating connection mid-operation");
    NSAssert([_queue count] == 0, @"Deallocating connection with items still on the queue");
    [_queue release];
    [_currentOperation release];
    
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
    CKConnectionOperation *operation = [[CKConnectionOperation alloc] initDownloadOperationWithIdentifier:identifier
                                                                                                     path:path];
    [self enqueueOperation:operation];
    [operation release];
    
    return [operation identifier];
}

- (id)uploadData:(NSData *)data toPath:(NSString *)path identifier:(id <NSObject>)identifier
{
    CKConnectionOperation *operation = [[CKConnectionOperation alloc] initUploadOperationWithIdentifier:identifier
                                                                                                   path:path
                                                                                                   data:data];
    [self enqueueOperation:operation];
    [operation release];
    
    return [operation identifier];
}

- (id)listContentsOfDirectoryAtPath:(NSString *)path identifier:(id <NSObject>)identifier;
{
    CKConnectionOperation *operation = [[CKConnectionOperation alloc] initDirectoryListingOperationWithIdentifier:identifier
                                                                                                             path:path];
    [self enqueueOperation:operation];
    [operation release];
    
    return [operation identifier];
}

- (id)createDirectoryAtPath:(NSString *)path
withIntermediateDirectories:(BOOL)createIntermediates
                 identifier:(id <NSObject>)identifier;
{
    CKConnectionOperation *operation = [[CKConnectionOperation alloc] initCreateDirectoryOperationWithIdentifier:identifier
                                                                                                            path:path
                                                                                                       recursive:createIntermediates
                                                                                                   mainOperation:nil];
    [self enqueueOperation:operation];
    [operation release];
    
    return [operation identifier];
}

- (id)moveItemAtPath:(NSString *)sourcePath toPath:(NSString *)destinationPath identifier:(id <NSObject>)identifier;
{
    CKConnectionOperation *operation = [[CKConnectionOperation alloc] initMoveOperationWithIdentifier:identifier
                                                                                                 path:sourcePath
                                                                                      destinationPath:destinationPath];
    [self enqueueOperation:operation];
    [operation release];
    
    return [operation identifier];
}

- (id)setPermissions:(unsigned long)posixPermissions ofItemAtPath:(NSString *)path identifier:(id <NSObject>)identifier;
{
    CKConnectionOperation *operation = [[CKConnectionOperation alloc] initSetPermissionsOperationWithIdentifier:identifier
                                                                                                           path:path
                                                                                                    permissions:posixPermissions];
    [self enqueueOperation:operation];
    [operation release];
    
    return [operation identifier];
}

- (id)deleteItemAtPath:(NSString *)path identifier:(id <NSObject>)identifier;
{
    CKConnectionOperation *operation = [[CKConnectionOperation alloc] initDeleteOperationWithIdentifier:identifier
                                                                                                   path:path];
    [self enqueueOperation:operation];
    [operation release];
    
    return [operation identifier];
}

@end


#pragma mark -


@implementation CKConnection (Queue)

/*  Adds the operation to the queue or starts it immediately if nothing else is in progress
 */
- (void)enqueueOperation:(CKConnectionOperation *)operation
{
    [_queue addObject:operation];
    [self dequeueOperation];
}

/*  Starts the next operation if the connection is ready
 */
- (void)dequeueOperation
{
    if (!_currentOperation && _status == CKConnectionStatusOpen)
    {
        // Remove from the queue
        if ([_queue count] > 0)
        {
            _currentOperation = [[_queue objectAtIndex:0] retain];
            [_queue removeObjectAtIndex:0];
            
            // Inform delegate
            id delegate = [self delegate];
            if (delegate && [delegate respondsToSelector:@selector(connection:operationDidBegin:)])
            {
                [delegate connection:self operationDidBegin:[_currentOperation identifier]];
            }
            
            
            // Start protocol's operation implementation on worker thread
            CKConnectionProtocol *workerThreadProxy = [[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:[self protocol]];
            switch ([_currentOperation operationType])
            {
                case CKConnectionOperationUpload:
                    [workerThreadProxy uploadData:[_currentOperation data] toPath:[_currentOperation path]];
                    break;
                    
                case CKConnectionOperationDownload:
                    [workerThreadProxy downloadContentsOfFileAtPath:[_currentOperation path]];
                    break;
                    
                case CKConnectionOperationDirectoryListing:
                    [workerThreadProxy fetchContentsOfDirectoryAtPath:[_currentOperation path]];
                    break;
                    
                case CKConnectionOperationCreateDirectory:
                    [workerThreadProxy createDirectoryAtPath:[_currentOperation path]];
                    break;
                    
                case CKConnectionOperationMove:
                    [workerThreadProxy moveItemAtPath:[_currentOperation path] toPath:[_currentOperation destinationPath]];
                    break;
                    
                case CKConnectionOperationSetPermissions:
                    [workerThreadProxy setPermissions:[_currentOperation permissions] ofItemAtPath:[_currentOperation path]];
                    break;
                    
                case CKConnectionOperationDelete:
                    [workerThreadProxy deleteItemAtPath:[_currentOperation path]];
                    break;
                    
                default:
                    [NSException raise:NSInternalInconsistencyException format:@"Dequeueing unrecognised connection type"];
                    break;
            }
        }
    }
}

- (CKConnectionOperation *)currentOperation { return _currentOperation; }

- (void)currentOperationDidStop
{
    [_currentOperation release];
    _currentOperation = nil;
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
        [delegate connection:self operationDidFinish:[[self currentOperation] identifier]];
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
        // When performing a recursive operation, it could fail mid-way. If so, we MUST report the
        // error usuing the original operation identifier.
        CKConnectionOperation *operation = [self currentOperation];
        id <NSObject> operationID = ([operation mainOperation]) ? [[operation mainOperation] identifier] : [operation identifier];
        [delegate connection:self operation:operationID didFailWithError:error];
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
        [delegate connection:self download:[[self currentOperation] identifier] didReceiveData:data];
    }
}

- (void)protocolDidUploadDataOfLength:(NSUInteger)length
{
    // Inform the delegate. Gives it a chance to e.g. cancel the connection in response
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(connection:upload:didSendDataOfLength:)])
    {
        [delegate connection:self upload:[[self currentOperation] identifier] didSendDataOfLength:length];
    }
}

- (void)protocolDidFetchContentsOfDirectory:(NSArray *)contents
{
    
}

@end


#pragma mark -


@implementation CKConnection (WorkerThread)

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
    NSAssert2(protocol == [self protocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    
    [self performSelectorOnMainThread:@selector(protocolDidCancelAuthenticationChallenge:) withObject:challenge waitUntilDone:NO];
}

#pragma mark Operation

- (void)connectionProtocolDidFinishCurrentOperation:(CKConnectionProtocol *)protocol;
{
    NSAssert2(protocol == [self protocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    
    // For recursive directory creation that has successfully created a parent directory, proceed to
    // the next child directory
    CKConnectionOperation *operation = [self currentOperation];
    CKConnectionOperation *mainOperation = [operation mainOperation];
    BOOL reportSuccess = YES;
    
    if ([operation operationType] == CKConnectionOperationCreateDirectory &&
        [operation isRecursive] &&
        mainOperation)
    {
        NSString *finalPath = [mainOperation path];
        NSString *path = [operation path];
        if (![finalPath isEqualToString:path])
        {
            NSString *nextPath = [path stringByAppendingPathComponent:[[finalPath pathComponents] objectAtIndex:[[path pathComponents] count]]];
            
            _currentOperation = [[CKConnectionOperation alloc] initCreateDirectoryOperationWithIdentifier:[operation identifier]
                                                                                                     path:nextPath
                                                                                                recursive:NO
                                                                                            mainOperation:mainOperation];
            
            // tidy up
            [operation release];
            reportSuccess = NO;
            
            // Try the next operation
            [[self protocol] createDirectoryAtPath:nextPath];
        }
    }
    
    if (reportSuccess)
    {
        [self performSelectorOnMainThread:@selector(protocolCurrentOperationDidFinish) withObject:nil waitUntilDone:NO];
    }
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol currentOperationDidFailWithError:(NSError *)error;
{
    NSAssert2(protocol == [self protocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    
    // For recursive directory creation, try to create the parent directory rather than fail if possible.
    BOOL reportError = YES;
    
    CKConnectionOperation *operation = [self currentOperation];
    if ([operation operationType] == CKConnectionOperationCreateDirectory &&
        [operation isRecursive] &&
        [[error domain] isEqualToString:CKConnectionErrorDomain] &&
        [error code] == CKConnectionErrorFileDoesNotExist)
    {
        NSString *path = [[operation path] stringByDeletingLastPathComponent];
        if (![path isEqualToString:@"/"])
        {
            _currentOperation = [[CKConnectionOperation alloc]
                                 initCreateDirectoryOperationWithIdentifier:[operation identifier]
                                 path:path
                                 recursive:YES
                                 mainOperation:([operation mainOperation] ? [operation mainOperation] : operation)];
            
            // tidy up
            [operation release];
            reportError = NO;
            
            // Try the new operation
            [[self protocol] createDirectoryAtPath:path];
        }
    }
    
    if (reportError)
    {
        [self performSelectorOnMainThread:@selector(protocolCurrentOperationDidFailWithError:) withObject:error waitUntilDone:NO];
    }
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didDownloadData:(NSData *)data;
{
    NSAssert2(protocol == [self protocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    
    [self performSelectorOnMainThread:@selector(protocolDidDownloadData:) withObject:data waitUntilDone:NO];
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didUploadDataOfLength:(NSUInteger)length;
{
    NSAssert2(protocol == [self protocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    
    NSInvocation *invocation = [NSInvocation invocationWithTarget:self selector:@selector(protocolDidUploadDataOfLength:)];
    [invocation setArgument:&length atIndex:2];
    [invocation retainArguments];
    
    [self performSelectorOnMainThread:@selector(invoke) withObject:invocation waitUntilDone:NO];
}

- (void)connectionProtocol:(CKConnectionProtocol *)protocol didLoadContentsOfDirectory:(NSArray *)contents;
{
    NSAssert2(protocol == [self protocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    
    [self performSelectorOnMainThread:@selector(protocolDidFetchContentsOfDirectory:) withObject:contents waitUntilDone:NO];
}

#pragma mark Transcript

/*	Convenience method for sending a string to the delegate for appending to the transcript
 */
- (void)connectionProtocol:(CKConnectionProtocol *)protocol appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript
{
	NSAssert2(protocol == [self protocol], @"-[CKConnectionProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    
    NSInvocation *invocation = [NSInvocation invocationWithTarget:self selector:@selector(protocolAppendString:toTranscript:)];
    [invocation setArgument:&string atIndex:2];
    [invocation setArgument:&transcript atIndex:3];
    [invocation retainArguments];
    
    [self performSelectorOnMainThread:@selector(invoke) withObject:invocation waitUntilDone:NO];
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

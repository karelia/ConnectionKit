//
//  CKConnection.m
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <ConnectionKit/ConnectionKit.h>
#import "CKFileTransferConnection+Private.h"

#import "CKConnectionError.h"
#import "CKConnectionProtocol1.h"
#import "CKConnectionThreadManager.h"

#import "NSInvocation+ConnectionKit.h"


NSString *const CKConnectionErrorDomain = @"ConnectionErrorDomain";


@interface CKFileTransferConnection (QueueInternal)
- (void)enqueueOperation:(CKConnectionOperation *)operation;
- (void)dequeueOperation;
@end


#pragma mark -


@implementation CKFileTransferConnection

#pragma mark Init & Dealloc

+ (CKFileTransferConnection *)connectionWithRequest:(NSURLRequest *)request delegate:(id <CKFileTransferDelegate>)delegate
{
    return [[[self alloc] initWithRequest:request delegate:delegate] autorelease];
}

/*  Should return nil if no protocol can be found
 */
- (id)initWithRequest:(NSURLRequest *)request delegate:(id <CKFileTransferDelegate>)delegate
{
    [super init];
    
    Class protocolClass = [CKFileTransferProtocol classForRequest:request];
    if (protocolClass)
    {
        _request = [request copy];
        _delegate = delegate;
        _queue = [[NSMutableArray alloc] init];
        
        // Start connection
        _client = [[CKFileTransferProtocolClient alloc] initWithConnection:self];
        _protocol = [[protocolClass alloc] initWithRequest:[self request] client:_client];
        [(CKFileTransferProtocolClient *)_client setConnectionProtocol:_protocol];
        
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

#pragma mark Accessors

- (NSURLRequest *)request { return _request; }

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
    name = [name copy];
    [_name release];
    _name = name;
}

- (CKFileTransferProtocol *)protocol
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


@implementation CKFileTransferConnection (Private)

- (id)delegate { return _delegate; }

- (CKConnectionStatus)status { return _status; }

- (CKConnectionOperation *)currentOperation { return _currentOperation; }

- (void)setCurrentOperation:(CKConnectionOperation *)operation
{
    [operation retain];
    [_currentOperation release];
    _currentOperation = operation;
}

@end


#pragma mark -


@implementation CKFileTransferConnection (Queue)

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
            if ([delegate respondsToSelector:@selector(fileTransferConnection:operationDidBegin:)])
            {
                [delegate fileTransferConnection:self operationDidBegin:[_currentOperation identifier]];
            }
            
            
            // Start protocol's operation implementation on worker thread
            CKFileTransferProtocol *workerThreadProxy = [[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:[self protocol]];
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

- (void)currentOperationDidStop
{
    [_currentOperation release];
    _currentOperation = nil;
}

@end


#pragma mark -


@implementation CKFileTransferConnection (ProtocolClient)

/*  These methods are invoked in response to a message to the protocol client. They happen on the
 *  main thread and are responsible for:
 *      A) informing the delegate
 *      B) dispatching the next operation
 */

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didOpenConnectionWithCurrentDirectoryPath:(NSString *)path
{
    _status = CKConnectionStatusOpen;
    
    // We're ready to start processing
    [self dequeueOperation];
    
    // Inform the delegate
    id delegate = [self delegate];
    if ([delegate respondsToSelector:@selector(fileTransferConnection:didOpenWithCurrentDirectoryPath:)])
    {
        [delegate fileTransferConnection:self didOpenWithCurrentDirectoryPath:path];
    }
}

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didFailWithError:(NSError *)error;
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

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // Inform the delegate
    id delegate = [self delegate];
    if ([delegate respondsToSelector:@selector(connection:didReceiveAuthenticationChallenge:)])
    {
        [delegate performSelector:@selector(connection:didReceiveAuthenticationChallenge:)
                       withObject:self
                       withObject:challenge];
    }
}

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    
}

#pragma mark Operations

- (void)fileTransferProtocolDidFinishCurrentOperation:(CKFileTransferProtocol *)protocol;
{
    // Inform the delegate
    id delegate = [self delegate];
    [delegate fileTransferConnection:self operationDidFinish:[[self currentOperation] identifier]];
    
    
    // Move onto the next operation
    [self currentOperationDidStop];
    [self dequeueOperation];
}

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol currentOperationDidFailWithError:(NSError *)error;
{
    // Inform the delegate. Gives it a chance to e.g. cancel the connection in response
    // When performing a recursive operation, it could fail mid-way. If so, we must report the error usuing the ORIGINAL operation identifier.
    CKConnectionOperation *operation = [self currentOperation];
    id <NSObject> operationID = ([operation mainOperation]) ? [[operation mainOperation] identifier] : [operation identifier];
    [[self delegate] fileTransferConnection:self operation:operationID didFailWithError:error];
    
    
    [self currentOperationDidStop];
    [self dequeueOperation];
}

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didDownloadData:(NSData *)data;
{
    // Inform the delegate. Gives it a chance to e.g. cancel the connection in response
    id delegate = [self delegate];
    if ([delegate respondsToSelector:@selector(fileTransferConnection:download:didReceiveData:)])
    {
        [delegate fileTransferConnection:self download:[[self currentOperation] identifier] didReceiveData:data];
    }
}

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didUploadDataOfLength:(NSUInteger)length;
{
    // Inform the delegate. Gives it a chance to e.g. cancel the connection in response
    id delegate = [self delegate];
    if ([delegate respondsToSelector:@selector(fileTransferConnection:upload:didSendDataOfLength:)])
    {
        [delegate fileTransferConnection:self upload:[[self currentOperation] identifier] didSendDataOfLength:length];
    }
}

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol didLoadContentsOfDirectory:(NSArray *)contents;
{
    
}

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript
{
    id delegate = [self delegate];
    if ([delegate respondsToSelector:@selector(fileTransferConnection:appendString:toTranscript:)])
    {
        [delegate fileTransferConnection:self appendString:string toTranscript:transcript];
    }
}

- (void)fileTransferProtocol:(CKFileTransferProtocol *)protocol appendFormat:(NSString *)formatString toTranscript:(CKTranscriptType)transcript, ...
{   // This method should never actually be called!
}

@end



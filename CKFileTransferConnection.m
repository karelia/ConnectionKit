//
//  CKConnection.m
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

//#import <ConnectionKit/ConnectionKit.h>
#import "CKFileTransferConnection+Private.h"
#import "CKFileTransferDelegate.h"
#import "CK_FileTransferClient.h"
#import "CK_FileOperation.h"

#import "CKError.h"
#import "CKConnectionProtocol1.h"
#import "CKConnectionThreadManager.h"

#import "NSInvocation+ConnectionKit.h"


NSString *const CKErrorDomain = @"ConnectionErrorDomain";
NSString *const CKErrorURLResponseErrorKey = @"URLResponse";


@interface CKFileTransferConnection (QueueInternal)
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
    
    Class protocolClass = [CKFSProtocol classForRequest:request];
    if (protocolClass)
    {
        _request = [request copy];
        _delegate = delegate;
        
        
        // Setup the queue. It starts off suspended
        _queue = [[NSOperationQueue alloc] init];
        [_queue setMaxConcurrentOperationCount:1];
        [_queue setSuspended:YES];
        
        
        // Start connection
        _client = [[CK_FileTransferClient alloc] initWithConnection:self];
        _protocol = [[protocolClass alloc] initWithRequest:[self request] client:_client];
        [(CK_FileTransferClient *)_client setConnectionProtocol:_protocol];
        
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
    NSAssert([[_queue operations] count] == 0, @"Deallocating connection with items still on the queue");
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

- (CKFSProtocol *)protocol
{
    return _protocol;   // _protocol is an id to provide less of a hint to external code
}

#pragma mark Connection

- (void)cancel
{
    _delegate = nil;    // It'll stop receiving messages
}

- (id)enqueueRequest:(CKFileRequest *)request identifier:(id <NSObject>)identifier
{
    CK_FileOperation *operation = [[CK_FileOperation alloc] initWithIdentifier:identifier
                                                                       request:request
                                                                    connection:self];
    
    [_queue addOperation:operation];
    [operation release];
    
    return [operation identifier];
}
                                   
@end


#pragma mark -


@implementation CKFileTransferConnection (Private)

- (id)delegate { return _delegate; }

- (CKConnectionStatus)status { return _status; }

- (CK_FileOperation *)currentOperation { return _currentOperation; }

// Called by a CK_FileOperation as the operation queue fires it off. We must act upon it to set the protocol to work
- (void)CK_operationDidBegin:(CK_FileOperation *)operation;
{
    // Store the operation
    NSAssert(![self currentOperation], @"Trying to start operation while another is active");
    _currentOperation = [operation retain];
    
    // Start operation
    CKFSProtocol *workerThreadProxy = [[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:[self protocol]];
    [workerThreadProxy startCurrentOperationWithRequest:[operation request]];
}

- (void)CK_currentOperationDidEnd:(BOOL)success error:(NSError *)error
{
    // We're done, reset operation storage
    CK_FileOperation *operation = [self currentOperation];
    [operation operationDidFinish];
    _currentOperation = nil;    // it's released at the end of this method
    
    // Inform the delegate
    id delegate = [self delegate];
    if (success)
    {
        [delegate fileTransferConnection:self
                      operationDidFinish:[operation identifier]];
    }
    else
    {
        // When performing a recursive operation, it could fail mid-way. If so, we must report the error usuing the ORIGINAL operation identifier.
        [[self delegate] fileTransferConnection:self
                                      operation:[operation identifier]
                               didFailWithError:error];
    }
    
    // Tidy up
    [operation release];
}

@end


#pragma mark -


@implementation CKFileTransferConnection (ProtocolClient)

/*  These methods are invoked in response to a message to the protocol client. They happen on the
 *  main thread and are responsible for:
 *      A) informing the delegate
 *      B) dispatching the next operation
 */

- (void)FSProtocol:(CKFSProtocol *)protocol didOpenConnectionWithCurrentDirectoryPath:(NSString *)path
{
    _status = CKConnectionStatusOpen;
    
    // Inform the delegate
    id delegate = [self delegate];
    if ([delegate respondsToSelector:@selector(fileTransferConnection:didOpenWithCurrentDirectoryPath:)])
    {
        [delegate fileTransferConnection:self didOpenWithCurrentDirectoryPath:path];
    }
    
    // We're ready to start processing
    [_queue setSuspended:NO];
}

- (void)FSProtocol:(CKFSProtocol *)protocol didFailWithError:(NSError *)error;
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

- (void)FSProtocol:(CKFSProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // Inform the delegate
    id delegate = [self delegate];
    if ([delegate respondsToSelector:@selector(fileTransferConnection:didReceiveAuthenticationChallenge:)])
    {
        [delegate fileTransferConnection:self didReceiveAuthenticationChallenge:challenge];
    }
}

#pragma mark Operations

- (void)FSProtocolDidFinishCurrentOperation:(CKFSProtocol *)protocol;
{
    [self CK_currentOperationDidEnd:YES error:nil];
}

- (void)FSProtocol:(CKFSProtocol *)protocol currentOperationDidFailWithError:(NSError *)error;
{
    [self CK_currentOperationDidEnd:NO error:error];
}

- (void)FSProtocol:(CKFSProtocol *)protocol didDownloadData:(NSData *)data;
{
    // Inform the delegate. Gives it a chance to e.g. cancel the connection in response
    id delegate = [self delegate];
    if ([delegate respondsToSelector:@selector(fileTransferConnection:download:didReceiveData:)])
    {
        [delegate fileTransferConnection:self download:[[self currentOperation] identifier] didReceiveData:data];
    }
}

- (void)FSProtocol:(CKFSProtocol *)protocol didUploadDataOfLength:(NSUInteger)length;
{
    // Inform the delegate. Gives it a chance to e.g. cancel the connection in response
    id delegate = [self delegate];
    if ([delegate respondsToSelector:@selector(fileTransferConnection:upload:didSendDataOfLength:)])
    {
        [delegate fileTransferConnection:self upload:[[self currentOperation] identifier] didSendDataOfLength:length];
    }
}

- (void)FSProtocol:(CKFSProtocol *)protocol
        didReceiveProperties:(CKFileInfo *)fileInfo
                ofItemAtPath:(NSString *)path;
{
    
}

- (void)FSProtocol:(CKFSProtocol *)protocol appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript
{
    id delegate = [self delegate];
    if ([delegate respondsToSelector:@selector(fileTransferConnection:appendString:toTranscript:)])
    {
        [delegate fileTransferConnection:self appendString:string toTranscript:transcript];
    }
}

- (void)FSProtocol:(CKFSProtocol *)protocol appendFormat:(NSString *)formatString toTranscript:(CKTranscriptType)transcript, ...
{   // This method should never actually be called!
}

@end


#pragma mark -


@implementation CKFileTransferConnection (SimpleOperations)

- (id)downloadContentsOfPath:(NSString *)path identifier:(id <NSObject>)identifier
{
    CKFileRequest *request = [[CKFileRequest alloc] initWithOperationType:CKOperationTypeDownload
                                                                     path:path];
    
    id result = [self enqueueRequest:request identifier:identifier];
    [request release];
    return result;
}

- (id)uploadData:(NSData *)data toPath:(NSString *)path identifier:(id <NSObject>)identifier
{
    CKMutableFileRequest *request = [[CKMutableFileRequest alloc] initWithOperationType:CKOperationTypeUpload
                                                                                   path:path];
    [request setData:data fileType:nil];
    
    id result = [self enqueueRequest:request identifier:identifier];
    [request release];
    return result;
}

- (id)fetchContentsOfDirectoryAtPath:(NSString *)path identifier:(id <NSObject>)identifier;
{
    CKFileRequest *request = [[CKFileRequest alloc] initWithOperationType:CKOperationTypeDirectoryContents
                                                                     path:path];
    
    id result = [self enqueueRequest:request identifier:identifier];
    [request release];
    return result;
}

- (id)createDirectoryAtPath:(NSString *)path
withIntermediateDirectories:(BOOL)createIntermediates
                 identifier:(id <NSObject>)identifier;
{
    CKMutableFileRequest *request = [[CKMutableFileRequest alloc] initWithOperationType:CKOperationTypeCreateDirectory
                                                                                   path:path];
    [request setCreateIntermediateDirectories:createIntermediates];
    
    id result = [self enqueueRequest:request identifier:identifier];
    [request release];
    return result;
}

- (id)removeItemAtPath:(NSString *)path identifier:(id <NSObject>)identifier;
{
    CKFileRequest *request = [[CKFileRequest alloc] initWithOperationType:CKOperationTypeRemove
                                                                     path:path];
    
    id result = [self enqueueRequest:request identifier:identifier];
    [request release];
    return result;
}

@end

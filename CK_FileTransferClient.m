//
//  CK_FileTransferClient.m
//  ConnectionKit
//
//  Created by Mike on 15/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CK_FileTransferClient.h"

#import "CKConnectionAuthentication.h"
#import "CKThreadProxy.h"


@implementation CK_FileTransferClient

#pragma mark Init & Dealloc

- (id)initWithConnection:(CKFileTransferConnection *)connection
{
    [super init];
        
    _connectionThreadProxy = [CKThreadProxy CK_proxyWithTarget:connection
                                                        thread:[NSThread currentThread]];
    [_connectionThreadProxy retain];
    
    return self;
}

- (void)startWithRequest:(NSURLRequest *)request;
{
    NSAssert1(!_protocol, @"%@ already has a protocol associated with it", self);
    _protocol = [[[CKFSProtocol classForRequest:request] alloc] initWithRequest:request client:self];
    [_protocol startConnection];
}

- (void)dealloc
{
    [_connectionThreadProxy release];
    [super dealloc];
}

#pragma mark Accessors

- (CKFSProtocol *)protocol { return _protocol; }

- (CKFileTransferConnection *)connectionThreadProxy { return _connectionThreadProxy; }

#pragma mark Overall connection

/*  Sending a message directly from the worker thread to the delegate is a bad idea as it is
 *  possible the connection may have been cancelled by the time the message is delivered. Instead,
 *  deliver messages to ourself on the main thread and then forward them on to the delegate if
 *  appropriate.
 */

- (void)FSProtocol:(CKFSProtocol *)protocol didOpenConnectionWithCurrentDirectoryPath:(NSString *)path
{
	NSAssert2(protocol == [self protocol], @"-[CKFileTransferProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    NSAssert([[self connectionThreadProxy] status] == CKConnectionStatusOpening, @"The connection is not ready to be opened");  // This should never be called twice
    
    [[self connectionThreadProxy] FSProtocol:protocol didOpenConnectionWithCurrentDirectoryPath:path];
}

- (void)FSProtocol:(CKFSProtocol *)protocol didFailWithError:(NSError *)error;
{
	NSAssert2(protocol == [self protocol], @"-[CKFileTransferProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    [[self connectionThreadProxy] FSProtocol:protocol didFailWithError:error];
}

#pragma mark Authorization

/*  Support method for filling an NSURLAuthenticationChallenge object. If no credential was supplied,
 *  looks for one from the connection's URL, and then falls back to using NSURLCredentialStorage.
 */
- (NSURLAuthenticationChallenge *)CK_fullAuthenticationChallengeForChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSURLAuthenticationChallenge *result = challenge;
    
    NSURLCredential *credential = [challenge proposedCredential];
    if (!credential)
    {
        NSURL *connectionURL = [[[self connectionThreadProxy] request] URL];
        
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

- (void)FSProtocol:(CKFSProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
	NSAssert2(protocol == [self protocol], @"-[CKFileTransferProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    NSAssert([[self connectionThreadProxy] status] > CKConnectionStatusNotOpen, @"The connection has not started yet");  // Should only happen while running
    
    
    // Fill in missing credentials if possible
    NSURLAuthenticationChallenge *fullChallenge = challenge;
    if (![challenge proposedCredential])
    {
        fullChallenge = [self CK_fullAuthenticationChallengeForChallenge:challenge];
    }
    
    
    // Does the delegate support this? If not, handle it ourselves
    id delegate = [[self connectionThreadProxy] delegate];
    if ([delegate respondsToSelector:@selector(connection:didReceiveAuthenticationChallenge:)])
    {
        // Set up a proxy -sender object to forward the request to the main thread
        [[self connectionThreadProxy] FSProtocol:protocol
                         didReceiveAuthenticationChallenge:fullChallenge];
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

#pragma mark Operation

- (void)FSProtocolDidFinishCurrentOperation:(CKFSProtocol *)protocol;
{
    NSAssert2(protocol == [self protocol], @"-[CKFileTransferProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    
    [[self connectionThreadProxy] FSProtocolDidFinishCurrentOperation:protocol];
}

- (void)FSProtocol:(CKFSProtocol *)protocol currentOperationDidFailWithError:(NSError *)error;
{
    NSAssert2(protocol == [self protocol], @"-[CKFileTransferProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    
    [[self connectionThreadProxy] FSProtocol:protocol currentOperationDidFailWithError:error];
}

- (void)FSProtocol:(CKFSProtocol *)protocol didDownloadData:(NSData *)data;
{
    NSAssert2(protocol == [self protocol], @"-[CKFileTransferProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    [[self connectionThreadProxy] FSProtocol:protocol didDownloadData:data];
}

- (void)FSProtocol:(CKFSProtocol *)protocol didUploadDataOfLength:(NSUInteger)length;
{
    NSAssert2(protocol == [self protocol], @"-[CKFileTransferProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    [[self connectionThreadProxy] FSProtocol:protocol didUploadDataOfLength:length];
}

- (void)FSProtocol:(CKFSProtocol *)protocol
        didReceiveProperties:(CKFileInfo *)fileInfo
                ofItemAtPath:(NSString *)path;
{
    NSAssert2(protocol == [self protocol], @"-[CKFileTransferProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    [[self connectionThreadProxy] FSProtocol:protocol didReceiveProperties:fileInfo ofItemAtPath:path];
}

#pragma mark Transcript

/*	Convenience method for sending a string to the delegate for appending to the transcript
 */
- (void)FSProtocol:(CKFSProtocol *)protocol appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript
{
	NSAssert2(protocol == [self protocol], @"-[CKFileTransferProtocolClient %@] message received from unknown protocol: %@", NSStringFromSelector(_cmd), protocol);
    
    [[self connectionThreadProxy] FSProtocol:protocol appendString:string toTranscript:transcript];
}

- (void)FSProtocol:(CKFSProtocol *)protocol appendFormat:(NSString *)formatString toTranscript:(CKTranscriptType)transcript, ...
{
	va_list arguments;
	va_start(arguments, transcript);
	NSString *string = [[NSString alloc] initWithFormat:formatString arguments:arguments];
	va_end(arguments);
	
	[self FSProtocol:protocol appendString:string toTranscript:transcript];
	[string release];
}

@end


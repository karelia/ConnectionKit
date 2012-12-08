//
//  CK2CURLBasedProtocol.m
//  Connection
//
//  Created by Mike on 06/12/2012.
//
//

#import "CK2CURLBasedProtocol.h"

@implementation CK2CURLBasedProtocol

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client completionHandler:(void (^)(NSError *))handler;
{
    if (self = [self initWithRequest:request client:client])
    {
        _completionHandler = [handler copy];
    }
    
    return self;
}

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client dataHandler:(void (^)(NSData *))dataBlock completionHandler:(void (^)(NSError *))handler
{
    if (self = [self initWithRequest:request client:client completionHandler:handler])
    {
        _dataBlock = [dataBlock copy];
    }
    return self;
}

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock completionHandler:(void (^)(NSError *))handler
{
    if (self = [self initWithRequest:request client:client completionHandler:handler])
    {
        _progressBlock = [progressBlock copy];
    }
    return self;
}

- (void)dealloc;
{
    [_handle release];
    [_completionHandler release];
    [_dataBlock release];
    [_progressBlock release];
    
    [super dealloc];
}

#pragma mark Loading

- (void)start; { return [self startWithCredential:nil]; }

- (void)startWithCredential:(NSURLCredential *)credential;
{
    _handle = [[CURLHandle alloc] initWithRequest:[self request]
                                       credential:credential
                                         delegate:self];
}

- (void)endWithError:(NSError *)error;
{
    _completionHandler(error);
    [_handle release]; _handle = nil;
}

- (void)stop;
{
    [_handle cancel];
}

#pragma mark CURLHandleDelegate

- (void)handle:(CURLHandle *)handle didFailWithError:(NSError *)error;
{
    if (!error) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil];
    [self endWithError:error];
}

- (void)handle:(CURLHandle *)handle didReceiveData:(NSData *)data;
{
    if (_dataBlock) _dataBlock(data);
}

- (void)handle:(CURLHandle *)handle willSendBodyDataOfLength:(NSUInteger)bytesWritten
{
    if (_progressBlock) _progressBlock(bytesWritten);
}

- (void)handleDidFinish:(CURLHandle *)handle;
{
    [self endWithError:nil];
}

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type;
{
    [[self client] protocol:self appendString:string toTranscript:(type == CURLINFO_HEADER_IN ? CKTranscriptReceived : CKTranscriptSent)];
}

@end

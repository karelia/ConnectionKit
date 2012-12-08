//
//  CK2CURLBasedProtocol.m
//  Connection
//
//  Created by Mike on 06/12/2012.
//
//

#import "CK2CURLBasedProtocol.h"

#import <CurlHandle/NSURLRequest+CURLHandle.h>


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

- (id)initWithCustomCommands:(NSArray *)commands request:(NSURLRequest *)childRequest createIntermediateDirectories:(BOOL)createIntermediates client:(id <CK2ProtocolClient>)client completionHandler:(void (^)(NSError *error))handler;
{
    // Navigate to the directory
    // @"HEAD" => CURLOPT_NOBODY, which stops libcurl from trying to list the directory's contents
    // If the connection is already at that directory then curl wisely does nothing
    NSMutableURLRequest *request = [childRequest mutableCopy];
    [request setURL:[[childRequest URL] URLByDeletingLastPathComponent]];
    [request setHTTPMethod:@"HEAD"];
    [request curl_setCreateIntermediateDirectories:createIntermediates];
    
    // Custom commands once we're in the correct directory
    // CURLOPT_PREQUOTE does much the same thing, but sometimes runs the command twice in my testing
    [request curl_setPostTransferCommands:commands];
    
    self = [self initWithRequest:request client:client dataHandler:nil completionHandler:^(NSError *error) {
        
        if (handler)
        {
            handler(error);
        }
        else
        {
            if (error)
            {
                [client protocol:self didFailWithError:error];
            }
            else
            {
                [client protocolDidFinish:self];
            }
        }
    }];
    
    [request release];
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

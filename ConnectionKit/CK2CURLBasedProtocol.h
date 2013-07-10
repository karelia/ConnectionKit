//
//  CK2CURLBasedProtocol.h
//  Connection
//
//  Created by Mike on 06/12/2012.
//
//

#import "CK2Protocol.h"

#import <CURLHandle/CURLTransfer.h>


@class CK2RemoteURL;

@interface CK2CURLBasedProtocol : CK2Protocol <CURLTransferDelegate, NSURLAuthenticationChallengeSender>
{
    CURLTransfer    *_transfer;
    NSString        *_user;
    
    void    (^_completionHandler)(NSError *error);
    void    (^_dataBlock)(NSData *data);
    CK2ProgressBlock _progressBlock;
    
    NSUInteger _totalBytesWritten;
}

#pragma mark Initialisation
// In any of these methods, if completion handler is nil, the standard behaviour of reporting to the client will be performed

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client completionHandler:(void (^)(NSError *))handler;
- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client dataHandler:(void (^)(NSData *))dataBlock completionHandler:(void (^)(NSError *))handler;
- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *))handler;

- (id)initWithCustomCommands:(NSArray *)commands request:(NSURLRequest *)request createIntermediateDirectories:(BOOL)createIntermediates client:(id <CK2ProtocolClient>)client completionHandler:(void (^)(NSError *error))handler;

// Already handled for you; can override in a subclass if you want
- (id)initForEnumeratingDirectoryWithRequest:(NSURLRequest *)request includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask client:(id<CK2ProtocolClient>)client;


#pragma mark Loading

// If the protocol requires authentication, override -start to fire off an authentication challenge to the client. When a response is received to the challenge, CK2CURLBasedProtocol automatically handles it to start up the handle/request
- (void)start;


#pragma mark Customization
+ (BOOL)usesMultiHandle;    // defaults to YES. Subclasses can override to be NO and fall back to the old synchronous "easy" backend
- (void)popCompletionHandlerByExecutingWithError:(NSError *)error;
- (void)reportToProtocolWithError:(NSError*)error;

@end

//
//  CK2CURLBasedProtocol.h
//  Connection
//
//  Created by Mike on 06/12/2012.
//
//

#import "CK2Protocol.h"

#import <CURLHandle/CURLHandle.h>


@interface CK2CURLBasedProtocol : CK2Protocol <CURLHandleDelegate>
{
    CURLHandle  *_handle;
    
    void    (^_completionHandler)(NSError *error);
    void    (^_dataBlock)(NSData *data);
    void    (^_progressBlock)(NSUInteger bytesWritten);
}

#pragma mark Initialisation
- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client completionHandler:(void (^)(NSError *))handler;
- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client dataHandler:(void (^)(NSData *))dataBlock completionHandler:(void (^)(NSError *))handler;
- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock completionHandler:(void (^)(NSError *))handler;


#pragma mark Loading
- (void)start;                                              // creates and starts the CURLHandle with no credential
- (void)startWithCredential:(NSURLCredential *)credential;  // creates and starts the CURLHandle with supplied credential

@end

//
//  CK2FTPProtocol.h
//  Connection
//
//  Created by Mike on 12/10/2012.
//
//

#import "CK2Protocol.h"

#import <CURLHandle/CURLHandle.h>


@interface CK2FTPProtocol : CK2Protocol <CURLHandleDelegate, NSURLAuthenticationChallengeSender>
{
  @private
    NSURLRequest    *_request;
    id <CK2ProtocolClient>  _client;
    
    CURLHandle  *_handle;
    
    void    (^_completionHandler)(NSError *error);
    void    (^_dataBlock)(NSData *data);
    void    (^_progressBlock)(NSUInteger bytesWritten);
}

@end



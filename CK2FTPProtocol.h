//
//  CK2FTPProtocol.h
//  Connection
//
//  Created by Mike on 12/10/2012.
//
//

#import "CK2FileTransferProtocol.h"

#import <CURLHandle/CURLHandle.h>


@interface CK2FTPProtocol : CK2FileTransferProtocol <CURLHandleDelegate, NSURLAuthenticationChallengeSender>
{
  @private
    NSURLRequest    *_request;
    
    id <CK2FileTransferProtocolClient>  _client;
    
    void    (^_completionHandler)(CURLHandle *handle, NSError *error);
    void    (^_dataBlock)(NSData *data);
    void    (^_progressBlock)(NSUInteger bytesWritten);
}

@end



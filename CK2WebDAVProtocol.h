//
//  CK2WebDAVProtocol.h
//
//  Created by Sam Deane on 19/11/2012.
//
//

#import "CK2Protocol.h"
#import <DAVKit/DAVKit.h>

@interface CK2WebDAVProtocol : CK2Protocol<DAVPutRequestDelegate, DAVSessionDelegate>
{
@private
    DAVSession* _session;
    DAVRequest* _davRequest;

    void    (^_completionHandler)(id result);
    void    (^_dataBlock)(NSData *data);
    void    (^_progressBlock)(NSUInteger bytesWritten);
}

@end

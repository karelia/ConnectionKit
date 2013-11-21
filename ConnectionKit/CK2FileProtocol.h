//
//  CK2FileProtocol.h
//  Connection
//
//  Created by Mike on 18/10/2012.
//
//

#import "CK2Protocol.h"

@interface CK2FileProtocol : CK2Protocol
{
  @private
    void    (^_block)(void);
    BOOL    _cancelled;
    dispatch_queue_t _queue;
    
    int64_t _bytesExpectedToWrite;
}

@end

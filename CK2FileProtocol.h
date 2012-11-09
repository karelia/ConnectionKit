//
//  CK2FileProtocol.h
//  Connection
//
//  Created by Mike on 18/10/2012.
//
//

#import "CK2FileTransferProtocol.h"

@interface CK2FileProtocol : CK2FileTransferProtocol
{
  @private
    void    (^_block)(void);
}

@end

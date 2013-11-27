//
//  CK2FTPProtocol.h
//  Connection
//
//  Created by Mike on 12/10/2012.
//
//

#import "CK2CURLBasedProtocol.h"


@interface CK2FTPProtocol : CK2CURLBasedProtocol
{
  @private
    BOOL    _atEnd;
    
    // SSL
    NSURLCredential *_credential;
    NSUInteger      _sslFailures;
}

@end



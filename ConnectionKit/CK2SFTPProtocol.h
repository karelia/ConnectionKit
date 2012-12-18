//
//  CK2SFTPProtocol.h
//  Connection
//
//  Created by Mike on 15/10/2012.
//
//

#import "CK2CURLBasedProtocol.h"

@interface CK2SFTPProtocol : CK2CURLBasedProtocol
{
  @private
    NSURLCredential *_hostFingerprintCredential;
    BOOL            _haveHostFingerprintCredential;
}
@end

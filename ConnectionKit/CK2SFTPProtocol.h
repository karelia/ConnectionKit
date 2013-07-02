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
    NSURLAuthenticationChallenge    *_fingerprintChallenge;
    enum curl_khstat                _knownHostsStat;
    dispatch_semaphore_t            _fingerprintSemaphore;
    
    NSString    *_transcriptMessage;
}
@end

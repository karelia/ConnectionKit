//
//  CKConnectionAuthentication+Internal.h
//  Connection
//
//  Created by Mike on 24/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//


#import "CKConnectionAuthentication.h"


/*  Simple object that forwards an authentication response from the main thread to the original
 *  protocol object's worker thread.
 */

@interface CKAuthenticationChallengeSender : NSObject <NSURLAuthenticationChallengeSender>
{
    NSURLAuthenticationChallenge    *_authenticationChallenge;
}

- (id)initWithAuthenticationChallenge:(NSURLAuthenticationChallenge *)originalChallenge;
- (NSURLAuthenticationChallenge *)authenticationChallenge;

@end



@interface CKURLProtectionSpace : NSURLProtectionSpace
{
    NSString    *_protocol;
}
@end

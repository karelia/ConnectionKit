//
//  CKAuthenticationChallengeSender.h
//  Marvel
//
//  Created by Mike on 20/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


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

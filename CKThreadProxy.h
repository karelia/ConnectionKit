//
//  CKThreadProxy.h
//  Connection
//
//  Created by Mike on 17/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@class CKConnectionProtocol;


// Provides a simple way to message another thread. Has a couple of ConnectionKit-specific tricks up its sleave; see inside for details
@interface CKThreadProxy : NSProxy
{
  @private
    NSThread    *_thread;
    id          _target;
}

// Class method to reduce risk of method selector collision. Can pass in nil thread as a convenience to refer to the main thread.
+ (id)CK_proxyWithTarget:(id <NSObject>)target thread:(NSThread *)thread;

// In addition to forwarding the message onto the main thread, the proxy guarantees the reply will be returned on the thread that sent the challenge.
- (void)connectionProtocol:(CKConnectionProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

@end
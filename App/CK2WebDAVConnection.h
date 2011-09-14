//
//  CK2WebDAVConnection.h
//  Sandvox
//
//  Created by Mike on 14/09/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import <Connection/Connection.h>

@class DAVSession;
@protocol DAVRequestDelegate;

@interface CK2WebDAVConnection : NSObject <CKConnection, DAVRequestDelegate, NSURLAuthenticationChallengeSender>
{
  @private
    NSURL       *_URL;
    NSURLAuthenticationChallenge    *_challenge;
    DAVSession  *_session;
    
    NSObject    *_delegate;
}

@property(nonatomic, assign) NSObject *delegate;

@end

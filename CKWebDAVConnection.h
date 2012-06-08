//
//  CKWebDAVConnection.h
//  Sandvox
//
//  Created by Mike on 14/09/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import <Connection/Connection.h>
#import <DAVKit/DAVKit.h>


@class DAVSession;

@interface CKWebDAVConnection : NSObject <CKPublishingConnection, DAVPutRequestDelegate, DAVSessionDelegate>
{
  @private
    BOOL                            _connected;
    NSURLAuthenticationChallenge    *_challenge;
    DAVSession                      *_session;
    
    NSMapTable                      *_transferRecordsByRequest;
    NSMutableArray                  *_queue;
    NSString                        *_currentDirectory;
    
    NSObject    *_delegate;
}

@property(nonatomic, copy) NSString *currentDirectory;

@end

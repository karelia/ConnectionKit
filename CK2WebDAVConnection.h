//
//  CK2WebDAVConnection.h
//  Sandvox
//
//  Created by Mike on 14/09/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import <Connection/Connection.h>
#import <DAVKit/DAVKit.h>


@class DAVSession;

@interface CK2WebDAVConnection : NSObject <CKConnection, DAVPutRequestDelegate, DAVSessionDelegate>
{
  @private
    BOOL                            _connected;
    NSURLAuthenticationChallenge    *_challenge;
    DAVSession                      *_session;
    
    NSMutableDictionary             *_transferRecordsByRequest;
    NSMutableArray                  *_queue;
    NSString                        *_currentDirectory;
    
    NSObject    *_delegate;
}

@property(nonatomic, assign) NSObject *delegate;
@property(nonatomic, copy) NSString *currentDirectory;

+ (BOOL)getDotMacAccountName:(NSString **)account password:(NSString **)password;

@end

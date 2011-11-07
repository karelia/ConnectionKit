//
//  CKSFTPConnection.h
//  Sandvox
//
//  Created by Mike on 25/10/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import <Connection/Connection.h>


@class CK2SFTPSession;


@interface CKSFTPConnection : NSObject <CKPublishingConnection>
{
 @private
    CK2SFTPSession      *_session;
    NSURL               *_url;
    NSOperationQueue    *_queue;
    NSString            *_currentDirectory;
    
    NSObject            *_delegate;
}

@property(nonatomic, copy) NSString *currentDirectory;

@end

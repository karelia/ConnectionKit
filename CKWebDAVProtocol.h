//
//  CKWebDAVProtocol.h
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKConnectionProtocol.h"


typedef enum {
    CKWebDAVProtocolStatusIdle,
    CKWebDAVProtocolStatusDownload,
    CKWebDAVProtocolStatusUploading,
    CKWebDAVProtocolStatusListingDirectory,
    CKWebDAVProtocolStatusCreatingDirectory,
    CKWebDAVProtocolStatusMovingItem,
    CKWebDAVProtocolStatusSettingPermissions,
    CKWebDAVProtocolStatusDeletingItem,
} CKWebDAVProtocolStatus;


@interface CKWebDAVProtocol : CKConnectionProtocol <NSURLAuthenticationChallengeSender>
{
@private
    CKWebDAVProtocolStatus  _status;
    
    // These ivars pertain to the current in-progress operation.
    // They are reset after the op finishes
    CFHTTPMessageRef                _HTTPRequest;
    CFReadStreamRef                 _HTTPStream;
    BOOL                            _hasProcessedHTTPResponse;
    
    CFHTTPAuthenticationRef         _authenticationRef;
    NSURLAuthenticationChallenge    *_authenticationChallenge;
}

@end

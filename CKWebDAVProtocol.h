//
//  CKWebDAVProtocol.h
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFileTransferProtocol.h"

#import "CKHTTPConnection.h"


typedef enum {
    CKWebDAVProtocolStatusNotOpen,
    CKWebDAVProtocolStatusOpening,
    CKWebDAVProtocolStatusIdle,
    CKWebDAVProtocolStatusDownload,
    CKWebDAVProtocolStatusUploading,
    CKWebDAVProtocolStatusListingDirectory,
    CKWebDAVProtocolStatusCreatingDirectory,
    CKWebDAVProtocolStatusMovingItem,
    CKWebDAVProtocolStatusSettingPermissions,
    CKWebDAVProtocolStatusDeletingItem,
} CKWebDAVProtocolStatus;


@interface CKWebDAVProtocol : CKFileTransferProtocol <CKHTTPConnectionDelegate>
{
@private
    CKWebDAVProtocolStatus  _status;
    
    // These ivars pertain to the current in-progress operation.
    // They are reset after the op finishes
    CKHTTPConnection    *_HTTPConnection;
}

@end

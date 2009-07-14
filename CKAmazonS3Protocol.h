//
//  CKAmazonS3Protocol.h
//  ConnectionKit
//
//  Created by Mike on 25/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKHTTPBasedProtocol.h"
#import "CKAmazonS3RESTOperation.h"


@interface CKAmazonS3Protocol : CKHTTPBasedProtocol <CKAmazonS3RESTOperationDelegate>
{
    NSURLCredential *_credential;
    
    CKAmazonS3RESTOperation *_currentOperation;
}

@end

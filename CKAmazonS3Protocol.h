//
//  CKAmazonS3Protocol.h
//  ConnectionKit
//
//  Created by Mike on 25/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKHTTPBasedProtocol.h"
#import "CK_AmazonS3RESTOperation.h"


@interface CKAmazonS3Protocol : CKHTTPBasedProtocol <CK_AmazonS3RESTOperationDelegate>
{
    NSURLCredential *_credential;
    
    CK_AmazonS3RESTOperation *_currentOperation;
}

@end

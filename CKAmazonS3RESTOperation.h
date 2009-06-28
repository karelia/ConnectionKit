//
//  CKAmazonS3HTTPConnection.h
//  ConnectionKit
//
//  Created by Mike on 28/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//


//  Handles the common logic of an S3 REST operation. Spec, terminology, etc. from http://docs.amazonwebservices.com/AmazonS3/2006-03-01/


#import <Foundation/Foundation.h>

#import "CKHTTPConnection.h"


@protocol CKAmazonS3RESTOperationDelegate;
@interface CKAmazonS3RESTOperation : NSOperation
{
  @private
    NSMutableURLRequest                     *_request;
    NSURLCredential                         *_credential;
    id <CKAmazonS3RESTOperationDelegate>    _delegate;  // weak ref
    
    CKHTTPConnection    *_connection;
    
    BOOL    _isFinished;
    BOOL    _isExecuting;
}

- (id)initWithRequest:(NSURLRequest *)request
           credential:(NSURLCredential *)credential
             delegate:(id <CKAmazonS3RESTOperationDelegate>)delegate;

@end


@protocol CKAmazonS3RESTOperationDelegate

- (void)amazonS3Operation:(CKAmazonS3RESTOperation *)operation
       didReceiveResponse:(NSHTTPURLResponse *)response;

- (void)amazonS3Operation:(CKAmazonS3RESTOperation *)operation
           didReceiveData:(NSData *)data;

- (void)amazonS3OperationDidFinishLoading:(CKAmazonS3RESTOperation *)operation;

- (void)amazonS3Operation:(CKAmazonS3RESTOperation *)operation
         didFailWithError:(NSError *)error;

@end

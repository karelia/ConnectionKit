//
//  CKAmazonS3HTTPConnection.h
//  ConnectionKit
//
//  Created by Mike on 28/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//


//  Handles the common logic of an S3 REST operation. Spec, terminology, etc. from http://docs.amazonwebservices.com/AmazonS3/2006-03-01/


#import "CK_AsyncOperation.h"


extern NSString * const CKAmazonErrorCodeKey;


@protocol CK_AmazonS3RESTOperationDelegate;
@interface CK_AmazonS3RESTOperation : CK_AsyncOperation
{
  @private
    NSMutableURLRequest                     *_request;
    NSURLCredential                         *_credential;
    id <CK_AmazonS3RESTOperationDelegate>    _delegate;  // weak ref
    
    NSURLConnection *_connection;
}

- (id)initWithRequest:(NSURLRequest *)request
           credential:(NSURLCredential *)credential
             delegate:(id <CK_AmazonS3RESTOperationDelegate>)delegate;

@end


@protocol CK_AmazonS3RESTOperationDelegate

- (void)amazonS3Operation:(CK_AmazonS3RESTOperation *)operation
       didReceiveResponse:(NSHTTPURLResponse *)response;

- (void)amazonS3Operation:(CK_AmazonS3RESTOperation *)operation
           didReceiveData:(NSData *)data;

- (void)amazonS3OperationDidFinishLoading:(CK_AmazonS3RESTOperation *)operation;

- (void)amazonS3Operation:(CK_AmazonS3RESTOperation *)operation
         didFailWithError:(NSError *)error;

@end

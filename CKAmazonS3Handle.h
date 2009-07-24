//
//  CKAmazonS3Handle.h
//  S3MacFUSE
//
//  Created by Mike on 23/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface CKAmazonS3Handle : NSObject
{
    NSMutableURLRequest *_request;
    NSURLCredential     *_credential;
    
    NSInputStream   *_stream;
    BOOL            _haveProcessedResponse;
    off_t           _expectedOffset;
}

- (id)initWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential;

- (int)read:(uint8_t *)buffer size:(size_t)size offset:(off_t)offset error:(NSError **)outError;
- (int)read:(uint8_t *)buffer size:(size_t)size error:(NSError **)outError;
- (NSData *)readDataToEndOfFile:(NSError **)error;

- (NSHTTPURLResponse *)response;

- (void)close;

@end

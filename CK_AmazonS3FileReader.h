//
//  CK_AmazonS3Stream.h
//  S3MacFUSE
//
//  Created by Mike on 23/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface CK_AmazonS3FileReader : NSObject
{
    NSMutableURLRequest *_request;
    NSURLCredential     *_credential;
    
    NSInputStream   *_HTTPStream;
    off_t           _expectedOffset;
}

- (id)initWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential;

- (int)read:(char *)buffer size:(size_t)size offset:(off_t)offset error:(NSError **)outError;

- (void)close;

@end

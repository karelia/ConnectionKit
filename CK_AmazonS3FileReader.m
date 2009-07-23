//
//  CK_AmazonS3Stream.m
//  S3MacFUSE
//
//  Created by Mike on 23/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CK_AmazonS3FileReader.h"

#import "CK_AmazonS3RESTOperation.h"
#import "CKHTTPConnection.h"


@implementation CK_AmazonS3FileReader

- (id)initWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential;
{
    [self init];
    
    _request = [request mutableCopy];
    _credential = [credential retain];
    
    return self;
}

- (int)read:(char *)buffer size:(size_t)size offset:(off_t)offset error:(NSError **)outError;
{
    // Open the stream if needed
    if (!_HTTPStream)
    {
        [CK_AmazonS3RESTOperation addAuthentication:_credential toRequest:_request];
        CFHTTPMessageRef message = [_request makeHTTPMessage];
        _HTTPStream = NSMakeCollectable(CFReadStreamCreateForHTTPRequest(NULL, message));
        
        [_HTTPStream setProperty:(id)kCFBooleanTrue
                          forKey:(NSString *)kCFStreamPropertyHTTPShouldAutoredirect];
                
        if (offset == 0)
        {
            [_HTTPStream open];
        }
        else
        {
            if (outError) *outError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                          code:ESPIPE
                                                      userInfo:nil];
            return -1;
        }
    }
    
    
    
    // Read from stream if in the right place
    int result = -1;
    if (offset == _expectedOffset)
    {
        result = [_HTTPStream read:(uint8_t *)buffer maxLength:size];
        if (result < 0)
        {
            if (outError) *outError = [_HTTPStream streamError];
        }
        else 
        {
            _expectedOffset += result;
        }
    }
    else
    {
        if (outError) *outError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                      code:ESPIPE
                                                  userInfo:nil];
    }
    
    return result;
}

- (void)close;
{
    [_HTTPStream close];
    [_HTTPStream release], _HTTPStream = nil;
}

@end

//
//  CK_AmazonS3Stream.m
//  S3MacFUSE
//
//  Created by Mike on 23/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKAmazonS3Handle.h"

#import "CK_AmazonS3RESTOperation.h"
#import "CKHTTPConnection.h"


@implementation CKAmazonS3Handle

#pragma mark Init

- (id)initWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential;
{
    [self init];
    
    _request = [request mutableCopy];
    _credential = [credential retain];
    
    return self;
}

- (BOOL)createStreamWithOffset:(off_t)offset error:(NSError **)outError
{
    [CK_AmazonS3RESTOperation addAuthentication:_credential toRequest:_request];
    CFHTTPMessageRef message = [_request makeHTTPMessage];
    _stream = NSMakeCollectable(CFReadStreamCreateForHTTPRequest(NULL, message));
    
    [_stream setProperty:(id)kCFBooleanTrue
                      forKey:(NSString *)kCFStreamPropertyHTTPShouldAutoredirect];
    
    if (offset == 0)
    {
        [_stream open];
    }
    else
    {
        if (outError) *outError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                      code:ESPIPE
                                                  userInfo:nil];
        return NO;
    }
    
    return YES;
}

#pragma mark Received Data

- (int)read:(uint8_t *)buffer size:(size_t)size offset:(off_t)offset error:(NSError **)outError;
{
    // Open the stream if needed
    if (!_stream)
    {
        [self createStreamWithOffset:offset error:outError];
    }
    
    
    
    // Read from stream if in the right place
    int result = -1;
    if (offset == _expectedOffset)
    {
        result = [self read:buffer size:size error:outError];
        if (result > 0)
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

/*  The key method. It reads the next lump of data from the stream, not caring about offsets
 */
- (int)read:(uint8_t *)buffer size:(size_t)size error:(NSError **)outError;
{
    int result = 0;
    NSError *error = nil;
    
    
    // Open the stream if needed
    if (!_stream)
    {
        if (![self createStreamWithOffset:0 error:&error]) result = -1;
    }
    
    
    // Read
    if (result > -1)
    {
        result = [_stream read:buffer maxLength:size];
        if (result < 0) error = [_stream streamError];
        
        
        // The response comes down the pipe first and determines how we treat the rest of the data (i.e. could fail the read, turning the data into an error)
        if (!_haveProcessedResponse)
        {
            NSHTTPURLResponse *response = [self response];
            if (response)
            {
                _haveProcessedResponse = YES;   // do this early so error handling can read in more data if it wants
                
                if ([response statusCode] >= 300)   // OMG, it's an error
                {
                    // TODO: Read in the response body and convert it to an error object
                    NSMutableData *errorData = [[NSMutableData alloc] initWithBytes:buffer length:result];
                    NSData *errorData2 = [self readDataToEndOfFile:&error];
                    if (errorData2) // reading the remaining data could have failed
                    {
                        [errorData appendData:errorData2];
                        
                        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                                  response, @"URLResponse",
                                                  errorData, @"ReceivedData",
                                                  nil];
                        
                        error = [NSError errorWithDomain:NSURLErrorDomain
                                                    code:NSURLErrorUnknown
                                                userInfo:userInfo];                        
                    }
                    
                    [errorData release];
                    result = -1;
                }
            }
        }
    }
    
    
    if (result < 0 && outError) *outError = error;
    return result;
}

- (NSData *)readDataToEndOfFile:(NSError **)outError;
{
    // Read data
    NSMutableData *result = [[NSMutableData alloc] init];
    while ([_stream streamStatus] < NSStreamStatusAtEnd)
    {
        uint8_t buf[1024];
        int len = [self read:buf size:1024 error:outError];
        if (len < 0)
        {
            [result release], result = nil;
        }
        else
        {
            [result appendBytes:(const void *)buf length:len];
        }
    }
    
    return [result autorelease];
}

// If possible, constructs a response object from the HTTP response. Does not block.
- (NSHTTPURLResponse *)response;
{
    NSHTTPURLResponse *result = nil;
    
    CFHTTPMessageRef responseMessage = (CFHTTPMessageRef)[_stream propertyForKey:(NSString *)kCFStreamPropertyHTTPResponseHeader];
    if (responseMessage && CFHTTPMessageIsHeaderComplete(responseMessage))
    {
        NSURL *URL = [_stream propertyForKey:(NSString *)kCFStreamPropertyHTTPFinalURL];
        result = [NSHTTPURLResponse responseWithURL:URL HTTPMessage:responseMessage];
    }
    
    return result;
}

#pragma mark Close

- (void)close;
{
    [_stream close];
    [_stream release], _stream = nil;
}


@end

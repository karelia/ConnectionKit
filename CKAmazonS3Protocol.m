//
//  CKAmazonS3Protocol.m
//  ConnectionKit
//
//  Created by Mike on 25/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKAmazonS3Protocol.h"


@implementation CKAmazonS3Protocol

#pragma mark Initialisation & Deallocation

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSURL *URL = [request URL];
    
    NSString *host = [URL host];
    if ([host isEqualToString:@"s3.amazonaws.com"] || [host hasSuffix:@".s3.amazonaws.com"])
    {
        NSString *scheme = [URL scheme];
        if (scheme && [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
        {
            return YES;
        }
    }
    
    return NO;
}

- (void)dealloc
{
    NSAssert2(!_currentOperation,
              @"%@ deallocation is leaking operation: %@",
              self,
              _currentOperation);
    
    [super dealloc];
}

#pragma mark Operations

- (void)fetchContentsOfDirectoryAtPath:(NSString *)path
{
    // S3 uses GET requests for directory contents. We then have to parse out the contents of the returned XML
    NSURL *URL = [[NSURL alloc] initWithString:remotePath relativeToURL:[[self request] URL]];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:URL];
    [URL release];
    
    
    // Start the request
    [self startOperationWithRequest:request];
    [request release];
}

// S3 only supports creating new buckets
- (void)createDirectoryAtPath:(NSString *)path
{
    NSParameterAssert(path);
    NSParameterAssert([path isAbsolutePath]);
    NSParameterAssert([[path pathComponents] count] == 2);
    
    
    // Send a PUT request with no data
    NSString *URLString = [[NSString alloc] initWithFormat:
                           @"%@://%@.s3.amazonaws.com/",
                           [[[self request] URL] scheme],
                           [path lastPathComponent]];
    
    NSURL *URL = [[NSURL alloc] initWithString:URLString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setHTTPMethod:@"PUT"];
    [URL release];
    [URLString release];
    
    
    // Send the request
    [self startOperationWithRequest:request];
    [request release];
}

#pragma mark Current Operation Handling

- (void)startOperationWithRequest:(NSURLRequest *)request
{
    NSAssert(!_currentOperation, @"Attempting to start an S3 operation while another is in progress");
    _currentOperation = [[CKAmazonS3RESTOperation alloc] initWithRequest:request
                                                              credential:_credential
                                                                delegate:self];
    NSAssert1(_currentOperation, @"Failed to create a connection for request: %@", request);
}

@end

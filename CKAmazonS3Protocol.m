//
//  CKAmazonS3Protocol.m
//  ConnectionKit
//
//  Created by Mike on 25/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKAmazonS3Protocol.h"


@implementation CKAmazonS3Protocol

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

@end

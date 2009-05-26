//
//  CKConnectionError.m
//  Connection
//
//  Created by Mike on 22/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//


#import "CKConnectionError.h"


NSString *const CKConnectionErrorURLResponseErrorKey = @"URLResponse";


@implementation NSError (ConnectionKit)

+ (NSError *)errorWithHTTPResponse:(CFHTTPMessageRef)response
{
    return [[[self alloc] initWithHTTPResponse:response] autorelease];
}

- (id)initWithHTTPResponse:(CFHTTPMessageRef)response
{
    return [self initWithDomain:@"HTTP"
                           code:CFHTTPMessageGetResponseStatusCode(response)
                       userInfo:nil];
}

- (id)initWithHTTPURLResponse:(NSHTTPURLResponse *)response
{
    return [self initWithDomain:@"HTTP" code:[response statusCode] userInfo:nil];
}

@end

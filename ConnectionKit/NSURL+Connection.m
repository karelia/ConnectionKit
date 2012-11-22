//
//  NSURL+Connection.m
//  Connection
//
//  Created by Mike on 05/12/2008.
//  Copyright 2008 Karelia Software. All rights reserved.
//

#import "NSURL+Connection.h"

#import "NSString+Connection.h"


@implementation NSURL (ConnectionKitAdditions)

- (id)initWithScheme:(NSString *)scheme
                host:(NSString *)host
                port:(NSNumber *)port
                user:(NSString *)username
            password:(NSString *)password
{
    NSParameterAssert(scheme);
	
	
	NSMutableString *buffer = [[NSMutableString alloc] initWithFormat:@"%@://", scheme];
    
    if (username && ![username isEqualToString:@""])
    {
        [buffer appendString:[username encodeLegally]];
        if (password && ![password isEqualToString:@""])
        {
            [buffer appendFormat:@":%@", [password encodeLegally]];
        }
        [buffer appendString:@"@"];    
    }
    
    
	if (host) [buffer appendString:host];
	
    
    if (port)
    {
        [buffer appendFormat:@":%i", [port intValue]];
    }
    
    self = [self initWithString:buffer];
    [buffer release];
    return self;
}

@end

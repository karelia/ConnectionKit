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
        [buffer appendString:[username encodeLegallyForURL]];
        if (password && ![password isEqualToString:@""])
        {
			NSString *escapedPassword = [password encodeLegallyForURL];
			[buffer appendFormat:@":%@", escapedPassword];
			[escapedPassword release];
        }
        [buffer appendString:@"@"];    
    }
	
    
	if (host)
		[buffer appendString:host];
	
    
    if (port)
        [buffer appendFormat:@":%i", [port intValue]];
	    
    self = [self initWithString:buffer];
    [buffer release];
    return self;
}

/**
	@method originalUnescapedPassword
	@abstract The password, in original form, without any percent escapes.
	@result The original password provided to initWithScheme:host:port:user:password:, without any percent escapes.
 */
- (NSString *)originalUnescapedPassword
{
	NSString *unescapedPassword = (NSString *)CFURLCreateStringByReplacingPercentEscapesUsingEncoding(NULL,
																									  (CFStringRef)[self password], 
																									  CFSTR(""), //Replace all percent escapes, as per docs.
																									  kCFStringEncodingUTF8);
	return [unescapedPassword autorelease];
}

@end

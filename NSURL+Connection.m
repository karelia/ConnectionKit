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
			//We need all non-legal URL characters escaped, so we can't use the NSString -encodeLegally category method here.
			NSString *escapedPassword = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL,
																							(CFStringRef)password,
																							NULL,
																							(CFStringRef)@"@", //Technically @ is a legal URL character, but because we're constructing a url with a username, the @ is NOT legal as part of a password. It must be escaped.
																							kCFStringEncodingUTF8);
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

- (NSString *)decodedPassword
{
	NSString *decodedPassword = (NSString *)CFURLCreateStringByReplacingPercentEscapesUsingEncoding(NULL,
																									(CFStringRef)[self password], 
																									CFSTR(""), 
																									kCFStringEncodingUTF8);
	return [decodedPassword autorelease];
}

@end

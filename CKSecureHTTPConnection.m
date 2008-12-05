//
//  CKSecureHTTPConnection.m
//  Connection
//
//  Created by Greg Hulands on 26/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKSecureHTTPConnection.h"
#import "DotMacConnection.h"

@implementation CKSecureHTTPConnection

+ (void)load	// registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:443], ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"https://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[CKAbstractConnection registerConnectionClass:[CKSecureHTTPConnection class] forTypes:[NSArray arrayWithObjects:port, url, nil]];
	[pool release];
}

+ (NSInteger)defaultPort { return 443; }

+ (NSString *)name
{
	return @"Secure HTTP";
}

+ (id)connectionToHost:(NSString *)host
                  port:(NSNumber *)port
              username:(NSString *)username
              password:(NSString *)password
                 error:(NSError **)error
{
	CKSecureHTTPConnection *c = [[self alloc] initWithHost:host
                                                      port:port
                                                  username:username
                                                  password:password
                                                     error:error];
	return [c autorelease];
}

+ (NSString *)urlScheme
{
	return @"https";
}

- (id)initWithURL:(NSURL *)URL
{
	if ((self = [super initWithURL:URL]))
	{
		[self setSSLOn:YES];
	}
	return self;
}


@end

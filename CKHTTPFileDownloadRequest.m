//
//  CKHTTPFileDownloadRequest.m
//  Connection
//
//  Created by Greg Hulands on 21/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKHTTPFileDownloadRequest.h"


@implementation CKHTTPFileDownloadRequest

- (id)initWithRemotePath:(NSString *)file to:(NSString *)localFile
{
	if (self = [super initWithMethod:@"GET" uri:file])
	{
		myDestination = [localFile copy];
	}
	return self;
}

- (void)dealloc
{
	[myDestination release];
	[super dealloc];
}

+ (id)downloadRemotePath:(NSString *)file to:(NSString *)localFile
{
	return [[[CKHTTPFileDownloadRequest alloc] initWithRemotePath:file to:localFile] autorelease];
}

- (NSString *)destination
{
	return myDestination;
}

@end

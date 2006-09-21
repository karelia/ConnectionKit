//
//  CKHTTPFileDownloadResponse.m
//  Connection
//
//  Created by Greg Hulands on 21/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKHTTPFileDownloadResponse.h"
#import "CKHTTPFileDownloadRequest.h"

@implementation CKHTTPFileDownloadResponse

- (NSString *)destination
{
	if ([[self request] isKindOfClass:[CKHTTPFileDownloadRequest class]])
	{
		return [(CKHTTPFileDownloadRequest *)[self request] destination];
	}
	return nil;
}

- (NSString *)formattedResponse
{
	if ([self code] == 201)
	{
		return [NSString stringWithFormat:@"Downloaded: %@ to: %@", [self uri], [self destination]];
	}
	else
	{
		return [NSString stringWithFormat:@"Failed to download: %@", [self destination]];
	}
}

@end

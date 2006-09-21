//
//  CKHTTPFileDownloadRequest.h
//  Connection
//
//  Created by Greg Hulands on 21/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKHTTPRequest.h"


@interface CKHTTPFileDownloadRequest : CKHTTPRequest
{
	NSString *myDestination;
}

+ (id)downloadRemotePath:(NSString *)file to:(NSString *)localFile;

- (NSString *)destination;

@end

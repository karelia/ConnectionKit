//
//  CKHTTPPutRequest.h
//  Connection
//
//  Created by Greg Hulands on 21/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKHTTPRequest.h"


@interface CKHTTPPutRequest : CKHTTPRequest
{
	NSString *myFilename;
}

+ (id)putRequestWithData:(NSData *)data filename:(NSString *)filename uri:(NSString *)uri;
+ (id)putRequestWithContentsOfFile:(NSString *)path uri:(NSString *)uri;

@end

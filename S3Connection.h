//
//  S3Connection.h
//  Connection
//
//  Created by Greg Hulands on 20/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKHTTPConnection.h"


@interface S3Connection : CKHTTPConnection 
{
	NSString *myCurrentDirectory;
	unsigned long long	bytesTransferred;
	unsigned long long	bytesToTransfer;
	unsigned long long	transferHeaderLength;
	NSFileHandle *myDownloadHandle;
}

@end

extern NSString *S3StorageClassKey; // file attribute extension keys

extern NSString *S3ErrorDomain;

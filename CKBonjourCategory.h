//
//  CKBonjourCategory.h
//  Connection
//
//  Created by Greg Hulands on 26/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKHostCategory.h"


@interface CKBonjourCategory : CKHostCategory
{
	NSNetServiceBrowser *myFTPBrowser;
	NSNetServiceBrowser *mySFTPBrowser;
	NSNetServiceBrowser *myHTTPBrowser;
	
	CKHostCategory *myFTPCategory;
	CKHostCategory *mySFTPCategory;
	CKHostCategory *myHTTPCategory;
}

@end

//
//  CKTransferController.h
//  Connection
//
//  Created by Greg Hulands on 28/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface CKTransferController : NSObject 
{
	
	
	struct __cktransfercontroller_flags {
		unsigned useThread: 1;
		
		unsigned unused: 31;
	} myFlags;
}

@end

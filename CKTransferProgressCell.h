//
//  CKTransferProgressCell.h
//  Connection
//
//  Created by Greg Hulands on 17/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

/*
	To set the name and progress, set the object value with a dictionary
	and have the keys progress and name
 */

@interface CKTransferProgressCell : NSCell
{
	int myProgress;
}

@end

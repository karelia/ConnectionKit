//
//  DropletOutlineView.m
//  Connection
//
//  Created by Greg Hulands on 16/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "DropletOutlineView.h"


@implementation DropletOutlineView

- (void)reloadData
{
	if (isReloading)
	{
		[self performSelector:@selector(reloadData) withObject:nil afterDelay:0.0];
	}
	isReloading = YES;
	[super reloadData];
	isReloading = NO;
}

@end

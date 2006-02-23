//
//  ProgressCell.m
//  FTPConnection
//
//  Created by Greg Hulands on 3/12/04.
//  Copyright 2004 __MyCompanyName__. All rights reserved.
//

#import "ProgressCell.h"


@implementation ProgressCell

- (id)initTextCell:(NSString *)txt
{
	[super initTextCell:txt];
	[self setObjectValue:[NSNumber numberWithInt:-1]];
	return self;
}

- (void)setObjectValue:(id)obj
{
	[super setObjectValue:obj];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	float percent = [[self objectValue] intValue] / 100.0;
	
	if (percent < 0 || percent >= 1)
	{		
		if (percent < 0)
		{	
			NSString *str = nil;
			if (percent == -1.0)
			{
				str = [NSString stringWithString:@"Waiting..."];
			}
			else
			{
				str = [NSString stringWithString:@"Cancelled..."];
			}
			
			NSDictionary *attribs = [NSDictionary dictionaryWithObjectsAndKeys:nil];
			NSSize size = [str sizeWithAttributes:attribs];
			NSRect centered = NSMakeRect(NSMidX(cellFrame) - (size.width/2), 
										 NSMidY(cellFrame) - (size.height / 2),
										 NSWidth(cellFrame),
										 size.height);
			[str drawInRect:centered withAttributes:attribs];
		}
		else
		{
			NSString *str = [NSString stringWithString:@"Finished"];
			NSDictionary *attribs = [NSDictionary dictionaryWithObjectsAndKeys:nil];
			NSSize size = [str sizeWithAttributes:attribs];
			NSRect centered = NSMakeRect(NSMidX(cellFrame) - (size.width/2), 
										 NSMidY(cellFrame) - (size.height / 2),
										 NSWidth(cellFrame),
										 size.height);
			[str drawInRect:centered withAttributes:attribs];
		}
	}
	else
	{
		[[NSColor colorWithCalibratedRed:164.0/256.0 green:106.0/256.0 blue:255.0/256.0 alpha:1.0] set];
		NSRectFill(NSMakeRect(NSMinX(cellFrame),NSMinY(cellFrame),percent * NSWidth(cellFrame),NSHeight(cellFrame)));
		[[NSColor colorWithCalibratedRed:129.0/256.0 green:84.0/256.0 blue:201.0/256.0 alpha:1.0] set];
		NSFrameRect(cellFrame);
	}
	
}

@end

//
//  CKTransferProgressCell.m
//  Connection
//
//  Created by Greg Hulands on 17/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKTransferProgressCell.h"

static NSColor *sProgressColor = nil;
static NSImage *sErrorImage = nil;
static NSImage *sFinishedImage = nil;
static NSMutableParagraphStyle *sStyle = nil;

NSSize CKLimitMaxWidthHeight(NSSize ofSize, float toMaxDimension);

@implementation CKTransferProgressCell

+ (void)initialize
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	sProgressColor = [[NSColor colorForControlTint:NSDefaultControlTint] retain];
	
	NSBundle *b = [NSBundle bundleForClass:[self class]];
	NSString *path = [b pathForResource:@"error" ofType:@"png"];
	sErrorImage = [[NSImage alloc] initWithContentsOfFile:path];
	path = [b pathForResource:@"finished" ofType:@"png"];
	sFinishedImage = [[NSImage alloc] initWithContentsOfFile:path];
	
	sStyle = [[NSMutableParagraphStyle alloc] init];
	[sStyle setLineBreakMode:NSLineBreakByTruncatingTail];
	
	[pool release];
}

- (void)setObjectValue:(id)value
{
	if ([value isKindOfClass:[NSDictionary class]])
	{
		myProgress = [[value objectForKey:@"progress"] intValue];
		[super setObjectValue:[value objectForKey:@"name"]];
	}
	else if ([value isKindOfClass:[NSNumber class]])
	{
		myProgress = [value intValue];
	}
}

#define PADDING 5

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{	
	NSRect imageRect = NSMakeRect(NSMinX(cellFrame), NSMinY(cellFrame), NSHeight(cellFrame), NSHeight(cellFrame));
	imageRect = NSOffsetRect(imageRect, PADDING, 0);
	
	// from omni
	NSMutableAttributedString *label = [[NSMutableAttributedString alloc] initWithAttributedString:[self attributedStringValue]];
	NSRange labelRange = NSMakeRange(0, [label length]);
	if ([NSColor respondsToSelector:@selector(alternateSelectedControlColor)]) 
	{
		NSColor *highlightColor = [self highlightColorWithFrame:cellFrame inView:controlView];
		BOOL highlighted = [self isHighlighted];
		
		if (highlighted && [highlightColor isEqual:[NSColor alternateSelectedControlColor]]) 
		{
            // add the alternate text color attribute.
			[label addAttribute:NSForegroundColorAttributeName value:[NSColor alternateSelectedControlTextColor] range:labelRange];
		}
	}
	
	[label addAttribute:NSParagraphStyleAttributeName value:sStyle range:labelRange];
	NSSize labelSize = [label size];
	NSRect labelRect = NSMakeRect(NSMaxX(imageRect) + PADDING,  
								  NSMidY(cellFrame) - (labelSize.height / 2),
								  NSWidth(cellFrame) - NSWidth(imageRect) - PADDING,
								  labelSize.height);
	[label drawInRect:labelRect];
	[label release];
	
	// draw the image or progress pie
	if (myProgress < 0)
	{
		NSSize s = CKLimitMaxWidthHeight([sErrorImage size], NSHeight(cellFrame));
		NSRect centered = NSMakeRect(NSMidX(imageRect) - (s.width / 2), 
									 NSMidY(imageRect) - (s.height / 2),
									 s.width,
									 s.height);
		[sErrorImage setFlipped:[controlView isFlipped]];
		[sErrorImage drawInRect:centered
					   fromRect:NSZeroRect
					  operation:NSCompositeSourceOver
					   fraction:1.0];
	}
	else if (myProgress >= 0 && myProgress < 100)
	{
		NSAffineTransform *flip;
		if ([controlView isFlipped]) 
		{
			[[NSGraphicsContext currentContext] saveGraphicsState];
			flip = [NSAffineTransform transform];
			[flip translateXBy:0 yBy:NSMaxY(imageRect)];
			[flip scaleXBy:1 yBy:-1];
			[flip concat];
			imageRect.origin.y = 0;
		}
		
		NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:imageRect];
		NSPoint cp = NSMakePoint(NSMidX(imageRect), NSMidY(imageRect));
		NSBezierPath *pie = [NSBezierPath bezierPath];
		float degrees = (myProgress / 100.0) * 360.0;
		
		[pie moveToPoint:cp];
		[pie lineToPoint:NSMakePoint(NSMidX(imageRect), NSMaxY(imageRect))];
		
		int i;
		float radius = floor(NSMaxY(imageRect) - NSMidY(imageRect));
		float x, y;
		for (i = 0; i <= floor(degrees); i++) {
			float rad = i * (M_PI / 180.0);
			x = sinf(rad) * radius;
			y = cosf(rad) * radius;
			[pie lineToPoint:NSMakePoint(cp.x + x, cp.y + y)];
		}
		[pie lineToPoint:cp];
		[pie closePath];
		
		[[NSColor whiteColor] set];
		[circle fill];
		[[sProgressColor colorWithAlphaComponent:0.5] set];
		[pie fill];
		[sProgressColor set];
		[pie setLineWidth:1.0];
		[pie stroke];
		[sProgressColor set];
		[circle setLineWidth:1.0];
		[circle stroke];
		
		if ([controlView isFlipped]) 
		{
			[flip invert];
			[flip concat];
			[[NSGraphicsContext currentContext] restoreGraphicsState];
		}
		
	}
	else
	{
		// we are finished
		NSSize s = CKLimitMaxWidthHeight([sFinishedImage size], NSHeight(cellFrame));
		NSRect centered = NSMakeRect(NSMidX(imageRect) - (s.width / 2), 
									 NSMidY(imageRect) - (s.height / 2),
									 s.width,
									 s.height);
		[sFinishedImage setFlipped:[controlView isFlipped]];
		[sFinishedImage drawInRect:centered
						  fromRect:NSZeroRect
						 operation:NSCompositeSourceOver
						  fraction:1.0];
	}
}

@end

NSSize CKLimitMaxWidthHeight(NSSize ofSize, float toMaxDimension)
{
	float max = fmax(ofSize.width, ofSize.height);
	if (max <= toMaxDimension)
		return ofSize;
	
	if (ofSize.width >= ofSize.height)
	{
		ofSize.width = toMaxDimension;
		ofSize.height *= toMaxDimension / max;
	}
	else
	{
		ofSize.height = toMaxDimension;
		ofSize.width *= toMaxDimension / max;
	}
	
	return ofSize;
}

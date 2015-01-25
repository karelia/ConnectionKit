/*
 Copyright (c) 2006, Greg Hulands <ghulands@mac.com>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "CKTransferProgressCell.h"

static NSColor *sProgressColor = nil;
static NSImage *sErrorImage = nil;
static NSImage *sFinishedImage = nil;
static NSMutableParagraphStyle *sStyle = nil;

NSSize CKLimitMaxWidthHeight(NSSize ofSize, CGFloat toMaxDimension);

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
        
        _finished = [[value objectForKey:@"finished"] boolValue];
        if (_finished) myProgress = 100;
        
        NSError *error = [value objectForKey:@"error"];
        if (error && !(error.code == NSURLErrorCancelled && [error.domain isEqualToString:NSURLErrorDomain])) myProgress = -1;
        
		[super setObjectValue:[value objectForKey:@"name"]];
	}
	else if ([value isKindOfClass:[NSNumber class]])
	{
		myProgress = [value integerValue];
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

        [sErrorImage drawInRect:centered
					   fromRect:NSZeroRect
					  operation:NSCompositeSourceOver
					   fraction:1.0
                 respectFlipped:YES
                          hints:nil];
	}
	else if (myProgress >= 0 && !_finished)
	{
		NSAffineTransform *flip = nil;
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
		CGFloat degrees = (myProgress / 100.0) * 360.0;
		
		[pie moveToPoint:cp];
		[pie lineToPoint:NSMakePoint(NSMidX(imageRect), NSMaxY(imageRect))];
		
		int i;
		CGFloat radius = floor(NSMaxY(imageRect) - NSMidY(imageRect));
		CGFloat x, y;
		for (i = 0; i <= floor(degrees); i++) {
			CGFloat rad = i * (M_PI / 180.0);
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
        
		[sFinishedImage drawInRect:centered
						  fromRect:NSZeroRect
						 operation:NSCompositeSourceOver
						  fraction:1.0
                    respectFlipped:YES
                             hints:nil];
	}
}

@end

NSSize CKLimitMaxWidthHeight(NSSize ofSize, CGFloat toMaxDimension)
{
	CGFloat max = fmax(ofSize.width, ofSize.height);
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

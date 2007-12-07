//
//  CKDirectoryBrowserCell.m
//  UberUpload
//
//  Created by Bryan Hansen on 11/28/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "CKDirectoryBrowserCell.h"
#import "CKDirectoryNode.h"
#import "NSMatrix+Connection.h"

static NSMutableParagraphStyle *sStyle = nil;
#define PADDING 5

@implementation CKDirectoryBrowserCell

+ (void)initialize
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	if (!sStyle)
	{
		sStyle = [[NSMutableParagraphStyle alloc] init];
		[sStyle setLineBreakMode:NSLineBreakByTruncatingTail];
	}
	
	[pool release];
}

// This is required because NSBrowser when asked for its path uses the cells stringValue to build up the path. 
// If extensions are hidden it gets screwed up.
- (NSString *)stringValue
{
	if ([self representedObject])
	{
		return [[self representedObject] name];
	}
	return @"";
}

#define ICON_SIZE 16.0

- (NSSize)cellSizeForBounds:(NSRect)aRect 
{
    NSSize s = [super cellSizeForBounds:aRect];
    s.height += 1.0 * 2.0;
	s.width += NSWidth(aRect);
    return s;
}

- (void)setMakeDragImage:(BOOL)flag
{
	myMakingDragImage = flag;
}

#define ICON_INSET_VERT		2.0	/* The size of empty space between the icon end the top/bottom of the cell */ 
#define ICON_SIZE			16.0/* Our Icons are ICON_SIZE x ICON_SIZE */
#define ICON_INSET_HORIZ	4.0	/* Distance to inset the icon from the left edge. */
#define ICON_TEXT_SPACING	2.0	/* Distance between the end of the icon and the text part */

#define ARROW_SIZE 7.0

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{	
	if (![self isLoaded]) 
	{
		NSMatrix *matrix = (NSMatrix *)controlView;
		NSBrowser *browser = [matrix browser];
		int row = [[matrix cells] indexOfObject:self];
		int col = [browser columnOfMatrix:matrix]; 
		[[browser delegate] browser:browser willDisplayCell:self atRow:row column:col];
		[self setLoaded:YES];
	}
	
	NSImage *iconImage = [[self representedObject] iconWithSize:NSMakeSize(ICON_SIZE, ICON_SIZE)];
	if (iconImage != nil) {
        NSSize imageSize = [iconImage size];
        NSRect imageFrame, highlightRect, textFrame;
		
		// Divide the cell into 2 parts, the image part (on the left) and the text part.
		NSDivideRect(cellFrame, &imageFrame, &textFrame, ICON_INSET_HORIZ + ICON_TEXT_SPACING + imageSize.width, NSMinXEdge);
        imageFrame.origin.x += ICON_INSET_HORIZ;
        imageFrame.size = imageSize;
		
		// Adjust the image frame top account for the fact that we may or may not be in a flipped control view, since when compositing the online documentation states: "The image will have the orientation of the base coordinate system, regardless of the destination coordinates".
        if ([controlView isFlipped]) {
            imageFrame.origin.y += ceil((textFrame.size.height + imageFrame.size.height) / 2);
        } else {
            imageFrame.origin.y += ceil((textFrame.size.height - imageFrame.size.height) / 2);
        }
		
        // We don't draw the background when creating the drag and drop image
		BOOL drawsBackground = YES;
        if (drawsBackground) {
            // If we are highlighted, or we are selected (ie: the state isn't 0), then draw the highlight color
            if ([self isHighlighted] || [self state] != 0) {
                // The return value from highlightColorInView will return the appropriate one for you. 
                [[self highlightColorInView:controlView] set];
			} else {
				[[NSColor controlBackgroundColor] set];
			}
			// Draw the highlight, but only the portion that won't be caught by the call to [super drawInteriorWithFrame:...] below.  
			highlightRect = NSMakeRect(NSMinX(cellFrame), NSMinY(cellFrame), NSWidth(cellFrame) - NSWidth(textFrame), NSHeight(cellFrame));
			NSRectFill(highlightRect);
        }
		
        [iconImage compositeToPoint:imageFrame.origin operation:NSCompositeSourceOver fraction:1.0];
		
		// Have NSBrowserCell kindly draw the text part, since it knows how to do that for us, no need to re-invent what it knows how to do.
		[super drawInteriorWithFrame:textFrame inView:controlView];
    } else {
		// At least draw something if we couldn't find an icon. You may want to do something more intelligent.
    	[super drawInteriorWithFrame:cellFrame inView:controlView];
    }
}

@end

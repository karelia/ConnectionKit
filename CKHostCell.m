//
//  CKHostCell.m
//  Connection
//
//  Created by Greg Hulands on 20/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "CKHostCell.h"

static NSMutableParagraphStyle *sStyle = nil;

NSString *CKHostCellStringValueKey = @"CKHostCellStringValueKey";
NSString *CKHostCellImageValueKey = @"CKHostCellImageValueKey";
NSString *CKHostCellSecondaryStringValueKey = @"CKHostCellSecondaryStringValueKey";

@interface NSImage (Omni)
- (void)drawFlippedInRect:(NSRect)rect fromRect:(NSRect)sourceRect operation:(NSCompositingOperation)op fraction:(float)delta;
- (void)drawFlippedInRect:(NSRect)rect fromRect:(NSRect)sourceRect operation:(NSCompositingOperation)op;
- (void)drawFlippedInRect:(NSRect)rect operation:(NSCompositingOperation)op fraction:(float)delta;
- (void)drawFlippedInRect:(NSRect)rect operation:(NSCompositingOperation)op;
@end

@implementation CKHostCell

NSRect CKCenteredAspectRatioPreservedRect(NSRect rect, NSSize imgSize, NSSize maxCellSize)
{
	float ratioH = imgSize.width / NSWidth(rect);
	float ratioV = imgSize.height / NSHeight(rect);
	float destWidth = 0;
	float destHeight = 0;
	
	if (ratioV > ratioH) {
		destHeight = NSHeight(rect);
		if (destHeight > maxCellSize.height)
			destHeight = maxCellSize.height;
		destWidth = (destHeight / imgSize.height) * imgSize.width;
	} else {
		destWidth = NSWidth(rect);
		if (destWidth > maxCellSize.width) 
			destWidth = maxCellSize.width;
		destHeight = (destWidth / imgSize.width) * imgSize.height;
	}
	
	float x = NSMidX(rect);
	float y = NSMidY(rect);
	
	return NSMakeRect(x - (destWidth / 2), y - (destHeight / 2), destWidth, destHeight);
}

+ (void)initialize
{
	sStyle = [[NSMutableParagraphStyle alloc] init];
	[sStyle setLineBreakMode:NSLineBreakByTruncatingTail];
}

- (id)init;
{
    if ([super initTextCell:@""] == nil)
        return nil;
    
    [self setImagePosition:NSImageLeft];
    [self setEditable:YES];
    [self setDrawsHighlight:YES];
    [self setScrollable:YES];
    
    return self;
}

- (id)initTextCell:(NSString *)str
{
#pragma unused (str)
	if ((self = [self init])) {
		
	}
	return self;
}

- (id)initImageCell:(NSImage *)image
{
#pragma unused (image)
	if ((self = [self init])) {
		
	}
	return self;
}

- (void)awakeFromNib
{
	[self setImagePosition:NSImageLeft];
    [self setEditable:YES];
    [self setDrawsHighlight:YES];
    [self setScrollable:YES];
}

- (void)dealloc;
{
    [myIcon release];    
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone;
{
    CKHostCell *copy = [super copyWithZone:zone];
    
    copy->myIcon = [myIcon retain];
    copy->myFlags.drawsHighlight = myFlags.drawsHighlight;
    
    return copy;
}

#define TEXT_VERTICAL_OFFSET (-1.0)
#define FLIP_VERTICAL_OFFSET (-9.0)
#define BORDER_BETWEEN_EDGE_AND_IMAGE (2.0)
#define BORDER_BETWEEN_IMAGE_AND_TEXT (3.0)
#define SIZE_OF_TEXT_FIELD_BORDER (1.0)

- (NSColor *)highlightColorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
{
    if (!myFlags.drawsHighlight)
        return nil;
    else
        return [super highlightColorWithFrame:cellFrame inView:controlView];
}

- (NSColor *)textColor;
{
    if (myFlags.settingUpFieldEditor)
        return [NSColor blackColor];
    else if (!myFlags.drawsHighlight && _cFlags.highlighted)
        return [NSColor textBackgroundColor];
    else
        return [super textColor];
}

#define CELL_SIZE_FUDGE_FACTOR 10.0

- (NSSize)cellSize;
{
    NSSize cellSize = [super cellSize];
    // TODO: WJS 1/31/04 -- I REALLY don't think this next line is accurate. It appears to not be used much, anyways, but still...
    cellSize.width += [myIcon size].width + (BORDER_BETWEEN_EDGE_AND_IMAGE * 2.0) + (BORDER_BETWEEN_IMAGE_AND_TEXT * 2.0) + (SIZE_OF_TEXT_FIELD_BORDER * 2.0) + CELL_SIZE_FUDGE_FACTOR;
    return cellSize;
}

#define _calculateDrawingRectsAndSizes \
NSRectEdge rectEdge;  \
NSSize imageSize; \
\
if (myFlags.imagePosition == NSImageLeft) { \
	rectEdge = NSMinXEdge; \
		if (myIcon == nil) \
			imageSize = NSZeroSize; \
				else \
					imageSize = NSMakeSize(NSHeight(aRect) - 1, NSHeight(aRect) - 1); \
} else { \
	rectEdge =  NSMaxXEdge; \
        if (myIcon == nil) \
            imageSize = NSZeroSize; \
				else \
					imageSize = [myIcon size]; \
} \
\
NSRect cellFrame = aRect, ignored; \
if (imageSize.width > 0) \
NSDivideRect(cellFrame, &ignored, &cellFrame, BORDER_BETWEEN_EDGE_AND_IMAGE, rectEdge); \
\
NSRect imageRect, textRect; \
NSDivideRect(cellFrame, &imageRect, &textRect, imageSize.width, rectEdge); \
\
if (imageSize.width > 0) \
NSDivideRect(textRect, &ignored, &textRect, BORDER_BETWEEN_IMAGE_AND_TEXT, rectEdge); \
\
textRect.origin.y += 1.0;


- (void)drawInteriorWithFrame:(NSRect)aRect inView:(NSView *)controlView;
{
    /*_calculateDrawingRectsAndSizes;*/
	NSRectEdge rectEdge;  
	NSSize imageSize; 
	
	if (myFlags.imagePosition == NSImageLeft) { 
		rectEdge = NSMinXEdge; 
		if (myIcon == nil)
			imageSize = NSZeroSize;
		else
			imageSize = NSMakeSize(NSHeight(aRect) - 1, NSHeight(aRect) - 1); 
	} else { 
		rectEdge =  NSMaxXEdge; 
		if (myIcon == nil) 
			imageSize = NSZeroSize; 
		else 
			imageSize = [myIcon size]; 
	} 
	
	NSRect cellFrame = aRect, ignored; 
	if (imageSize.width > 0) 
		NSDivideRect(cellFrame, &ignored, &cellFrame, BORDER_BETWEEN_EDGE_AND_IMAGE, rectEdge); 
				
	NSRect imageRect, textRect; 
	NSDivideRect(cellFrame, &imageRect, &textRect, imageSize.width, rectEdge); 
				
	if (imageSize.width > 0) 
		NSDivideRect(textRect, &ignored, &textRect, BORDER_BETWEEN_IMAGE_AND_TEXT, rectEdge); 
				
	textRect.origin.y += 1.0;
	
    
    NSDivideRect(textRect, &ignored, &textRect, SIZE_OF_TEXT_FIELD_BORDER, NSMinXEdge);
    textRect = NSInsetRect(textRect, 1.0, 0.0);
	
    if (![controlView isFlipped])
        textRect.origin.y -= (textRect.size.height + FLIP_VERTICAL_OFFSET);
	
    // Draw the text
    NSMutableAttributedString *label = [[NSMutableAttributedString alloc] initWithAttributedString:[self attributedStringValue]];
    NSRange labelRange = NSMakeRange(0, [label length]);
    if ([NSColor respondsToSelector:@selector(alternateSelectedControlColor)]) {
        NSColor *highlightColor = [self highlightColorWithFrame:cellFrame inView:controlView];
        BOOL highlighted = [self isHighlighted];
		
        if (highlighted && [highlightColor isEqual:[NSColor alternateSelectedControlColor]]) {
            // add the alternate text color attribute.
            [label addAttribute:NSForegroundColorAttributeName value:[NSColor alternateSelectedControlTextColor] range:labelRange];
        }
    }
    
    [label addAttribute:NSParagraphStyleAttributeName value:sStyle range:labelRange];
	NSSize size = [label size];
	NSRect centered = NSMakeRect(NSMinX(textRect), 
								 NSMidY(textRect) - (size.height / 2),
								 NSWidth(textRect),
								 size.height);
    [label drawInRect:centered];
    [label release];
    
    // Draw the image
	NSSize maxImageSize = [[self icon] size];
	if (maxImageSize.width > NSWidth(imageRect)) maxImageSize.width = NSWidth(imageRect);
	if (maxImageSize.height > NSHeight(imageRect)) maxImageSize.height = NSHeight(imageRect);
	imageRect = CKCenteredAspectRatioPreservedRect(imageRect, [[self icon] size], maxImageSize);
    //imageRect.size = imageSize;
	//imageRect.size = [[self myIcon] size];
    //imageRect.origin.y = NSMidY(aRect) - imageRect.size.height / 2;
	
    if ([controlView isFlipped])
        [[self icon] drawFlippedInRect:imageRect fromRect:NSZeroRect operation:NSCompositeSourceOver];
    else
        [[self icon] drawInRect:imageRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
}

- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)flag;
{
    return [super trackMouse:theEvent inRect:cellFrame ofView:controlView untilMouseUp:flag];
}

- (void)editWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject event:(NSEvent *)theEvent;
{
    myFlags.settingUpFieldEditor = YES;
    [super editWithFrame:aRect inView:controlView editor:textObj delegate:anObject event:theEvent];
    myFlags.settingUpFieldEditor = NO;
}
- (void)selectWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject start:(int)selStart length:(int)selLength;
{
    _calculateDrawingRectsAndSizes;
    
	/* This puts us off by a single pixel vertically in OmniWeb's workspace panel. - WJS 1/31/04
    if ([controlView isFlipped])
	textRect.origin.y += TEXT_VERTICAL_OFFSET; // Move it up a pixel so we don't draw off the bottom
    else
	textRect.origin.y -= (textRect.size.height + FLIP_VERTICAL_OFFSET);
	*/
	
	NSDivideRect(textRect, &ignored, &textRect, SIZE_OF_TEXT_FIELD_BORDER, NSMinXEdge);
    textRect = NSInsetRect(textRect, 1.0, 0.0);
	
    if (![controlView isFlipped])
        textRect.origin.y -= (textRect.size.height + FLIP_VERTICAL_OFFSET);
	
    // Draw the text
    NSMutableAttributedString *label = [[NSMutableAttributedString alloc] initWithAttributedString:[self attributedStringValue]];
    NSRange labelRange = NSMakeRange(0, [label length]);
    
    [label addAttribute:NSParagraphStyleAttributeName value:sStyle range:labelRange];
	NSSize size = [label size];
	NSRect centered = NSMakeRect(NSMinX(textRect), 
								 NSMidY(textRect) - (size.height / 2),
								 NSWidth(textRect),
								 size.height);
	
	// textRect.size.height -= 3.0f;
    myFlags.settingUpFieldEditor = YES;
    [super selectWithFrame:centered inView:controlView editor:textObj delegate:anObject start:selStart length:selLength];
    myFlags.settingUpFieldEditor = NO;
}

- (void)setObjectValue:(id)obj;
{
    if ([obj isKindOfClass:[NSDictionary class]]) 
	{
        NSDictionary *dictionary = (NSDictionary *)obj;
        
        [super setObjectValue:[dictionary objectForKey:CKHostCellStringValueKey]];
        [self setIcon:[dictionary objectForKey:CKHostCellImageValueKey]];
    }
	else if ([obj isKindOfClass:[NSImage class]])
	{
		[self setIcon:obj];
	}
	else
	{
		[super setObjectValue:obj];
		return;
	}
}

// API

- (NSImage *)icon;
{
    return myIcon;
}

- (void)setIcon:(NSImage *)anIcon;
{
    if (anIcon == myIcon)
        return;
    [myIcon release];
    myIcon = [anIcon retain];
}

- (NSCellImagePosition)imagePosition;
{
    return myFlags.imagePosition;
}
- (void)setImagePosition:(NSCellImagePosition)aPosition;
{
    myFlags.imagePosition = aPosition;
}


- (BOOL)drawsHighlight;
{
    return myFlags.drawsHighlight;
}

- (void)setDrawsHighlight:(BOOL)flag;
{
    myFlags.drawsHighlight = flag;
}

- (NSRect)textRectForFrame:(NSRect)aRect inView:(NSView *)controlView;
{
    _calculateDrawingRectsAndSizes;
    
	NSDivideRect(textRect, &ignored, &textRect, SIZE_OF_TEXT_FIELD_BORDER, NSMinXEdge);
    textRect = NSInsetRect(textRect, 1.0, 0.0);
	
    if (![controlView isFlipped])
        textRect.origin.y -= (textRect.size.height + FLIP_VERTICAL_OFFSET);
	
    // Draw the text
    NSMutableAttributedString *label = [[NSMutableAttributedString alloc] initWithAttributedString:[self attributedStringValue]];
    NSRange labelRange = NSMakeRange(0, [label length]);
    
    [label addAttribute:NSParagraphStyleAttributeName value:sStyle range:labelRange];
	NSSize size = [label size];
	NSRect centered = NSMakeRect(NSMinX(textRect), 
								 NSMidY(textRect) - (size.height / 2),
								 NSWidth(textRect),
								 size.height);
	
    return centered;
}


@end


@implementation NSImage (Omni)
- (void)drawFlippedInRect:(NSRect)rect fromRect:(NSRect)sourceRect operation:(NSCompositingOperation)op fraction:(float)delta;
{
    CGContextRef context;
	
    context = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(context); {
        CGContextTranslateCTM(context, 0, NSMaxY(rect));
        CGContextScaleCTM(context, 1, -1);
        
        rect.origin.y = 0; // We've translated ourselves so it's zero
        [self drawInRect:rect fromRect:sourceRect operation:op fraction:delta];
    } CGContextRestoreGState(context);
}

- (void)drawFlippedInRect:(NSRect)rect fromRect:(NSRect)sourceRect operation:(NSCompositingOperation)op;
{
    [self drawFlippedInRect:rect fromRect:sourceRect operation:op fraction:1.0];
}

- (void)drawFlippedInRect:(NSRect)rect operation:(NSCompositingOperation)op fraction:(float)delta;
{
    [self drawFlippedInRect:rect fromRect:NSZeroRect operation:op fraction:delta];
}

- (void)drawFlippedInRect:(NSRect)rect operation:(NSCompositingOperation)op;
{
    [self drawFlippedInRect:rect operation:op fraction:1.0];
}
@end

@implementation CKHostExtendedCell : CKHostCell

- (id)copyWithZone:(NSZone *)zone
{
	CKHostExtendedCell *copy = [super copyWithZone:zone];
	
	copy->mySecondaryString = [mySecondaryString copy];
	
	return copy;
}

- (void)dealloc
{
	[mySecondaryString release];
	
	[super dealloc];
}

- (void)setSecondaryString:(NSString *)str
{
	if (mySecondaryString != str)
	{
		[mySecondaryString autorelease];
		mySecondaryString = [str copy];
	}
}

- (NSString *)secondaryString
{
	return mySecondaryString;
}

- (void)setObjectValue:(id)obj
{
	[super setObjectValue:obj];
	
	if ([obj isKindOfClass:[NSDictionary class]]) 
	{        
        [self setSecondaryString:[obj objectForKey:CKHostCellSecondaryStringValueKey]];
    }
}

// this drawing code is modified from http://www.martinkahr.com/2007/05/04/nscell-image-and-text-sample/

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView 
{
	[self setTextColor:[NSColor blackColor]];
		
	NSColor* primaryColor   = [NSColor textColor];
	NSString* primaryText   = [self stringValue];
	
	NSDictionary* primaryTextAttributes = [NSDictionary dictionaryWithObjectsAndKeys: primaryColor, NSForegroundColorAttributeName,
		[NSFont systemFontOfSize:13], NSFontAttributeName, nil];
	
	NSColor* secondaryColor = [self isHighlighted] ? [NSColor alternateSelectedControlTextColor] : [NSColor disabledControlTextColor];
	NSString* secondaryText = [self secondaryString];
	
	NSDictionary* secondaryTextAttributes = [NSDictionary dictionaryWithObjectsAndKeys: secondaryColor, NSForegroundColorAttributeName,
		[NSFont systemFontOfSize:10], NSFontAttributeName, nil];
	
	NSSize primarySize = [primaryText sizeWithAttributes:primaryTextAttributes];
	NSPoint primaryPoint = NSMakePoint(cellFrame.origin.x+cellFrame.size.height+10, cellFrame.origin.y);
	if (!secondaryText)
	{
		primaryPoint = NSMakePoint(cellFrame.origin.x+cellFrame.size.height+10, NSMidY(cellFrame) - (primarySize.height / 2.0));
	}
	[primaryText drawAtPoint:primaryPoint withAttributes:primaryTextAttributes];
	
		
	[secondaryText drawAtPoint:NSMakePoint(cellFrame.origin.x+cellFrame.size.height+10, cellFrame.origin.y+cellFrame.size.height/2) 
				withAttributes:secondaryTextAttributes];
	
	
	[[NSGraphicsContext currentContext] saveGraphicsState];
	float yOffset = cellFrame.origin.y;
	if ([controlView isFlipped]) {
		NSAffineTransform* xform = [NSAffineTransform transform];
		[xform translateXBy:0.0 yBy: cellFrame.size.height];
		[xform scaleXBy:1.0 yBy:-1.0];
		[xform concat];		
		yOffset = 0-cellFrame.origin.y;
	}	
	NSImage* icon = [self icon];	
	
	NSImageInterpolation interpolation = [[NSGraphicsContext currentContext] imageInterpolation];
	[[NSGraphicsContext currentContext] setImageInterpolation: NSImageInterpolationHigh];	
	
	[icon drawInRect:NSMakeRect(cellFrame.origin.x+5,yOffset+3,cellFrame.size.height-6, cellFrame.size.height-6)
			fromRect:NSMakeRect(0,0,[icon size].width, [icon size].height)
		   operation:NSCompositeSourceOver
			fraction:1.0];
	
	[[NSGraphicsContext currentContext] setImageInterpolation: interpolation];
	
	[[NSGraphicsContext currentContext] restoreGraphicsState];	
}

@end


//
//  CK2IconItemView.m
//  ConnectionKit
//
//  Created by Paul Kim on 12/23/12.
//  Copyright (c) 2012 Paul Kim. All rights reserved.
//
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this list
// of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice, this
// list of conditions and the following disclaimer in the documentation and/or other
// materials provided with the distribution.
//
// Neither the name of Karelia Software nor the names of its contributors may be used to
// endorse or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
// SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
// TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
// WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "CK2IconItemView.h"
#import "CK2IconViewItem.h"

#import "NSURL+CK2OpenPanel.h"
#import "CK2IconView.h"
#import "NSImage+CK2OpenPanel.h"

#define MARGIN                 4.0
#define ICON_SIZE              64.0
#define ICON_SELECTION_MARGIN  4.0
#define ICON_TEXT_MARGIN       8.0
#define TEXT_WIDTH             114.0
#define TEXT_HEIGHT            34.0
#define SELECTION_RADIUS       8.5
#define INNER_SELECTION_RADIUS 3.0

@implementation CK2IconItemView

@synthesize item = _item;

- (id)initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect]) != nil)
    {
        [self createTextField];
    }
    return self;
}

- (void)dealloc
{
    [self setItem:nil];
    [_textCell release];
    [super dealloc];
}

- (void)createTextField
{
    _textCell = [[NSTextFieldCell alloc] initTextCell:@""];
    [_textCell setEditable:NO];
    [_textCell setAlignment:NSCenterTextAlignment];
    [_textCell setLineBreakMode:NSLineBreakByWordWrapping];
    [_textCell setTruncatesLastVisibleLine:YES];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqual:@"selected"] || [keyPath isEqual:@"enabled"])
    {
        [self setNeedsDisplay:YES];
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)setItem:(CK2IconViewItem *)item
{
    if (item != _item)
    {
        [_item removeObserver:self forKeyPath:@"selected"];
        [_item removeObserver:self forKeyPath:@"enabled"];
        _item = item;
        [_item addObserver:self forKeyPath:@"selected" options:NSKeyValueObservingOptionNew context:NULL];
        [_item addObserver:self forKeyPath:@"enabled" options:NSKeyValueObservingOptionNew context:NULL];
    }
}

- (NSRect)iconRectForBounds:(NSRect)bounds
{
    return NSMakeRect(NSMinX(bounds) + (NSWidth(bounds) - ICON_SIZE) / 2.0,
                      NSMinY(bounds) + (NSHeight(bounds) - (2 * ICON_SELECTION_MARGIN + 2 * MARGIN + ICON_SIZE + ICON_TEXT_MARGIN + TEXT_HEIGHT)) / 2.0 + TEXT_HEIGHT + ICON_TEXT_MARGIN + ICON_SELECTION_MARGIN + MARGIN,
                      ICON_SIZE, ICON_SIZE);
}

- (NSRect)textRectForBounds:(NSRect)bounds
{
    NSRect  rect;
    
    if ([[[self item] representedObject] ck2_isPlaceholder])
    {
        NSSize  size;
        
        rect = [self bounds];
        rect.size.height = CGFLOAT_MAX;
        rect.size.width = NSWidth(bounds) * .75;
        size = [_textCell cellSizeForBounds:rect];

        rect = NSMakeRect(NSMinX(bounds) + (NSWidth(bounds) - size.width) / 2.0, NSMinY(bounds) + (NSHeight(bounds) - size.height) / 2.0, size.width, size.height);
    }
    else
    {
        rect = NSMakeRect(NSMinX(bounds) + (NSWidth(bounds) - TEXT_WIDTH) / 2.0, NSMinY(bounds) + (NSHeight(bounds) - (2 * ICON_SELECTION_MARGIN + ICON_SIZE + ICON_TEXT_MARGIN + TEXT_HEIGHT)) / 2.0, TEXT_WIDTH, TEXT_HEIGHT);
    }
    return rect;
}

- (NSColor *)selectionColor
{
    return [NSColor colorWithCalibratedWhite:0.76 alpha:1.0];
}

- (void)drawSelectionForText:(NSString *)label inRect:(NSRect)rect
{
    // Draw text selection
    NSTextView      *fieldEditor;
    NSLayoutManager *layoutManager;
    NSRectArray     rects;
    NSUInteger      count;
    CGFloat         yPos;
    NSBezierPath    *path;
    NSRange         range;
    NSColor         *selectionColor;
    
    fieldEditor = (NSTextView *)[[self window] fieldEditor:YES forObject:self];
    [_textCell setUpFieldEditorAttributes:fieldEditor];
    [fieldEditor setString:label];
    [fieldEditor setFrame:rect];
    [fieldEditor setTextContainerInset:NSZeroSize];
    [fieldEditor setFont:[_textCell font]];
    
    layoutManager = [fieldEditor layoutManager];
    
    range = NSMakeRange(0, [label length]);
    rects = [layoutManager rectArrayForCharacterRange:range withinSelectedCharacterRange:range inTextContainer:[fieldEditor textContainer] rectCount:&count];
    
    if ([[self window] isKeyWindow])
    {
        selectionColor = [NSColor alternateSelectedControlColor];
        [_textCell setTextColor:[NSColor whiteColor]];
    }
    else
    {
        selectionColor = [self selectionColor];
    }
    [selectionColor set];
    
    yPos = NSMaxY(rect) - 1.0; // A little fudge
    count = MIN(2, count);
    for (NSUInteger i = 0; i < count; i++)
    {
        // The rects aren't positioned correctly so we correct them here. Also some fudge on the height
        rects[i].size.height += 1.0;
        rects[i].origin.x = NSMinX(rect) + (NSWidth(rect) - NSWidth(rects[i])) / 2.0;
        rects[i].origin.y = yPos - NSHeight(rects[i]);
        
        if (!NSContainsRect(rect, rects[i]) && (i != 0))
        {
            // We only care about the rects within the visible region. For instance, we sometimes get one rect for
            // the two lines plus another rect out of bounds
            count = i;
        }
        
        yPos = NSMinY(rects[i]);
    }
    
    path = nil;
    if (count > 1)
    {
        CGFloat         diff, height;
        
        diff = NSWidth(rects[0]) - NSWidth(rects[1]);
        if (diff < SELECTION_RADIUS + INNER_SELECTION_RADIUS)
        {
            // The two lines of text are pretty close to eachother so just construct one rect to encompass them both
            count = 1;
            height = NSHeight(rects[0]) + NSHeight(rects[1]);
            rects[0] = NSMakeRect(MIN(NSMinX(rects[0]), NSMinX(rects[1])), NSMaxY(rect) - height,
                                  MAX(NSWidth(rects[0]), NSWidth(rects[1])), height);
            rects[0] = NSInsetRect(rects[0], -SELECTION_RADIUS, 0.0);
            
            path = [NSBezierPath bezierPathWithRoundedRect:rects[0] xRadius:SELECTION_RADIUS yRadius:SELECTION_RADIUS];
        }
        else
        {
            // Lines of text are varying widths. Construct a path to follow the general shape, rounding the ends/corners.
            CGFloat radius;
            
            radius = NSHeight(rects[0]) / 2.0;
            
            path = [NSBezierPath bezierPath];
            // Top left corner
            [path moveToPoint:NSMakePoint(NSMinX(rects[0]), NSMaxY(rects[0]))];
            
            if (diff > 0.0)
            {
                // First line is wider than the second
                
                // Right cap, top rect
                [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(rects[0]), NSMinY(rects[0]) + radius) radius:radius startAngle:90 endAngle:270 clockwise:YES];
                
                // Upper right corner, bottom rect
                [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(rects[1]) + radius + INNER_SELECTION_RADIUS, NSMaxY(rects[1]) - INNER_SELECTION_RADIUS) radius:INNER_SELECTION_RADIUS startAngle:90 endAngle:180 clockwise:NO];
                
                // Lower right corner, bottom rect
                [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(rects[1]), NSMinY(rects[1]) + radius) radius:radius startAngle:0 endAngle:270 clockwise:YES];
                
                // Lower left corner, bottom rect
                [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(rects[1]), NSMinY(rects[1]) + radius) radius:radius startAngle:270 endAngle:180 clockwise:YES];
                
                // Upper left corner, bottom rect
                [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(rects[1]) - radius - INNER_SELECTION_RADIUS, NSMaxY(rects[1]) - INNER_SELECTION_RADIUS) radius:INNER_SELECTION_RADIUS startAngle:0 endAngle:90 clockwise:NO];
                
                // Left cap, top rect
                [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(rects[0]), NSMinY(rects[0]) + radius) radius:radius startAngle:270 endAngle:90 clockwise:YES];
            }
            else
            {
                // Upper right corner, top rect
                [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(rects[0]), NSMaxY(rects[0]) - radius) radius:radius startAngle:90 endAngle:0 clockwise:YES];
                
                // Lower right corner, top rect
                [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(rects[0]) + radius + INNER_SELECTION_RADIUS, NSMinY(rects[0]) + INNER_SELECTION_RADIUS) radius:INNER_SELECTION_RADIUS startAngle:180 endAngle:270 clockwise:NO];
                
                // Right cap, bottom rect
                [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(rects[1]), NSMinY(rects[1]) + radius) radius:radius startAngle:90 endAngle:270 clockwise:YES];
                
                // Left cap, bottom rect
                [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(rects[1]), NSMinY(rects[1]) + radius) radius:radius startAngle:180 endAngle:90 clockwise:YES];
                
                // Lower left corner, top rect
                [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(rects[0]) - radius - INNER_SELECTION_RADIUS, NSMinY(rects[0]) + INNER_SELECTION_RADIUS) radius:INNER_SELECTION_RADIUS startAngle:270 endAngle:0 clockwise:NO];
                [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(rects[0]), NSMaxY(rects[0]) - radius) radius:radius startAngle:180 endAngle:90 clockwise:YES];
            }
            [path closePath];
        }
    }
    else
    {
        rects[0] = NSInsetRect(rects[0], -SELECTION_RADIUS, 0);
        path = [NSBezierPath bezierPathWithRoundedRect:rects[0] xRadius:SELECTION_RADIUS yRadius:SELECTION_RADIUS];
    }
    
    [path fill];
}


- (void)drawRect:(NSRect)dirtyRect
{
    CK2IconViewItem *item;
    NSRect          iconRect, rect, bounds;
    NSColor         *color, *selectionColor;
    NSString        *label;
    NSURL           *url;
    
    item = [self item];

    NSAssert([item view] == self, @"Item view for view %@ not properly set.", self);
    
    url = [item representedObject];
    
    bounds = [self bounds];
    
    selectionColor = [NSColor colorWithCalibratedWhite:0.76 alpha:1.0];
    
    if (![url ck2_isPlaceholder])
    {
        // Draw icon (and its selection)
        iconRect = [self iconRectForBounds:bounds];
        if ([item isSelected])
        {
            NSBezierPath    *path;
            
            rect = NSInsetRect(iconRect, -ICON_SELECTION_MARGIN, -ICON_SELECTION_MARGIN);
            path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:ICON_SELECTION_MARGIN yRadius:ICON_SELECTION_MARGIN];
            [selectionColor set];
            [path fill];
        }
        
        [[url ck2_icon] drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
    
        if (![item isEnabled])
        {
            [[NSColor colorWithDeviceWhite:1.0 alpha:0.5] set];
            NSRectFillUsingOperation(iconRect, NSCompositeSourceAtop);
        }
    }
    
    color = [item isEnabled] ? [NSColor controlTextColor] : [NSColor disabledControlTextColor];
    
    rect = [self textRectForBounds:bounds];
    
    label = [url ck2_displayName];
    [_textCell setStringValue:label];
    
    if ([[self item] isSelected])
    {
        [self drawSelectionForText:label inRect:rect];
    }
    else
    {
        [_textCell setTextColor:color];
    }

    [_textCell drawWithFrame:rect inView:self];
}

-(void)mouseDown:(NSEvent *)theEvent
{
    NSInteger       clickCount;
    CK2IconViewItem *item;
    NSPoint         point;
    NSRect          bounds;
    BOOL            isFlipped;

    point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    bounds = [self bounds];
    item = [self item];
    isFlipped = [self isFlipped];

    if ([item isEnabled] &&
        (NSMouseInRect(point, [self iconRectForBounds:bounds], isFlipped) ||
         NSMouseInRect(point, [self textRectForBounds:bounds], isFlipped)))
    {
        [super mouseDown:theEvent];
        
        clickCount = [theEvent clickCount];
        
        if (clickCount == 1)
        {
            [NSApp sendAction:[item action] to:[item target] from:[self item]];
        }
        else if (clickCount == 2)
        {
            [NSApp sendAction:[item doubleAction] to:[item target] from:[self item]];
        }
    }
}

// Suppress animations
- (id)animator
{
    return self;
}

- (id)animationForKey:(NSString *)key
{
    return nil;
}

#pragma mark NSCoding

#define ITEM_KEY            @"item"

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if ((self = [super initWithCoder:aDecoder]) != nil)
    {        
        [self createTextField];
        [self setItem:[aDecoder decodeObjectForKey:ITEM_KEY]];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [super encodeWithCoder:aCoder];
    
    [aCoder encodeObject:[self item] forKey:ITEM_KEY];
}

@end

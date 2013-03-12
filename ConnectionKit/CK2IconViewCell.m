//
//  CK2IconViewCell.m
//  Connection
//
//  Created by Paul Kim on 3/11/13.
//
//

#import "CK2IconViewCell.h"
#import "NSURL+CK2OpenPanel.h"

#define ICON_SIZE              128.0
#define ICON_SELECTION_MARGIN  4.0
#define ICON_TEXT_MARGIN       8.0
#define TEXT_WIDTH             114.0
#define TEXT_HEIGHT            34.0
#define SELECTION_RADIUS       8.5
#define INNER_SELECTION_RADIUS 3.0

@implementation CK2IconViewCell

- (id)init
{
    if ((self = [super init]) != nil)
    {
        _textCell = [[NSTextFieldCell alloc] initTextCell:@""];
        [_textCell setEditable:NO];
        [_textCell setAlignment:NSCenterTextAlignment];
        [_textCell setLineBreakMode:NSLineBreakByWordWrapping];
        [_textCell setTruncatesLastVisibleLine:YES];
    }
    return self;
}

- (void)dealloc
{
    [_textCell release];
    [super dealloc];
}

- (NSRect)imageFrame
{
    NSRect      frame;
    
    frame = [self frame];
    return NSMakeRect(NSMinX(frame) + (NSWidth(frame) - ICON_SIZE) / 2.0, NSMinY(frame) + (NSHeight(frame) - (2 * ICON_SELECTION_MARGIN + ICON_SIZE + ICON_TEXT_MARGIN + TEXT_HEIGHT)) / 2.0 + TEXT_HEIGHT + ICON_TEXT_MARGIN + ICON_SELECTION_MARGIN, ICON_SIZE, ICON_SIZE);
}

- (NSRect)titleFrame
{
    NSRect  rect, bounds;
    
    bounds = [self frame];
    if ([[self representedItem] ck2_isPlaceholder])
    {
        NSSize  size;
        
        rect = [self frame];
        rect.size.height = CGFLOAT_MAX;
        rect.size.width = NSWidth(bounds) * .75;
//        size = [_textCell cellSizeForBounds:rect];
        size = NSMakeSize(114.0, 34.0);
        
        rect = NSMakeRect(NSMinX(bounds) + (NSWidth(bounds) - size.width) / 2.0, NSMinY(bounds) + (NSHeight(bounds) - size.height) / 2.0, size.width, size.height);
    }
    else
    {
        rect = NSMakeRect(NSMinX(bounds) + (NSWidth(bounds) - TEXT_WIDTH) / 2.0, NSMinY(bounds) + (NSHeight(bounds) - (2 * ICON_SELECTION_MARGIN + ICON_SIZE + ICON_TEXT_MARGIN + TEXT_HEIGHT)) / 2.0, TEXT_WIDTH, TEXT_HEIGHT);
    }
    return rect;
}

- (CALayer *)layerForType:(NSString *)type
{
    if ([type isEqualToString:IKImageBrowserCellBackgroundLayer])
    {
        CALayer     *layer;
    
        layer = [CALayer layer];
        [layer setDelegate:self];
        [layer setFrame:[self frame]];
        [layer setNeedsDisplay];

        return layer;
    }
    return [super layerForType:type];
}


- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)context
{
    NSRect          iconRect, rect;//, bounds;
    NSColor         *color, *selectionColor;
    NSString        *label;
    NSURL           *url;
    
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *nscg = [NSGraphicsContext graphicsContextWithGraphicsPort:context flipped:NO];
    [NSGraphicsContext setCurrentContext:nscg];
    
    url = [self representedItem];
    
//    bounds = [self frame];
    
    selectionColor = [NSColor colorWithCalibratedWhite:0.76 alpha:1.0];
    
    if (![url ck2_isPlaceholder])
    {
        // Draw icon (and its selection)
        NSImage     *icon;
        
        iconRect = [self imageFrame];
        if ([self isSelected])
        {
            NSBezierPath    *path;
            
            rect = NSInsetRect(iconRect, -ICON_SELECTION_MARGIN, -ICON_SELECTION_MARGIN);
            path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:ICON_SELECTION_MARGIN yRadius:ICON_SELECTION_MARGIN];
            [selectionColor set];
            [path fill];
        }
        
        //PENDING:
/*        if ([url isEqual:[(CK2IconView *)[item collectionView] homeURL]])
        {
            icon = [NSImage ck2_homeDirectoryImage];
        }
        else*/
        {
            icon = [url ck2_icon];
        }
        
        [icon drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];

        //PENDING:
/*        if (![item isEnabled])
        {
            [[NSColor colorWithDeviceWhite:1.0 alpha:0.5] set];
            NSRectFillUsingOperation(iconRect, NSCompositeSourceAtop);
        }*/
    }
  
    //PENDING:
//    color = [item isEnabled] ? [NSColor controlTextColor] : [NSColor disabledControlTextColor];
    color = [NSColor controlTextColor];
    
    rect = [self titleFrame];
    
    label = [url ck2_displayName];
    [_textCell setStringValue:label];
    
    if ([self isSelected])
    {
        // Draw text selection
        NSTextView      *fieldEditor;
        NSLayoutManager *layoutManager;
        NSRectArray     rects;
        NSUInteger      count;
        CGFloat         yPos;
        NSBezierPath    *path;
        NSRange         range;
        NSWindow        *window;
        
        window = [[self imageBrowserView] window];
        
        fieldEditor = (NSTextView *)[window fieldEditor:YES forObject:self];
        [_textCell setUpFieldEditorAttributes:fieldEditor];
        [fieldEditor setString:label];
        [fieldEditor setFrame:rect];
        [fieldEditor setTextContainerInset:NSZeroSize];
        [fieldEditor setFont:[_textCell font]];
        
        layoutManager = [fieldEditor layoutManager];
        
        range = NSMakeRange(0, [label length]);
        rects = [layoutManager rectArrayForCharacterRange:range withinSelectedCharacterRange:range inTextContainer:[fieldEditor textContainer] rectCount:&count];
        
        if ([window isKeyWindow])
        {
            selectionColor = [NSColor alternateSelectedControlColor];
            [_textCell setTextColor:[NSColor whiteColor]];
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
                // The two lines are pretty close to eachother so just construct one rect to encompass them both
                count = 1;
                height = NSHeight(rects[0]) + NSHeight(rects[1]);
                rects[0] = NSMakeRect(MIN(NSMinX(rects[0]), NSMinX(rects[1])), NSMaxY(rect) - height,
                                      MAX(NSWidth(rects[0]), NSWidth(rects[1])), height);
                rects[0] = NSInsetRect(rects[0], -SELECTION_RADIUS, 0.0);
                
                path = [NSBezierPath bezierPathWithRoundedRect:rects[0] xRadius:SELECTION_RADIUS yRadius:SELECTION_RADIUS];
            }
            else
            {
                // Lines are varying widths. Construct a path to follow the general shape, rounding the ends/corners.
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
    else
    {
        [_textCell setTextColor:color];
    }
    
    [_textCell drawWithFrame:rect inView:[self imageBrowserView]];
    
    [NSGraphicsContext restoreGraphicsState];
}

@end

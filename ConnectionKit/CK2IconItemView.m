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

#define ICON_SIZE             64.0
#define ICON_SELECTION_MARGIN 4.0
#define ICON_TEXT_MARGIN      8.0
#define TEXT_WIDTH            114.0
#define TEXT_HEIGHT           34.0
#define SELECTION_RADIUS      8.0

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

- (void)awakeFromNib
{
    [_item addObserver:self forKeyPath:@"selected" options:NSKeyValueObservingOptionNew context:NULL];
    [_item addObserver:self forKeyPath:@"enabled" options:NSKeyValueObservingOptionNew context:NULL];
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
    return NSMakeRect(NSMinX(bounds) + (NSWidth(bounds) - ICON_SIZE) / 2.0, NSMinY(bounds) + (NSHeight(bounds) - (2 * ICON_SELECTION_MARGIN + ICON_SIZE + ICON_TEXT_MARGIN + TEXT_HEIGHT)) / 2.0 + TEXT_HEIGHT + ICON_TEXT_MARGIN + ICON_SELECTION_MARGIN, ICON_SIZE, ICON_SIZE);
}

- (NSRect)textRectForBounds:(NSRect)bounds
{
    return NSMakeRect(NSMinX(bounds) + (NSWidth(bounds) - TEXT_WIDTH) / 2.0, NSMinY(bounds) + (NSHeight(bounds) - (2 * ICON_SELECTION_MARGIN + ICON_SIZE + ICON_TEXT_MARGIN + TEXT_HEIGHT)) / 2.0, TEXT_WIDTH, TEXT_HEIGHT);
}


- (void)drawRect:(NSRect)dirtyRect
{
    CK2IconViewItem *item;
    NSRect          iconRect, rect, bounds;
    NSColor         *color, *selectionColor;
    NSString        *label;
    
    item = [self item];

    NSAssert([item view] == self, @"Item view for view %@ not properly set.", self);
    
    bounds = [self bounds];
    
    selectionColor = [NSColor colorWithCalibratedWhite:0.76 alpha:1.0];
    
    iconRect = [self iconRectForBounds:bounds];
    if ([item isSelected])
    {
        NSBezierPath    *path;
        
        rect = NSInsetRect(iconRect, -ICON_SELECTION_MARGIN, -ICON_SELECTION_MARGIN);
        path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:ICON_SELECTION_MARGIN yRadius:ICON_SELECTION_MARGIN];
        [selectionColor set];
        [path fill];
    }
    
    [[[[self item] representedObject] ck2_icon] drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
    
    color = [NSColor controlTextColor];
    if (![[self item] isEnabled])
    {
        [[NSColor colorWithDeviceWhite:1.0 alpha:0.5] set];
        NSRectFillUsingOperation(iconRect, NSCompositeSourceAtop);
        
        color = [NSColor disabledControlTextColor];
    }
    
    rect = [self textRectForBounds:bounds];
    
    label = [[[self item] representedObject] ck2_displayName];
    [_textCell setStringValue:label];
    
    if ([[self item] isSelected])
    {
/*        NSTextView      *fieldEditor;
        NSLayoutManager *layoutManager;
        NSRectArray     rects;
        NSUInteger      count;
        
        fieldEditor = (NSTextView *)[[self window] fieldEditor:YES forObject:self];
        [self addSubview:fieldEditor];
        [fieldEditor setString:label];
        [fieldEditor setFrame:rect];
        [_textField setUpFieldEditorAttributes:fieldEditor];
        [fieldEditor setFont:[_textField font]];
        [fieldEditor alignCenter:nil];

        layoutManager = [fieldEditor layoutManager];
        
        rects = [layoutManager rectArrayForCharacterRange:NSMakeRange(0, [label length]) withinSelectedCharacterRange:NSMakeRange(0, [label length]) inTextContainer:[fieldEditor textContainer] rectCount:&count];

        [[NSColor alternateSelectedControlColor] set];
        for (NSUInteger i = 0; i < count; i++)
        {
            NSRectFill(rects[i]);
        }
  */
        NSRect  selRect;


        selRect.origin = NSZeroPoint;          // Unnecessary but added to shut up the static analyzer
        selRect.size = [_textCell cellSizeForBounds:rect];
        selRect.size.height += 1.0;
        selRect.size.width += 12.0;
        selRect.origin.x = NSMinX(rect) + (NSWidth(rect) - NSWidth(selRect)) / 2;
        selRect.origin.y = NSMaxY(rect) - NSHeight(selRect);
        
        if ([[self window] isKeyWindow])
        {
            selectionColor = [NSColor alternateSelectedControlColor];
        }
        
        [selectionColor set];

        [[NSBezierPath bezierPathWithRoundedRect:selRect xRadius:SELECTION_RADIUS yRadius:SELECTION_RADIUS] fill];
        [_textCell setTextColor:[NSColor whiteColor]];
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
    
    item = [self item];

    if ([item isEnabled])
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

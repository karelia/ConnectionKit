//
//  CK2BrowserPreviewView.m
//  Connection
//
//  Created by Paul Kim on 1/18/13.
//
//

#import "CK2BrowserPreviewView.h"
#import "NSURL+CK2OpenPanel.h"

#define MARGIN                  24.0
#define LABELS_TOP_MARGIN       10.0
#define LABELS_LEFT_MARGIN      20.0
#define LABELS_RIGHT_MARGIN     10.0

@implementation CK2BrowserPreviewView

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_separatorGradient release];
    
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (_separatorGradient == nil)
    {
        _separatorGradient = [[NSGradient alloc] initWithColorsAndLocations:
                              [NSColor colorWithCalibratedWhite:1.0 alpha:0.0],
                              0.0,
                              [NSColor colorWithCalibratedWhite:0.83 alpha:1.0],
                              0.25,
                              [NSColor colorWithCalibratedWhite:0.83 alpha:1.0],
                              0.75,
                              [NSColor colorWithCalibratedWhite:1.0 alpha:0.0],
                              1.0,
                              nil];
    }
    
    [_separatorGradient drawInRect:_separatorRect angle:0.0];
}

- (void)setURL:(NSURL *)url
{
    if (url != nil)
    {
     [_iconView setObjectValue:[url ck2_icon]];
     [_nameField setStringValue:[url ck2_displayName]];
     [_sizeField setObjectValue:[url ck2_size]];
     [_kindField setStringValue:[url ck2_kind]];
     [_dateModifiedField setObjectValue:[url ck2_dateModified]];
    }
    else
    {
        [_iconView setObjectValue:nil];
        [_nameField setStringValue:@""];
        [_sizeField setObjectValue:@""];
        [_kindField setStringValue:@""];
        [_dateModifiedField setObjectValue:@""];
    }
}


- (void)setFrame:(NSRect)frameRect
{
    [super setFrame:frameRect];
    
    [self tile];
}

- (void)tileLabelField:(NSTextField *)labelField valueField:(NSTextField *)valueField
{
    NSRect  bounds, rect;
    CGFloat xSep;
    
    bounds = [self bounds];
    xSep = NSWidth(bounds) * .4;
    
    rect = [labelField frame];
    rect.origin.x = MAX(xSep - NSWidth(rect), LABELS_LEFT_MARGIN);
    [labelField setFrame:rect];
    
    rect = [valueField frame];
    rect.origin.x = xSep;
    rect.size.width = NSMaxX(bounds) - LABELS_RIGHT_MARGIN - rect.origin.x;
    [valueField setFrame:rect];
}

- (void)tileLabels
{
    NSRect      rect;
    NSSize      size;
    CGFloat     y, height;

    [self tileLabelField:_dateModifiedLabel valueField:_dateModifiedField];
    [self tileLabelField:_sizeLabel valueField:_sizeField];
    [self tileLabelField:_kindLabel valueField:_kindField];
    [self tileLabelField:_nameLabel valueField:_nameField];
    
    // Allow name field to take multiple lines (up to 3)
    height = NSHeight([_nameLabel frame]);
    
    rect = [_nameField frame];
    rect.size.height = CGFLOAT_MAX;
    size = [[_nameField cell] cellSizeForBounds:rect];
    rect.size.height = MAX(size.height, height);
    rect.size.height = MIN(rect.size.height, 3 * height);
    [_nameField setFrame:rect];
    
    y = NSMaxY(rect);
    rect = [_nameLabel frame];
    rect.origin.y = y - NSHeight(rect);
    [_nameLabel setFrame:rect];
}

- (void)tile
{
    NSRect  bounds, iconFrame;
    
    bounds = [self bounds];
    
    [self tileLabels];

    _separatorRect.size.width = NSWidth(bounds) * .8;
    _separatorRect.size.height = 1.0;
    _separatorRect.origin.x = NSMinX(bounds) + (NSWidth(bounds) - NSWidth(_separatorRect)) / 2.0;
    _separatorRect.origin.y = NSMaxY([_nameLabel frame]) + LABELS_TOP_MARGIN;

    iconFrame.origin = NSZeroPoint;     // Unnecessary but added to shut up the static analyzer
    iconFrame.size.width = MIN(NSWidth(bounds) - 2 * MARGIN, NSHeight(bounds) - NSMaxY(_separatorRect) - 2 * MARGIN);
    iconFrame.size.height = NSWidth(iconFrame);
    iconFrame.origin.x = NSMinX(bounds) + (NSWidth(bounds) - NSWidth(iconFrame)) / 2.0;
    iconFrame.origin.y = NSMaxY(_separatorRect) + MARGIN;
    
    [_iconView setFrame:iconFrame];
    
    [self setNeedsDisplay:YES];
}

- (void)superviewFrameChanged:(NSNotification *)notification
{
    [self setFrame:[[self superview] bounds]];
}

- (void)removeFromSuperview
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:[self superview]];
    
    [super removeFromSuperview];
}

- (void)viewDidMoveToSuperview
{
    NSView      *superview;
    
    superview = [self superview];
    if (superview != nil)
    {
        [superview setPostsFrameChangedNotifications:YES];
    
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(superviewFrameChanged:) name:NSViewFrameDidChangeNotification object:superview];
    
        [self superviewFrameChanged:nil];
    }
}

@end

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
    
    [super dealloc];
}

- (void)setURL:(NSURL *)url
{
    if (url != nil)
    {
     [_iconView setObjectValue:[url icon]];
     [_nameField setStringValue:[url displayName]];
     [_sizeField setObjectValue:[url size]];
     [_kindField setStringValue:[url kind]];
     [_dateModifiedField setObjectValue:[url dateModified]];
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
    NSRect      rect, bounds;
    NSSize      size;
    CGFloat     y, height;

    rect = [_labelBox frame];
    bounds = [self bounds];
    rect.size.width = NSWidth(bounds);
    [_labelBox setFrame:rect];
    
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

    rect = [_labelBox frame];
    rect.size.height = y + LABELS_TOP_MARGIN;
    rect.origin.y = 0.0;
    [_labelBox setFrame:rect];
}

- (void)tile
{
    NSRect  bounds, separatorRect, iconFrame;
    
    bounds = [self bounds];
    
    [self tileLabels];
    separatorRect = [_separator frame];
    
    separatorRect.origin.x = NSMinX(bounds) + (NSWidth(bounds) - NSWidth(separatorRect)) / 2.0;
    separatorRect.origin.y = NSMaxY([_nameLabel frame]);
    [_separator setFrame:separatorRect];
    
    iconFrame.size.width = MIN(NSWidth(bounds) - 2 * MARGIN, NSHeight(bounds) - NSMaxY(separatorRect) - 2 * MARGIN);
    iconFrame.size.height = iconFrame.size.width;
    iconFrame.origin.x = NSMinX(bounds) + (NSWidth(bounds) - NSWidth(iconFrame)) / 2.0;
    iconFrame.origin.y = NSMaxY(separatorRect) + MARGIN;
    
    [_iconView setFrame:iconFrame];
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

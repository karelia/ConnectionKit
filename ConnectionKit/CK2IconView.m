//
//  CK2IconView.m
//  Connection
//
//  Created by Paul Kim on 1/17/13.
//
//

#import "CK2IconView.h"
#import "NSURL+CK2OpenPanel.h"

@implementation CK2IconView

@synthesize messageMode = _messageMode;

- (id)initWithFrame:(NSRect)frame
{
    if (self = [super initWithFrame:frame])
    {
        [self initNotifications];
    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if ([_typeSelectTimer isValid])
    {
        [_typeSelectTimer invalidate];
        [_typeSelectTimer release];
    }
    [_typeSelectBuffer release];
    
    [super dealloc];
}

- (void)initNotifications
{
    // Tried doing this by overriding setFrame: but it seems to cause spastic behavior. Seems to work more smoothly
    // when done this way.
    [self setPostsFrameChangedNotifications:YES];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tile) name:NSViewFrameDidChangeNotification object:self];
}

- (void)awakeFromNib
{
    [self initNotifications];
}

- (void)setMessageMode:(BOOL)messageMode
{
    _messageMode = messageMode;
    [self tile];
}

- (void)setContent:(NSArray *)content
{
    [super setContent:content];
    [self tile];
}

- (void)tile
{
    NSRect    bounds;
    
    bounds = [self bounds];
    if (_messageMode)
    {
        [self setMinItemSize:bounds.size];
        [self setMaxItemSize:bounds.size];
    }
    else
    {
        NSUInteger  colCount;
        CGFloat     calcWidth;
        NSSize      size, minSize;
        
        // NSCollectionView tends to align things towards the left. We want the icons to be evenly distributed so we
        // set the minimum width of each item to force such a layout.

        minSize = [[[self itemPrototype] view] frame].size;
        
        colCount = NSWidth(bounds) / minSize.width;
        calcWidth = floor(NSWidth(bounds) / colCount);
        
        [self setMaxNumberOfColumns:colCount];
        
        size = NSMakeSize(MIN(calcWidth, minSize.width), minSize.height);
        [self setMinItemSize:size];
        // Setting the max size gets rid of odd scroller behavior
        [self setMaxItemSize:size];
    }
}

- (void)resetTypeSelectTimer
{
    if ([_typeSelectTimer isValid])
    {
        [_typeSelectTimer invalidate];
        [_typeSelectTimer release];
    }
    
    // You have to type the name within a short period of time otherwise it resets. We use -keyRepeatDelay as that
    // seems like a reasonable match. May have to do some experimentation to find out what the delay really is (and
    // if it correlates to any existing settings).
    _typeSelectTimer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:[NSEvent keyRepeatDelay]] interval:0 target:self selector:@selector(clearTypeSelectBuffer:) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:_typeSelectTimer forMode:NSRunLoopCommonModes];
}

- (void)clearTypeSelectBuffer:(id)sender
{
    if ([sender isKindOfClass:[NSTimer class]])
    {
        [_typeSelectTimer invalidate];
        [_typeSelectTimer release];
        _typeSelectTimer = nil;
    }
    [_typeSelectBuffer setString:@""];
}

- (void)keyDown:(NSEvent *)event
{
    if ([event type] == NSKeyDown)
    {
        NSString    *string;
        NSUInteger  flags;
        
        string = [event characters];
        flags = [event modifierFlags] & NSDeviceIndependentModifierFlagsMask;
        
        if (([string isEqual:@"/"] || [string isEqual:@"~"]) && ((flags & NSCommandKeyMask) == 0))
        {
            // Let the window handle it
            [[self nextResponder] keyDown:event];
            return;
        }
    }
    [super keyDown:event];
}

- (void)insertText:(id)aString
{
    NSUInteger      i;
    NSArray         *urls;
    
    if (_typeSelectBuffer == nil)
    {
        _typeSelectBuffer = [[NSMutableString alloc] init];
    }
    
    if ([_typeSelectBuffer length] == 0)
    {
        [self resetTypeSelectTimer];
    }
    
    [_typeSelectBuffer appendString:aString];
    urls = [self content];

    i = [urls indexOfObject:_typeSelectBuffer inSortedRange:NSMakeRange(0, [urls count]) options:NSBinarySearchingInsertionIndex | NSBinarySearchingFirstEqual usingComparator:
         ^ NSComparisonResult (id obj1, id obj2)
         {
             NSString    *string1, *string2;
             
             string1 = obj1;
             if ([obj1 isKindOfClass:[NSURL class]])
             {
                 string1 = [obj1 ck2_displayName];
             }
             string2 = obj2;
             if ([obj2 isKindOfClass:[NSURL class]])
             {
                 string2 = [obj2 ck2_displayName];
             }
             
             return [string1 caseInsensitiveCompare:string2];
         }];
    
    if (i == NSNotFound)
    {
        NSBeep();
    }
    else
    {
        [self setSelectionIndexes:[NSIndexSet indexSetWithIndex:i]];
        [self scrollRectToVisible:[self frameForItemAtIndex:i]];
    }
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    NSWindow            *window;
    
    window = [self window];
    
    if (window != nil)
    {
        NSNotificationCenter    *notificationCenter;

        notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter removeObserver:self name:NSWindowDidBecomeKeyNotification object:window];
        [notificationCenter removeObserver:self name:NSWindowDidResignKeyNotification object:window];
    }
}

- (void)viewDidMoveToWindow
{
    NSWindow                *window;
    
    window = [self window];

    if (window != nil)
    {
        NSNotificationCenter    *notificationCenter;
        
        notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self selector:@selector(windowDidBecomeKey:) name:NSWindowDidBecomeKeyNotification object:window];
        [notificationCenter addObserver:self selector:@selector(windowDidResignKey:) name:NSWindowDidResignKeyNotification object:window];
    }
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    [self setNeedsDisplay:YES];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    [self setNeedsDisplay:YES];
}


@end

/*
 This class is based on FileSystemBrowserCell. The original version of
 which can be found here:
 http://developer.apple.com/library/mac/#samplecode/ComplexBrowser/Listings/FileSystemBrowserCell_m.html
 
 The original code falls under the copyright and license specified
 there.
 
 
 Modifications to the code for this project fall under the following
 license:
 
 Copyright (c) 2013, Karelia Software
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or other
 materials provided with the distribution.
 
 Neither the name of Karelia Software nor the names of its contributors may be used to
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

#import "CK2FileCell.h"

@implementation CK2FileCell

#define ICON_SIZE 		16.0	// Our Icons are ICON_SIZE x ICON_SIZE 
#define ICON_INSET_HORIZ	4.0     // Distance to inset the icon from the left edge. 
#define ICON_TEXT_SPACING	2.0     // Distance between the end of the icon and the text part 
#define ICON_INSET_VERT         2.0     // Distance from top/bottom of icon

- (id)init {
    self = [super init];
    [self setLineBreakMode:NSLineBreakByTruncatingMiddle];
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    CK2FileCell *result = [super copyWithZone:zone];
    result->_image = nil;
    result.image = self.image;
    result->_labelColor = nil;
    result.labelColor = self.labelColor;
    return result;
}

- (void)dealloc {
    [_image release];
    [_labelColor release];
    [super dealloc];
}

@synthesize image = _image;
@synthesize labelColor = _labelColor;
@synthesize textOnly = _isTextOnly;


- (void)setTextOnly:(BOOL)flag
{
    _isTextOnly = flag;
    if (_isTextOnly)
    {
        [self setLineBreakMode:NSLineBreakByTruncatingTail];
    }
    else
    {
        [self setLineBreakMode:NSLineBreakByTruncatingMiddle];
    }
}


- (NSRect)imageRectForBounds:(NSRect)bounds {
    bounds.origin.x += ICON_INSET_HORIZ;
    bounds.size.width = ICON_SIZE;
    bounds.origin.y += trunc((bounds.size.height - ICON_SIZE) / 2.0); 
    bounds.size.height = ICON_SIZE;
    return bounds;
}

- (NSRect)titleRectForBounds:(NSRect)bounds {
    if (!_isTextOnly)
    {
        // Inset the title for the image
        CGFloat inset = (ICON_INSET_HORIZ + ICON_SIZE + ICON_TEXT_SPACING);
        bounds.origin.x += inset;
        bounds.size.width -= inset;
    }
    return [super titleRectForBounds:bounds];
}

- (NSSize)cellSizeForBounds:(NSRect)aRect {
    // Make our cells a bit higher than normal to give some additional space for the icon to fit.
    NSSize theSize = [super cellSizeForBounds:aRect];
    theSize.width += (ICON_INSET_HORIZ + ICON_SIZE + ICON_TEXT_SPACING);
    theSize.height = ICON_INSET_VERT + ICON_SIZE + ICON_INSET_VERT;
    return theSize;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    // First draw a label background color
    if (self.labelColor != nil) {
        [[self.labelColor colorWithAlphaComponent:0.2] set];
        NSRectFillUsingOperation(cellFrame, NSCompositeSourceOver);
    }
    
    if (!_isTextOnly)
    {
        NSRect imageRect = [self imageRectForBounds:cellFrame];
        
        [self.image drawInRect:imageRect
                      fromRect:NSZeroRect
                     operation:NSCompositeSourceOver
                      fraction:1.0
                respectFlipped:YES
                         hints:nil];
        
        CGFloat inset = (ICON_INSET_HORIZ + ICON_SIZE + ICON_TEXT_SPACING);
        cellFrame.origin.x += inset;
        cellFrame.size.width -= inset;
    }
    cellFrame.origin.y += 1; // Looks better
    cellFrame.size.height -= 1;
    [super drawInteriorWithFrame:cellFrame inView:controlView];
}

- (void)drawWithExpansionFrame:(NSRect)cellFrame inView:(NSView *)view {
    // We want to exclude the icon from the expansion frame when you hover over the cell
    [super drawInteriorWithFrame:cellFrame inView:view];
}

@end

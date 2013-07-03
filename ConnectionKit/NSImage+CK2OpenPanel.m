//
//  NSImage+NSImage_CK2OpenPanel.m
//  Connection
//
//  Created by Paul Kim on 1/27/13.
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


#import "NSImage+CK2OpenPanel.h"

@class CK2BlockImageRep;

@interface CK2BlockImageRep : NSImageRep
{
    void           (^_drawBlock)(CK2BlockImageRep *);
}

@property (readwrite, copy) void    (^drawBlock)(CK2BlockImageRep *rep);

+ (id)imageRepWithDrawBlock:(void (^)(CK2BlockImageRep *))block;

- (id)initWithDrawBlock:(void (^)(CK2BlockImageRep *))block;

@end


@implementation CK2BlockImageRep

@synthesize drawBlock = _drawBlock;

+ (id)imageRepWithDrawBlock:(void (^)(CK2BlockImageRep *))block
{
    return [[[[self class] alloc] initWithDrawBlock:block] autorelease];
}

- (id)initWithDrawBlock:(void (^)(CK2BlockImageRep *))block
{
    if ((self = [super init]) != nil)
    {
        [self setDrawBlock:block];
    }
    return self;
}

#pragma mark NSCopying method

- (id)copyWithZone:(NSZone *)zone
{
	CK2BlockImageRep	*copy;
    
	copy = [super copyWithZone:zone];
    
    // NSImageRep uses NSCopyObject so we have to force a copy here (which actually
    // just retains the object in this case).
    copy->_drawBlock = [_drawBlock copy];
	
	return copy;
}

- (void)dealloc
{
    [self setDrawBlock:nil];
    
    [super dealloc];
}

#pragma mark NSImageRep methods

- (BOOL)draw
{
    if (_drawBlock != NULL)
    {
        _drawBlock(self);
        
        return YES;
    }
    return NO;
}

@end


@implementation NSImage (CK2OpenPanel)

+ (id)ck2_imageWithSize:(NSSize)size usingDrawBlock:(void (^)(CK2BlockImageRep *))block
{
    return [[[[self class] alloc] initCK2WithSize:size usingDrawBlock:block] autorelease];
}

// Using the CK2 prefix for -init methods confuses the static analyzer so it's buried within the method name here
- (id)initCK2WithSize:(NSSize)size usingDrawBlock:(void (^)(CK2BlockImageRep *))block
{
    if ((self = [self initWithSize:size]) != nil)
    {
        CK2BlockImageRep        *rep;
        
        rep = [CK2BlockImageRep imageRepWithDrawBlock:block];
        [rep setSize:size];
        [self addRepresentation:rep];
    }
    return self;
}

- (NSImage *)ck2_imageWithBadgeImage:(NSImage *)badgeImage
{
    NSImage                 *image;
	
    image = [[self copy] autorelease];
    
    return [NSImage ck2_imageWithSize:[self size] usingDrawBlock:
            ^(CK2BlockImageRep *blockRep)
            {
                NSRect  rect;
                
                [image drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
               
                rect.origin = NSZeroPoint;
                rect.size = [blockRep size];
                [badgeImage drawInRect:rect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
            }];
}



@end


//
//  CK2IconViewItem.m
//  ConnectionKit
//
//  Created by Paul Kim on 12/19/12.
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

#import "CK2IconViewItem.h"
#import "CK2IconItemView.h"

@interface CK2IconViewItem ()

@end

@implementation CK2IconViewItem

@synthesize target = _target;
@synthesize action = _action;
@synthesize doubleAction = _doubleAction;
@synthesize enabled = _isEnabled;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) != nil)
    {
        [self setEnabled:YES];
    }
    
    return self;
}

- (void)dealloc
{
    [(CK2IconItemView *)[self view] setItem:nil];
    [super dealloc];
}

- (void)setView:(NSView *)view
{
    [super setView:view];
    
    [(CK2IconItemView *)[self view] setItem:self];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    CK2IconViewItem     *copy;
    
    copy = [super copyWithZone:zone];
    [copy setTarget:[self target]];
    [copy setAction:[self action]];
    [copy setDoubleAction:[self doubleAction]];
    
    return copy;
}

#pragma mark NSCoding

#define TARGET_KEY          @"target"
#define ACTION_KEY          @"action"
#define DOUBLE_ACTION_KEY   @"doubleAction"
#define ENABLED_ACTION_KEY  @"enabled"

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if ((self = [super initWithCoder:aDecoder]) != nil)
    {
        [self setTarget:[aDecoder decodeObjectForKey:TARGET_KEY]];
        [self setAction:NSSelectorFromString([aDecoder decodeObjectForKey:ACTION_KEY])];
        [self setDoubleAction:NSSelectorFromString([aDecoder decodeObjectForKey:DOUBLE_ACTION_KEY])];
        [self setEnabled:[aDecoder decodeBoolForKey:ENABLED_ACTION_KEY]];        
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [super encodeWithCoder:aCoder];
    
    [aCoder encodeObject:[self target] forKey:TARGET_KEY];
    [aCoder encodeObject:NSStringFromSelector([self action]) forKey:ACTION_KEY];
    [aCoder encodeObject:NSStringFromSelector([self doubleAction]) forKey:DOUBLE_ACTION_KEY];
    [aCoder encodeBool:[self isEnabled] forKey:ENABLED_ACTION_KEY];
}

@end

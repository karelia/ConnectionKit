//
//  CKFileInfo.m
//  ConnectionKit
//
//  Created by Mike on 25/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFileInfo.h"


@implementation CKFileInfo

#pragma mark Init & Dealloc

- (id)initWithFilename:(NSString *)filename attributes:(NSDictionary *)attributes
{
    [self init];
    
    _filename = [filename copy];
    _attributes = [attributes copy];
    
    return self;
}

- (id)initWithDirectoryContents:(NSArray *)directoryContents
{
    [self init];
    
    _directoryContents = [directoryContents copy];
    
    return self;
}

- (void)dealloc
{
    [_filename release];
    [_directoryContents release];
    [_attributes release];
    
    [super dealloc];
}

#pragma mark Properties

@synthesize filename = _filename;
@synthesize directoryContents = _directoryContents;
@synthesize fileAttributes = _attributes;

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];   // immutable object
}

@end

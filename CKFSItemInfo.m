//
//  CKFSItemInfo.m
//  ConnectionKit
//
//  Created by Mike on 25/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFSItemInfo.h"


@interface CKFSItemInfo ()
- (void)CK_setFilename:(NSString *)filename;
- (void)CK_setDirectoryContents:(NSArray *)contents;
- (void)CK_setFileAttributes:(NSDictionary *)attributes;
@end



@implementation CKFSItemInfo

#pragma mark Init & Dealloc

+ (id)infoWithFilename:(NSString *)filename
{
    return [[[self alloc] initWithFilename:filename attributes:nil] autorelease];
}

+ (id)infoWithFileAttributes:(NSDictionary *)attributes;
{
    return [[[self alloc] initWithFilename:nil attributes:attributes] autorelease];
}

+ (id)infoWithDirectoryContents:(NSArray *)contents
{
    return [[[self alloc] initWithDirectoryContents:contents] autorelease];
}

+ (id)infoWithFilenames:(NSArray *)filenames
{
    NSMutableArray *contents = [[NSMutableArray alloc] initWithCapacity:[filenames count]];
    for (NSString *aFilename in filenames)
    {
        CKFSItemInfo *item = [[CKFSItemInfo alloc] initWithFilename:aFilename attributes:nil];
        [contents addObject:item];
        [item release];
    }
    return [self infoWithDirectoryContents:contents];
}

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
    [self CK_setDirectoryContents:directoryContents];
    return self;
}

- (id)initWithItemInfo:(CKFSItemInfo *)item;
{
    [self init];
    
    _filename = [[item filename] copy];
    [self CK_setDirectoryContents:[item directoryContents]];
    [self CK_setFileAttributes:[item fileAttributes]];
    
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

- (void)CK_setFilename:(NSString *)filename
{
    filename = [filename copy];
    [_filename release];
    _filename = filename;
}

@synthesize directoryContents = _directoryContents;

- (void)CK_setDirectoryContents:(NSArray *)contents
{
    contents = [[NSArray alloc] initWithArray:contents copyItems:YES];
    [_directoryContents release];
    _directoryContents = contents;
}

@synthesize fileAttributes = _attributes;

- (void)CK_setFileAttributes:(NSDictionary *)attributes
{
    attributes = [[NSDictionary alloc] initWithDictionary:attributes copyItems:YES];
    [_attributes release];
    _attributes = attributes;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];   // immutable object
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
    return [[CKMutableFSItemInfo alloc] initWithItemInfo:self];
}

@end


#pragma mark -


@implementation CKMutableFSItemInfo

@dynamic filename;
- (void)setFilename:(NSString *)filename
{
    [self CK_setFilename:filename];
}

- (void)addDirectoryContentsItem:(CKFSItemInfo *)item
{
    NSMutableArray *contents = [[self directoryContents] mutableCopy];
    if (contents)
    {
        [contents addObject:item];
    }
    else
    {
        contents = [[NSMutableArray alloc] initWithObjects:item, nil];
    }
    
    [self CK_setDirectoryContents:contents];
    [contents release];
}

- (void)setValue:(id)attribute forFileAttribute:(NSString *)key;
{
    NSMutableDictionary *attributes = [[self fileAttributes] mutableCopy];
    if (!attribute) attribute = [[NSMutableDictionary alloc] init];
    
    [attributes setObject:attribute forKey:key];
    [self CK_setFileAttributes:attributes];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[[self class] alloc] initWithItemInfo:self];
}

@end


//
//  CKFSItemInfo.h
//  ConnectionKit
//
//  Created by Mike on 25/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface CKFSItemInfo : NSObject <NSCopying, NSMutableCopying>
{
  @private
    NSString        *_filename;
    NSArray         *_directoryContents;
    NSDictionary    *_attributes;
}

- (id)initWithFilename:(NSString *)filename attributes:(NSDictionary *)attributes;
- (id)initWithDirectoryContents:(NSArray *)directoryContents;
- (id)initWithItemInfo:(CKFSItemInfo *)item;

@property(nonatomic, copy, readonly) NSString *filename;
@property(nonatomic, copy, readonly) NSArray *directoryContents;
@property(nonatomic, copy, readonly) NSDictionary *fileAttributes;

@end


@interface CKMutableFSItemInfo : CKFSItemInfo

@property(nonatomic, copy, readwrite) NSString *filename;
- (void)addDirectoryContentsItem:(CKFSItemInfo *)item;
- (void)setValue:(id)attribute forFileAttribute:(NSString *)key;

@end
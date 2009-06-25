//
//  CKFileInfo.h
//  ConnectionKit
//
//  Created by Mike on 25/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface CKFileInfo : NSObject <NSCopying>
{
  @private
    NSString        *_filename;
    NSArray         *_directoryContents;
    NSDictionary    *_attributes;
}

- (id)initWithFilename:(NSString *)filename attributes:(NSDictionary *)attributes;
- (id)initWithDirectoryContents:(NSArray *)directoryContents;

@property(nonatomic, copy, readonly) NSString *filename;
@property(nonatomic, copy, readonly) NSArray *directoryContents;
@property(nonatomic, copy, readonly) NSDictionary *fileAttributes;

@end

//
//  CK_AmazonS3BucketInfoParser.h
//  S3MacFUSE
//
//  Created by Mike on 23/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@class CKFSItemInfo, CKMutableFSItemInfo;


@interface CK_AmazonS3BucketInfoParser : NSObject
{
  @private
    CKMutableFSItemInfo *_result;
    CKMutableFSItemInfo *_itemInProgress;
    
    NSMutableArray  *_keysInProgress;
    NSMutableString *_textInProgress;
}

- (CKFSItemInfo *)parseData:(NSData *)data;

@end

//
//  CK_AmazonS3Parser.h
//  S3MacFUSE
//
//  Created by Mike on 23/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@class CKFileInfo;


@interface CK_AmazonS3ServiceInfoParser : NSObject
{
    NSMutableArray      *_directoryContents;
    NSString            *_filenameInProgress;
    NSMutableDictionary *_attributesInProgress;
    
    NSMutableArray  *_keysInProgress;
    NSMutableString *_textInProgress;
}

- (CKFileInfo *)parseData:(NSData *)data;

@end

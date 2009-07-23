//
//  CK_AmazonS3BucketInfoParser.m
//  S3MacFUSE
//
//  Created by Mike on 23/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CK_AmazonS3BucketInfoParser.h"

#import "CKFSItemInfo.h"


@implementation CK_AmazonS3BucketInfoParser

static NSArray *bucketContentsKeys;

+ (void)initialize
{
    if (!bucketContentsKeys)
    {
        bucketContentsKeys = [[NSArray alloc] initWithObjects:
                              @"ListBucketResult",
                              @"Contents",
                              nil];
    }
}

- (CKFSItemInfo *)parseData:(NSData *)data;
{
    _result = [[CKMutableFSItemInfo alloc] init];
    _keysInProgress = [[NSMutableArray alloc] initWithCapacity:4];
    
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    [parser setDelegate:self];
    
    CKFSItemInfo *result = nil;
    if ([parser parse]) result = [[_result copy] autorelease];
    
    [_result release], _result = nil;
    [_keysInProgress release], _keysInProgress = nil;
    
    return result;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary *)attributeDict
{
    [_keysInProgress addObject:elementName];
    
    if ([_keysInProgress isEqualToArray:bucketContentsKeys])
    {
        _itemInProgress = [[CKMutableFSItemInfo alloc] init];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if ([_keysInProgress count] == 2 &&
        [[_keysInProgress objectAtIndex:0] isEqualToString:@"ListBucketResult"] &&
        [elementName isEqualToString:@"Name"])
    {
        [_result setFilename:_textInProgress];
    }
    else if (_itemInProgress)
    {
        if ([elementName isEqualToString:@"Contents"])
        {
            [_result addDirectoryContentsItem:_itemInProgress];
            [_itemInProgress release], _itemInProgress = nil;
        }
        else
        {
            if ([elementName isEqualToString:@"Key"])
            {
                [_itemInProgress setFilename:_textInProgress];
            }
            else if ([elementName isEqualToString:@"LastModified"])
            {
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                [formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
                [formatter setTimeStyle:NSDateFormatterFullStyle];
                [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSzzz"];
                
                NSString *dateString = _textInProgress; // account for timezone-less dates
                if ([dateString hasSuffix:@"Z"])
                {
                    dateString = [[dateString substringToIndex:dateString.length-1]
                                  stringByAppendingString:@"GMT"];
                }
                
                NSDate *date = [formatter dateFromString:dateString];
                [_itemInProgress setValue:date forFileAttribute:NSFileModificationDate];
                [formatter release];
            }
            else if ([elementName isEqualToString:@"Size"])
            {
                NSNumber *size = [NSNumber numberWithLongLong:[_textInProgress longLongValue]];
                [_itemInProgress setValue:size forFileAttribute:NSFileSize];
            }
        }
    }
    
    
    [_textInProgress release],  _textInProgress = nil;
    [_keysInProgress removeLastObject];
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if (_textInProgress)
    {
        [_textInProgress appendString:string];
    }
    else
    {
        _textInProgress = [[NSMutableString alloc] initWithString:string];
    }
}

@end

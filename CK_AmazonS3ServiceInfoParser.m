//
//  CK_AmazonS3Parser.m
//  S3MacFUSE
//
//  Created by Mike on 23/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CK_AmazonS3ServiceInfoParser.h"

#import "CKFileInfo.h"


@implementation CK_AmazonS3ServiceInfoParser

- (CKFileInfo *)parseData:(NSData *)data;
{
    _directoryContents = [[NSMutableArray alloc] init];
    _keysInProgress = [[NSMutableArray alloc] initWithCapacity:4];
    
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    [parser setDelegate:self];
    if (![parser parse])
    {
        [_directoryContents release], _directoryContents = nil;
    }
    
    CKFileInfo *result = [[CKFileInfo alloc] initWithDirectoryContents:_directoryContents];
    
    [_directoryContents release];
    [_keysInProgress release];
    
    return [result autorelease];
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary *)attributeDict
{
    [_keysInProgress addObject:elementName];
    
    if ([_keysInProgress count] >= 3)
    {
        _attributesInProgress = [[NSMutableDictionary alloc] init];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if ([_keysInProgress count] >= 3)
    {
        NSString *item = [_keysInProgress objectAtIndex:([_keysInProgress count] - 2)];
        
        if ([elementName isEqualToString:@"Bucket"])
        {
            CKFileInfo *info = [[CKFileInfo alloc] initWithFilename:_filenameInProgress
                                                         attributes:_attributesInProgress];
            [_filenameInProgress release], _filenameInProgress = nil;
            [_attributesInProgress release], _attributesInProgress = nil;
            
            [_directoryContents addObject:info];
            [info release];
        }
        else if ([item isEqualToString:@"Bucket"])
        {
            if ([elementName isEqualToString:@"Name"])
            {
                _filenameInProgress = [_textInProgress copy];
            }
            else if ([elementName isEqualToString:@"CreationDate"])
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
                [_attributesInProgress setObject:date forKey:NSFileCreationDate];
                [formatter release];
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

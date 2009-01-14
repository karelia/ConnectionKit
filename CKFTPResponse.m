//
//  CKFTPResponse.m
//  Connection
//
//  Created by Mike on 13/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFTPResponse.h"


@implementation CKFTPResponse

#pragma mark -
#pragma mark Init & Dealloc

static NSCharacterSet *sNewlineCharacterSet;
+ (void)initialize
{
    if (!sNewlineCharacterSet)
    {
        sNewlineCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@"\n\r"] retain];
    }
}

- (id)initWithLines:(NSArray *)responseLines
{
    NSParameterAssert(responseLines);
    NSParameterAssert([responseLines count] > 0);
    
    [super init];
    
    
    
    // To be valid, the first line must be of the form "100 " or "100-"
    NSString *firstLine = [responseLines objectAtIndex:0];
    if ([firstLine length] >= 4)
    {
        unichar character = [firstLine characterAtIndex:3];
        if (character == ' ' || (_isMark = (character == '-')))
        {
            // Now look for a valid response code
            NSScanner *scanner = [[NSScanner alloc] initWithString:firstLine];
            [scanner scanInt:&_code];
            [scanner release];
            
            if (_code >= 100 && _code < 600)
            {
                _lines = [responseLines copy];
                
                
                
                // But, if the first line is a mark, the return code may change by the end due to some error
                if (_isMark && [[self lines] count] > 1)
                {
                    NSString *lastResponseLine = [[self lines] lastObject];
                    NSRange searchRange = NSMakeRange(0, [lastResponseLine length]);
                    
                    // Ignore any trailing new lines
                    while ([lastResponseLine rangeOfCharacterFromSet:sNewlineCharacterSet
                                                             options:(NSBackwardsSearch | NSAnchoredSearch)
                                                               range:searchRange].location != NSNotFound)
                    {
                        searchRange.length -= 1;
                    }
                    
                    // Search back to the the newline that hopefully precedes the response code
                    searchRange = [lastResponseLine rangeOfCharacterFromSet:sNewlineCharacterSet
                                                                    options:NSBackwardsSearch
                                                                      range:searchRange];
                    
                    NSUInteger searchIndex = (searchRange.location == NSNotFound) ? 0 : (searchRange.location + 1);
                    
                    // Look for a valid response code
                    if ([lastResponseLine length] >= (searchIndex + 4) &&
                        [lastResponseLine characterAtIndex:(searchIndex + 3)] == ' ')
                    {
                        NSScanner *scanner = [[NSScanner alloc] initWithString:lastResponseLine];
                        [scanner setScanLocation:searchIndex];
                        
                        int code;
                        if ([scanner scanInt:&code] && code >= 100 && code < 600)
                        {
                            _code = code;
                            _isMark = NO;
                        }
                        [scanner release];
                    }
                }
                
                
                return self;
            }
        }
    }
    
    
    // Control reaches this point if there was a parse error
    [self release];
    return nil;
}

- (id)initWithString:(NSString *)responseString
{
    NSArray *lines = [[NSArray alloc] initWithObjects:responseString, nil];
    self = [self initWithLines:lines];
    [lines release];
    return self;
}

- (id)init
{
    // Stops anyone calling this method by mistake
    return [self initWithLines:nil];
}

- (void)dealloc
{
    [_lines release];
    [super dealloc];
}

#pragma mark -
#pragma mark Copy

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];   // We're immutable
}

#pragma mark -
#pragma mark Accessors

- (unsigned)code { return _code; }

- (NSArray *)lines { return _lines; }

- (BOOL)isMark { return _isMark; }

@end


//
//  CKFTPResponse.m
//  Connection
//
//  Created by Mike on 13/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFTPResponse.h"


@implementation CKFTPResponse

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
        if (character == ' ' || character == '-')
        {
            // Now look for a valid response code
            NSScanner *scanner = [[NSScanner alloc] initWithString:firstLine];
            [scanner scanInt:&_code];
            [scanner release];
            
            if (_code >= 100 && _code < 600)
            {
                _lines = [responseLines copy];
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

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];   // We're immutable
}

- (unsigned)code { return _code; }

- (NSArray *)lines { return _lines; }

- (BOOL)isMark
{
    // To be a mark, the first line has to be of the form "100-" and the last line NOT "100 "
    NSString *firstResponseLine = [[self lines] objectAtIndex:0];
    BOOL result = ([firstResponseLine characterAtIndex:3] == '-');  // -init… already checked the string is long enough etc.
    if (result)
    {
        NSString *lastResponseLine = [[self lines] lastObject];
        if ([lastResponseLine length] >= 4 && [lastResponseLine characterAtIndex:3] == ' ')
        {
            NSScanner *scanner = [[NSScanner alloc] initWithString:lastResponseLine];
            
            int responseCode;
            if ([scanner scanInt:&responseCode])
            {
                result = (responseCode != [self code]);
            }
            
            [scanner release];
        }
    }
    
    return result;
}

@end


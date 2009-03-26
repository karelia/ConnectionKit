//
//  CKFTPRequest.m
//  Connection
//
//  Created by Mike on 24/03/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFTPCommand.h"


@implementation CKFTPCommand

+ (NSCharacterSet *)FTPCommandCodeCharacters
{
    static NSCharacterSet *result = nil;
    if (!result)
    {
        result = [NSCharacterSet characterSetWithCharactersInString:
                  @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
        [result retain];
    }
    
    return result;
}

#pragma mark -
#pragma mark Init

+ (CKFTPCommand *)commandWithCode:(NSString *)code argumentField:(NSString *)argumentField;
{
    return [[[self alloc] initWithCommandCode:code argumentField:argumentField] autorelease];
}

+ (CKFTPCommand *)commandWithCode:(NSString *)code
{
    return [[[self alloc] initWithCommandCode:code] autorelease];
}

- (id)initWithCommandCode:(NSString *)verb argumentField:(NSString *)argumentField
{
    NSParameterAssert(verb);
    NSParameterAssert([verb length] > 0 || [verb length] <= 4);
    
    NSCharacterSet *legalVerbCharacters = [[self class] FTPCommandCodeCharacters];
    NSCharacterSet *illegalVerbCharacters = [legalVerbCharacters invertedSet];
    NSParameterAssert([verb rangeOfCharacterFromSet:illegalVerbCharacters].location == NSNotFound);
    
    if (argumentField) NSParameterAssert([argumentField length] > 0);
    
    [super init];
        
    _commandCode = [verb copy];
    _argumentField = [argumentField copy];
    
    return self;
}

- (id)initWithCommandCode:(NSString *)code
{
    return [self initWithCommandCode:code argumentField:nil];
}

- (void)dealloc
{
    [_commandCode release];
    [_argumentField release];
    
    [super dealloc];
}
    
#pragma mark -
#pragma mark Accessor Methods

- (NSString *)commandCode { return _commandCode; }
        
- (NSString *)argumentField { return _argumentField; }

#pragma mark -
#pragma mark Copy

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];   // immutable object
}

#pragma mark -
#pragma mark Description and Serialization

- (NSData *)serializedCommand
{
    NSMutableString *string = [[self serializedTelnetString] mutableCopy];
    /*[string replaceOccurrencesOfString:@"\r"    // escape carriage returns for Telnet. RFC 854.
                            withString:@"\r[NULL]"    // not functional yet
                               options:0
                                 range:NSMakeRange(0, [string length])];*/
    [string appendString:@"\r\n"];
    
    NSData *result = [string dataUsingEncoding:NSASCIIStringEncoding];
    [string release];
    
    return result;
}

- (NSString *)serializedTelnetString
{
    NSString *result = [[self commandCode] uppercaseString];
    NSString *parameter = [self argumentField];
    if (parameter)
    {
        result = [result stringByAppendingFormat:@" %@", parameter];
    }
    
    return result;
}

- (NSString *)description
{
    NSString *result = [[super description] stringByAppendingString:[self serializedTelnetString]];
    return result;
}

@end

//
//  CKFTPResponse.m
//  Connection
//
//  Created by Mike on 24/03/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFTPReply.h"


@implementation CKFTPReply

#pragma mark init

+ (CKFTPReply *)replyWithCode:(NSUInteger)code text:(NSString *)text
{
    return [[[self alloc] initWithReplyCode:code text:text] autorelease];
}

- (id)initWithReplyCode:(NSUInteger)code textLines:(NSArray *)lines
{
    NSParameterAssert(code < 1000);
    NSParameterAssert(lines);
    NSParameterAssert([lines count] >= 1);
    
    [super init];
    
    _replyCode = code;
    _textLines = [[NSArray alloc] initWithArray:lines copyItems:YES];   // deep copy
    
    return self;
}

- (id)initWithReplyCode:(NSUInteger)code text:(NSString *)text
{
    return [self initWithReplyCode:code textLines:[NSArray arrayWithObject:text]];
}

#pragma mark reply code

- (NSUInteger)replyCode { return _replyCode; }

- (NSString *)replyCodeString
{
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
    [formatter setNumberStyle:NSNumberFormatterNoStyle];
    NSString *result = [formatter stringFromNumber:[NSNumber numberWithUnsignedInteger:[self replyCode]]];
    
    [formatter release];
    return result;
}

- (CKFTPReplyType)replyType
{
    // The first digit of -replyCode
    CKFTPReplyType result = [self replyCode] / 100;
    return result;
}

- (CKFTPReplyFunctionGroup)functionalGrouping
{
    // The second digit or -replyCode
    CKFTPReplyFunctionGroup result = ([self replyCode] - (100 * [self replyType])) / 10;
    return result;
}

#pragma mark reply text

- (NSArray *)textLines { return _textLines; }


- (NSString *)quotedString
{
    static NSString *quoteCharacter = @"\"";
    static NSString *pairOfQuoteCharacters = @"\"\"";
    
    
    NSString *text = [[self textLines] objectAtIndex:0];
    NSScanner *scanner = [[NSScanner alloc] initWithString:text];
    [scanner setCharactersToBeSkipped:nil];
    
    NSString *result = nil;
    
    
    // Find the start of the quote
    [scanner scanUpToString:quoteCharacter intoString:NULL];
    if (![scanner isAtEnd])
    {
        [scanner setScanLocation:([scanner scanLocation] + 1)];
        if (![scanner isAtEnd])
        {
            // Find the first quote. The efficiency of parsing is fairly heavily weighted towards
            // strings without a pair of quotes, as they are exception rather than the norm.
            if (![scanner scanUpToString:quoteCharacter intoString:&result])
            {
                result = @"";   // accounts for an empty quote
            }
            
            
            // The quote might actually be a pair, such as in this reply:
            // 257 "/he said ""yo"" to me" created
            while ([scanner scanString:pairOfQuoteCharacters intoString:NULL])
            {
                result = [result stringByAppendingString:quoteCharacter];
            
                // Find the next quote
                NSString *nextString;
                if ([scanner scanUpToString:quoteCharacter intoString:&nextString])
                {
                    result = [result stringByAppendingString:nextString];
                }
            }
            
            
            // If we ever reach the end of the text, there was no closing quote, so it's invalid
            if ([scanner isAtEnd]) result = nil;
        }
    }
    
    [scanner release];
    
    
    return result;
}

#pragma mark serialization

- (NSArray *)serializedTelnetLines
{
    NSArray *lines = [self textLines];
    
    // The last line always needs to be of the form "123 Text"
    NSString *code = [self replyCodeString];
    NSString *lastLine = [NSString stringWithFormat:@"%@ %@", code, [lines lastObject]];
    
    // Handle simple replies
    if ([lines count] <= 1)
    {
        return [NSArray arrayWithObject:lastLine];
    }
    
    // To get to here, it's a multiline response
    NSMutableArray *result = [[lines mutableCopy] autorelease];
    [result replaceObjectAtIndex:([result count] - 1) withObject:lastLine];
    
    NSString *firstLine = [[NSString alloc] initWithFormat:@"%@-%@", code, [lines objectAtIndex:0]];
    [result replaceObjectAtIndex:0 withObject:firstLine];
    [firstLine release];
    
    return result;
}

- (NSString *)description
{
    return [[self serializedTelnetLines] componentsJoinedByString:@"\n"];
}

#pragma mark copy

- (id)copyWithZone:(NSZone *)zone
{
    // Immutable object
    return [self retain];
}

@end


#pragma mark -


@implementation CKStreamedFTPReply

#pragma mark init & dealloc

- (id)init
{
    if (self = [self initWithReplyCode:000 text:@""])
    {
        _data = [[NSMutableData alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    [_data release];
    [_multilineReplyBuffer release];
    
    [super dealloc];
}

#pragma mark copy

- (id)copyWithZone:(NSZone *)zone
{
    id result = [[CKFTPReply allocWithZone:zone] initWithReplyCode:[self replyCode]
                                                         textLines:[self textLines]];
    return result;
}

#pragma mark appending data

// Utility method to seek a particular character. Taken from -[NSData rangeOfData:range:]
+ (NSUInteger)locationOfCharacter:(char)character inData:(NSData *)data location:(NSUInteger)location
{	
	uint8_t *str = (uint8_t *)[data bytes];
	while (location < [data length])
	{
		if (str[location] == character)
		{
			return location;
		}
		location++;
	}
	
	return NSNotFound;
}

- (NSData *)replyDidBecomeComplete
{
    // Support method for when enough data has been received to complete the reply
    // Copies any data out of the temporary ivars, and then resets them.
    // Returns any leftover data from the buffer.
    [_textLines release];
    _textLines = _multilineReplyBuffer;
    _multilineReplyBuffer = nil;
    
    NSData *result = nil;
    if (_scanLocation < [_data length])
    {
        result = [_data subdataWithRange:NSMakeRange(_scanLocation, [_data length] - _scanLocation)];
    }
    [_data release];    _data = nil;
    return result;
}

/*  The general strategy is to add received data to _data. Once a complete line has arrived,
 *  decode it into a string and increment scanLocation. Once the full reply has been received the
 *  buffer is no longer needed, and any remaining data in it is returned to the caller.
 */
- (BOOL)appendData:(NSData *)data nextData:(NSData **)excess
{
    NSParameterAssert(data);
    NSAssert(![self isComplete], @"Can't append data to streamed FTP reply, already complete");
    
    
    
    // The code below assumes that some processing will take place and won't work if the empty data
    // is allowed to enter the system
    if ([data length] == 0) return 0;
    
    
    
    // Add the data to the buffer (the majority of the time it should be valid)
    BOOL result = YES;
    NSUInteger oldScanLocation = oldScanLocation;
    [_data appendData:data];
    
    
        
    // To be a valid reply, the first 3 characters must all be numeric...
    if (_scanLocation == 0)
    {
        NSString *replyStart = [[NSString alloc] initWithBytes:[_data bytes]
                                                        length:MAX(4, [_data length])
                                                      encoding:NSASCIIStringEncoding];
        
        result = NO;
        if (replyStart)
        {
            NSScanner *scanner = [[NSScanner alloc] initWithString:replyStart];
            [scanner setCharactersToBeSkipped:nil];
            
            int replyCode;
            if ([scanner scanInt:&replyCode] && replyCode < 1000)
            {
                result = YES;
                
                // ...and the 4th character must be a space or hyphen
                if ([replyStart length] >= 4)
                {
                    unichar spacerChar = [replyStart characterAtIndex:3];
                    switch (spacerChar)
                    {
                        case '-':
                            _multilineReplyBuffer = [[NSMutableArray alloc] init];
                        case ' ':
                            // Reaching this point means there is enough data for the full reply code.
                            _replyCode = replyCode;
                            _scanLocation = 4;
                            break;
                        default:
                            result = NO;
                    }
                }
            }
            
            [scanner release];
            [replyStart release];
        }
    }
    
    
    
    // If we have a valid start to the reply, search for the end of it
    // Already know that a valid reply code is present by this point, just have to decode the text
    if (result)
    {
        // Multiline replies require us to wait until the final line is received
        NSString *lastLineCode;
        if (_multilineReplyBuffer) lastLineCode = [[self replyCodeString] stringByAppendingString:@" "];
        
            
        // Split off text lines one at a time. They can end in <CR><LF> or <LF>
        NSUInteger linebreakStart = [CKStreamedFTPReply locationOfCharacter:'\n'
                                                                     inData:_data
                                                                   location:_scanLocation];
        while (linebreakStart != NSNotFound)
        {
            // What is the range of the actual text? Ignore the <LF>'s preceeding <CR> if it exists
            NSRange lineRange = NSMakeRange(_scanLocation, linebreakStart - _scanLocation);
            if (((uint8_t *)[_data bytes])[linebreakStart - 1] == '\r') lineRange.length--;
            NSData *lineData = [_data subdataWithRange:lineRange];
            
            _scanLocation = linebreakStart + 1;
            
            
            // Unescape any <CR>s within the line
            lineData = [CKStreamedFTPReply dataByUnescapingTelnetCarriageReturnsInData:lineData];
                
            
            // Any valid data MUST now be ASCII
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSASCIIStringEncoding];
            if (line)
            {
                [line autorelease];
                
                
                // We can easily use the line to finish a standard reply
                if (!_multilineReplyBuffer)
                {
                    *excess = [self replyDidBecomeComplete];
                    _textLines = [[NSArray alloc] initWithObjects:line, nil];
                    break;
                }
                
                
                // If this is the last line of a multiline reply, strip it of the code prefix
                if ([line hasPrefix:lastLineCode])
                {
                    line = [line substringFromIndex:4];
                    [_multilineReplyBuffer addObject:line];
                    *excess = [self replyDidBecomeComplete];
                    break;
                }
                
                [_multilineReplyBuffer addObject:line];
            }
            else
            {
                result = NO;
                break;
            }
            
            
            // Read in the next line
            linebreakStart = [CKStreamedFTPReply locationOfCharacter:'\n'
                                                              inData:_data
                                                            location:_scanLocation];
        }
    }
    
    
    // If the data was invalid, undo the changes caused by it
    if (!result)
    {
        [_data replaceBytesInRange:NSMakeRange([_data length] - [data length], [data length])
                         withBytes:NULL
                            length:0];
        
        _scanLocation = oldScanLocation;
        if (![self hasReplyCode]) _replyCode = 0;
    }
    
    
    return result;
}

+ (NSData *)dataByUnescapingTelnetCarriageReturnsInData:(NSData *)data
{
    return data;    // TODO: Actually do this!
}

#pragma mark accessors

- (BOOL)isComplete { return (_data == nil); }

- (BOOL)hasReplyCode
{
    BOOL result = (_scanLocation >= 4);
    return result;
}

@end

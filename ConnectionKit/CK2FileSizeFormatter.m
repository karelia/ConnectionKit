//
//  CK2FileSizeFormatter.m
//  Connection
//
//  Created by Paul Kim on 1/16/13.
//
//

#import "CK2FileSizeFormatter.h"

#define FRACTION_TRESHOLD_INDEX   2

static NSArray  *_unitLabels;

@implementation CK2FileSizeFormatter

+ (void)initialize
{
    if ([[self class] isEqual:[CK2FileSizeFormatter class]])
    {
        _unitLabels = [@[ @"bytes", @"KB", @"MB", @"TB", @"PB", @"EB", @"ZB", @"YB" ] retain];
    }
}

- (NSString *)stringForObjectValue:(id)anObject
{
    if ([anObject isKindOfClass:[NSNumber class]])
    {
        NSUInteger              i, count;
        double                  size;
        NSString                *formattedNumber;
        
        size = [anObject doubleValue];
        count = [_unitLabels count];
        
        for (i = 0; (i < count) && (size >= 1000); i++)
        {
            size /= 1000;
        }
        
        if (i >= count)
        {
            i = count - 1;
        }

        if (i < FRACTION_TRESHOLD_INDEX)
        {
            [self setMaximumFractionDigits:0];
        }
        else
        {
            [self setMaximumFractionDigits:1];
        }
        
        formattedNumber = [super stringForObjectValue:[NSNumber numberWithDouble:size]];
        
        return [NSString stringWithFormat:@"%@ %@", formattedNumber, [_unitLabels objectAtIndex:i]];
    }
    else if ([anObject isKindOfClass:[NSString class]])
    {
        return @"--";
    }
    return @"";
}

@end

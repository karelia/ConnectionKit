//
//  NSCalendarDate+Connection.m
//  Connection
//
//  Created by Greg Hulands on 21/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "NSCalendarDate+Connection.h"


@implementation NSCalendarDate (Connection)

+ (NSCalendarDate *)calendarDateWithZuluFormat:(NSString *)zulu
{
	// 2005-12-15T19:52:13Z
	NSCalendarDate *d = [NSCalendarDate dateWithString:zulu calendarFormat:@"%Y-%m-%dT%H:%M:%SZ"];
	NSTimeZone *zone = [NSTimeZone defaultTimeZone];
	int offset = [zone secondsFromGMT];
	NSCalendarDate *newDate = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate:[d timeIntervalSinceReferenceDate] + offset];
	
	return newDate;
}

+ (id)calendarDateWithString:(NSString *)string
{
	NSCalendarDate *date = nil;
	// Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
	date = [NSCalendarDate dateWithString:string calendarFormat:@"%a, %d %b %Y %H:%M:%S %Z"];
	if (date)
	{
		return date;
	}
	// Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
	date = [NSCalendarDate dateWithString:string calendarFormat:@"%A, %d-%b-%y %H:%M:%S %Z"];
	if (date)
	{
		return date;
	}
	// Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format
	date = [NSCalendarDate dateWithString:string calendarFormat:@"%a %b %e %H:%M:%S %Y"];
	if (date)
	{
		return date;
	}
	// 2006-02-05T23:22:39Z			; ISO 8601 date format
	if ([string hasSuffix:@"Z"])
	{
		date = [NSCalendarDate dateWithString:string calendarFormat:@"%Y-%m-%dT%H:%M:%SZ"];
		if (date)
		{
			return date;
		}
	}
	else
	{
		date = [NSCalendarDate dateWithString:string calendarFormat:@"%Y-%m-%dT%H:%M:%S%z"];
		if (date)
		{
			return date;
		}
	}
	return date;
}

- (NSString *)zuluFormat
{
	return [self descriptionWithCalendarFormat:@"%Y-%m-%dT%H:%M:%SZ" timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0] locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];
}

@end

/*
 Copyright (c) 2006, Greg Hulands <ghulands@mac.com>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#import "NSCalendarDate+Connection.h"


@implementation NSCalendarDate (Connection)

+ (NSCalendarDate *)calendarDateWithZuluFormat:(NSString *)zulu
{
	// 2005-12-15T19:52:13.000Z
	NSCalendarDate *d = [NSCalendarDate dateWithString:zulu calendarFormat:@"%Y-%m-%dT%H:%M:%S.000Z"];
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

//
//  NSCalendarDate+Connection.h
//  Connection
//
//  Created by Greg Hulands on 21/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface NSCalendarDate (Connection)

+ (NSCalendarDate *)calendarDateWithZuluFormat:(NSString *)zulu;
	/*
	 We will try and guess the date by trying these formats
	 -----------------
	 Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
	 Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
	 Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format
	 2006-02-05T23:22:39Z			; ISO 8601 date format
	 */
+ (id)calendarDateWithString:(NSString *)string;

- (NSString *)zuluFormat;

@end

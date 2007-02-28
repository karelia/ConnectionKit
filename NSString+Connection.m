//
//  NSString+Connection.m
//  Connection
//
//  Created by Greg Hulands on 19/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "NSString+Connection.h"
#import <math.h>
#import "AbstractConnectionProtocol.h"

@implementation NSString (Connection)

- (NSString *)encodeLegally
{
	NSString *result = (NSString *) CFURLCreateStringByAddingPercentEscapes(
																			NULL, (CFStringRef) self, (CFStringRef) @"%+#", NULL,
																			CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
	return [result autorelease];
}

+ (NSString *)stringWithData:(NSData *)data encoding:(NSStringEncoding)encoding
{
	return [[[NSString alloc] initWithData:data encoding:encoding] autorelease];
}

- (NSString *)firstPathComponent
{
	NSString *str = self;
	if ([str hasPrefix:@"/"])
		str = [str substringFromIndex:1];
	NSMutableArray *comps = [NSMutableArray arrayWithArray:[str componentsSeparatedByString:@"/"]];
	if ([comps count] > 0) {
		return [comps objectAtIndex:0];
	}
	return @"";
}

- (NSString *)stringByDeletingFirstPathComponent
{
	NSString *str = self;
	if ([str hasPrefix:@"/"])
		str = [str substringFromIndex:1];
	NSMutableArray *comps = [NSMutableArray arrayWithArray:[str componentsSeparatedByString:@"/"]];
	if ([comps count] > 0) {
		[comps removeObjectAtIndex:0];
	}
	return [@"/" stringByAppendingString:[comps componentsJoinedByString:@"/"]];
}

- (NSString *)stringByDeletingFirstPathComponent2
{
	NSString *str = self;
	if ([str hasPrefix:@"/"])
		str = [str substringFromIndex:1];
	NSMutableArray *comps = [NSMutableArray arrayWithArray:[str componentsSeparatedByString:@"/"]];
	if ([comps count] > 0) {
		[comps removeObjectAtIndex:0];
	}
	return [comps componentsJoinedByString:@"/"];
}

+ (NSString *)formattedFileSize:(double)size
{
	if (size == 0) return @"0 B";
	NSString *suffix[] = {
		LocalizedStringInThisBundle(@"bytes", @"filesize"),
		LocalizedStringInThisBundle(@"Kilobytes", @"filesize"),
		LocalizedStringInThisBundle(@"MB", @"filesize"),
		LocalizedStringInThisBundle(@"GB", @"filesize"),
		LocalizedStringInThisBundle(@"TB", @"filesize"),
		LocalizedStringInThisBundle(@"PB", @"filesize"),
		LocalizedStringInThisBundle(@"EB", @"filesize")
	};
	
	int power = floor(log(size) / log(1024));
	return [NSString stringWithFormat:@"%01.02lf %@", size / pow(1024, power), suffix[power]];
}

+ (NSString *)formattedSpeed:(double)speed
{
	return [NSString stringWithFormat:@"%@/s", [NSString formattedFileSize:speed]];
}

@end

@implementation NSAttributedString (Connection)

+ (NSAttributedString *)attributedStringWithString:(NSString *)str attributes:(NSDictionary *)attribs
{
	return [[[NSAttributedString alloc] initWithString:str attributes:attribs] autorelease];
}

@end

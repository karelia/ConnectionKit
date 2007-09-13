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
	if (size == 0) return [NSString stringWithFormat:@"0 %@", LocalizedStringInThisBundle(@"bytes", @"filesize: bytes")];
	NSString *suffix[] = {
		LocalizedStringInThisBundle(@"bytes", @"filesize: bytes"),
		LocalizedStringInThisBundle(@"KB", @"filesize: kilobytes"),
		LocalizedStringInThisBundle(@"MB", @"filesize: megabytes"),
		LocalizedStringInThisBundle(@"GB", @"filesize: gigabytes"),
		LocalizedStringInThisBundle(@"TB", @"filesize: terabytes"),
		LocalizedStringInThisBundle(@"PB", @"filesize: petabytes"),
		LocalizedStringInThisBundle(@"EB", @"filesize: exabytes")
	};
	
	int power = floor(log(size) / log(1024));
	if (power > 1)
	{
		return [NSString stringWithFormat:@"%01.02lf %@", size / pow(1024, power), suffix[power]];
	}
	else
	{
		return [NSString stringWithFormat:@"%01.0lf %@", size / pow(1024, power), suffix[power]];
	}
}

+ (NSString *)formattedSpeed:(double)speed
{
	return [NSString stringWithFormat:@"%@/%@", [NSString formattedFileSize:speed], LocalizedStringInThisBundle(@"s", @"abbreviation for seconds, e.g. 12 MB/s")];
}

+ (id)uuid
{
	CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
	CFStringRef uuidStr = CFUUIDCreateString(kCFAllocatorDefault, uuid);
	CFRelease(uuid);
	[(NSString *)uuidStr autorelease];
	return (NSString *)uuidStr;
}

@end

@implementation NSAttributedString (Connection)

+ (NSAttributedString *)attributedStringWithString:(NSString *)str attributes:(NSDictionary *)attribs
{
	return [[[NSAttributedString alloc] initWithString:str attributes:attribs] autorelease];
}

@end

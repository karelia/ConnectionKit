//
//  NSString+Connection.m
//  Connection
//
//  Created by Greg Hulands on 19/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "NSString+Connection.h"


@implementation NSString (Connection)

- (NSString *)encodeLegally
{
	NSString *result = (NSString *) CFURLCreateStringByAddingPercentEscapes(
																			NULL, (CFStringRef) self, (CFStringRef) @"%+#", NULL,
																			CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
	return result;
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

@end

@implementation NSAttributedString (Connection)

+ (NSAttributedString *)attributedStringWithString:(NSString *)str attributes:(NSDictionary *)attribs
{
	return [[[NSAttributedString alloc] initWithString:str attributes:attribs] autorelease];
}

@end

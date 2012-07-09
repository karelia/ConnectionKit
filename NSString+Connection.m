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

#import "NSString+Connection.h"
#import "CKConnectionProtocol.h"
#import <CommonCrypto/CommonDigest.h>

#include <math.h>

@implementation NSString (Connection)

- (NSString *)encodeLegally
{
	NSString *result = (NSString *) CFURLCreateStringByAddingPercentEscapes(
																			NULL, (CFStringRef)self, (CFStringRef)@"%+#", 
																			NULL, CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
	return [result autorelease];
}
- (NSString *)encodeLegallyForS3
{
	NSString *result = (NSString *) CFURLCreateStringByAddingPercentEscapes(
																			NULL, (CFStringRef)self, NULL, (CFStringRef)@"+",
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

- (NSString *)stringByAppendingURLComponent:(NSString *)URLComponent
{
	URLComponent = [URLComponent stringByStandardizingURLComponents];
	
	if ([URLComponent hasPrefix:@"/"])
		URLComponent = [URLComponent substringFromIndex:1];
	if ([URLComponent hasSuffix:@"/"])
		URLComponent = [URLComponent substringToIndex:[URLComponent length] - 1];
	
	if (![self hasSuffix:@"/"])
		URLComponent = [@"/" stringByAppendingString:URLComponent];
	return [self stringByAppendingString:URLComponent];	
}

- (NSString *)stringByStandardizingURLComponents
{
	NSString *returnString = [NSString stringWithString:self];
	
	//Make sure we've got one (and only one) leading slash
	while ([returnString hasPrefix:@"//"])
	{
		returnString = [returnString substringFromIndex:1];
	}
	
	//Make sure we've got no tailing slashes
	while ([returnString hasSuffix:@"/"] && ![returnString isEqualToString:@"/"])
	{
		returnString = [returnString substringToIndex:[returnString length] - 1];
	}
	return returnString;
}
- (NSArray *)componentsSeparatedByCharactersInSet:(NSCharacterSet *)set  //10.5 adds this to NSString, but we are 10.4+
{ 
	NSMutableArray *result = [NSMutableArray array]; 
	NSScanner *scanner = [NSScanner scannerWithString:self]; 
	NSString *chunk = nil; 
	[scanner setCharactersToBeSkipped:nil]; 
	BOOL sepFound = [scanner scanCharactersFromSet:set intoString:(NSString **)nil]; // skip any preceding separators 
	if(sepFound) 
	{ // if initial separator, start with empty component 
		[result addObject:@""]; 
	} 
	while ([scanner scanUpToCharactersFromSet:set intoString:&chunk]) 
	{ 
		[result addObject:chunk]; 
		sepFound = [scanner scanCharactersFromSet: set intoString: (NSString **) nil]; 
	} 
	if(sepFound) 
	{ // if final separator, end with empty component 
		[result addObject: @""]; 
	} 
	result = [result copy]; 
	return [result autorelease]; 
}
- (BOOL)containsSubstring:(NSString *)substring
{
	return [[self lowercaseString] rangeOfString:[substring lowercaseString]].location != NSNotFound;
}

+ (NSString *)formattedFileSize:(double)size
{
	if (size == 0) return [NSString stringWithFormat:@"0 %@", LocalizedStringInConnectionKitBundle(@"bytes", @"filesize: bytes")];
	NSString *suffix[] = {
		LocalizedStringInConnectionKitBundle(@"bytes", @"filesize: bytes"),
		LocalizedStringInConnectionKitBundle(@"KB", @"filesize: kilobytes"),
		LocalizedStringInConnectionKitBundle(@"MB", @"filesize: megabytes"),
		LocalizedStringInConnectionKitBundle(@"GB", @"filesize: gigabytes"),
		LocalizedStringInConnectionKitBundle(@"TB", @"filesize: terabytes"),
		LocalizedStringInConnectionKitBundle(@"PB", @"filesize: petabytes"),
		LocalizedStringInConnectionKitBundle(@"EB", @"filesize: exabytes")
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
	return [NSString stringWithFormat:@"%@/%@", [NSString formattedFileSize:speed], LocalizedStringInConnectionKitBundle(@"s", @"abbreviation for seconds, e.g. 12 MB/s")];
}

@end

@implementation NSAttributedString (Connection)

+ (NSAttributedString *)attributedStringWithString:(NSString *)str attributes:(NSDictionary *)attribs
{
	return [[[NSAttributedString alloc] initWithString:str attributes:attribs] autorelease];
}

@end

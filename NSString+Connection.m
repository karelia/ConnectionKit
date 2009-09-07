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

@implementation NSString (Connection)

#pragma mark -
#pragma mark Class Methods
+ (NSString *)formattedFileSize:(CGFloat)sizeInBytes
{
	if (sizeInBytes == 0)
		return [NSString stringWithFormat:@"0 %@", LocalizedStringInConnectionKitBundle(@"bytes", @"filesize: bytes")];
	
	NSString *suffix[] = 
	{
		LocalizedStringInConnectionKitBundle(@"bytes", @"filesize: bytes"),
		LocalizedStringInConnectionKitBundle(@"KB", @"filesize: kilobytes"),
		LocalizedStringInConnectionKitBundle(@"MB", @"filesize: megabytes"),
		LocalizedStringInConnectionKitBundle(@"GB", @"filesize: gigabytes"),
		LocalizedStringInConnectionKitBundle(@"TB", @"filesize: terabytes"),
		LocalizedStringInConnectionKitBundle(@"PB", @"filesize: petabytes"),
		LocalizedStringInConnectionKitBundle(@"EB", @"filesize: exabytes")
	};
	
	NSInteger power = floor(log(sizeInBytes) / log(1000));
	if (power > 1)
		return [NSString stringWithFormat:@"%01.02lf %@", (sizeInBytes / pow(1000, power)), suffix[power]];
	else
		return [NSString stringWithFormat:@"%01.0lf %@", (sizeInBytes / pow(1000, power)), suffix[power]];
}

+ (NSString *)UUID
{
	CFUUIDRef UUID = CFUUIDCreate(kCFAllocatorDefault);
	
	CFStringRef UUIDString = CFUUIDCreateString(kCFAllocatorDefault, UUID);
	CFRelease(UUID);
	
	return [(NSString *)UUIDString autorelease];
}

+ (NSString *)stringWithBytesOfUnknownEncoding:(char *)bytes length:(NSUInteger)length
{
	if (!bytes)
		return nil;
	
	CFStringEncoding encodings[] = 
	{
		kCFStringEncodingUTF8,
		kCFStringEncodingISOLatin1, 
		kCFStringEncodingWindowsLatin1,
		kCFStringEncodingNextStepLatin,
		kCFStringEncodingISOLatin2,
		kCFStringEncodingISOLatin3,
		kCFStringEncodingISOLatin4,
		kCFStringEncodingISOLatinCyrillic,
		kCFStringEncodingISOLatinArabic,
		kCFStringEncodingISOLatinGreek,
		kCFStringEncodingISOLatinHebrew,
		kCFStringEncodingISOLatin5,
		kCFStringEncodingISOLatin6,
		kCFStringEncodingISOLatinThai,
		kCFStringEncodingISOLatin7,
		kCFStringEncodingISOLatin8,
		kCFStringEncodingISOLatin9,
		kCFStringEncodingWindowsLatin2,
		kCFStringEncodingWindowsCyrillic,
		kCFStringEncodingWindowsGreek,
		kCFStringEncodingWindowsLatin5,
		kCFStringEncodingWindowsHebrew,
		kCFStringEncodingWindowsArabic,
		kCFStringEncodingKOI8_R,
		kCFStringEncodingBig5,
	};
	
	//Note that sizeof only works as we expect here when compiling with C99.
	NSInteger numberOfEncodings = (sizeof(encodings) / sizeof(CFStringEncoding));
	NSInteger encodingIndex;
	CFStringRef convertedString = nil;
	for (encodingIndex = 0; encodingIndex < numberOfEncodings; encodingIndex++)
	{
		convertedString = CFStringCreateWithBytes(kCFAllocatorDefault, 
												  (UInt8 *)bytes, 
												  length, 
												  encodings[encodingIndex], 
												  NO);
		if (convertedString)
			break;
	}
	
	if (!convertedString)
		return nil;
	
	return [(NSString *)convertedString autorelease];
}

#pragma mark -
#pragma mark Encoding
- (NSString *)encodeLegallyForURL
{
	NSString *result = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, 
																		   (CFStringRef)self, 
																		   NULL, 
																		   (CFStringRef)@":/%#;@", //Escape these as per [NSURL URLWithString]
																		   kCFStringEncodingUTF8);
	return [result autorelease];
}

- (NSString *)encodeLegallyForURI
{
	NSString *result = (NSString *) CFURLCreateStringByAddingPercentEscapes(NULL, 
																			(CFStringRef)self,
																			(CFStringRef)@"%+#", 
																			NULL,
																			kCFStringEncodingUTF8);
	return [result autorelease];
}

- (NSString *)encodeLegallyForAmazonS3URI
{
	NSString *result = (NSString *) CFURLCreateStringByAddingPercentEscapes(
																			NULL, (CFStringRef)self, NULL, (CFStringRef)@"+",
																			CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
	return [result autorelease];
}

#pragma mark -
#pragma mark Convenience Methods

- (BOOL)containsSubstring:(NSString *)substring
{
	return [[self lowercaseString] rangeOfString:[substring lowercaseString]].location != NSNotFound;
}

- (NSString *)firstPathComponent
{
	for (NSString *pathComponent in [self pathComponents])
		if (![pathComponent isEqualToString:@"/"])
			return pathComponent;
	return nil;	
}

- (NSString *)stringByDeletingFirstPathComponent
{
	//Grab the first path component
	NSString *firstPathComponent = [self firstPathComponent];
	if (!firstPathComponent)
		return self;
	
	NSMutableArray *pathComponents = [NSMutableArray arrayWithArray:[self pathComponents]];
	
	//Remove the leading slash, since it's not really a path component
	if ([[pathComponents objectAtIndex:0] isEqualToString:@"/"])
		[pathComponents removeObjectAtIndex:0];
	
	//Remove the first path component
	[pathComponents removeObject:firstPathComponent];
	
	//Put it all back together
	return [@"/" stringByAppendingPathComponent:[pathComponents componentsJoinedByString:@"/"]];
}

- (NSString *)stringByStandardizingPathWithLeadingSlash
{
	NSString *result = [NSString stringWithString:self];
	if (![result hasPrefix:@"/"])
		result = [@"/" stringByAppendingPathComponent:result];
	return [result stringByStandardizingPath];
}

#pragma mark -
#pragma mark URL Cooperation
- (NSString *)stringByStandardizingURLComponents
{
	NSString *returnString = [NSString stringWithString:self];
	
	//Make sure we've got one (and only one) leading slash
	while ([returnString hasPrefix:@"//"])
	{
		returnString = [returnString substringFromIndex:1];
	}
	
	//Make sure we've got no trailing slashes
	while ([returnString hasSuffix:@"/"] && ![returnString isEqualToString:@"/"])
	{
		returnString = [returnString substringToIndex:[returnString length] - 1];
	}
	return returnString;
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


@end
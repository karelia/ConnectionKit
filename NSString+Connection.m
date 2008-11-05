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
#import "AbstractConnectionProtocol.h"
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

- (NSString *)stringByStandardizingHTTPPath
{
	NSString *result = [NSString stringWithString:self];
	if (![result hasPrefix:@"/"])
		result = [@"/" stringByAppendingPathComponent:result];
	return [result stringByStandardizingPath];
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

- (NSString *)md5Hash;
{
	// toHash is an NSData
	NSData *toHash = [self dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char *digest = (unsigned char *)MD5([toHash bytes], [toHash length], NULL);
	return [NSString stringWithFormat: @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
			digest[0], digest[1], 
			digest[2], digest[3],
			digest[4], digest[5],
			digest[6], digest[7],
			digest[8], digest[9],
			digest[10], digest[11],
			digest[12], digest[13],
			digest[14], digest[15]];
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

+ (id)uuid
{
	CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
	CFStringRef uuidStr = CFUUIDCreateString(kCFAllocatorDefault, uuid);
	CFRelease(uuid);
	[(NSString *)uuidStr autorelease];
	return (NSString *)uuidStr;
}

/*The following are from Fugu (for SFTP usage)
 * Copyright (c) 2003 Regents of The University of Michigan. 
*/
+ ( NSString * )pathForExecutable: ( NSString * )executable
{
    NSString	*executablePath = nil;
    NSString	*searchPath = [[ NSUserDefaults standardUserDefaults ]
							   objectForKey: @"ExecutableSearchPath" ];
	
    if ( searchPath == nil ) {
		searchPath = @"/usr/bin";
    }
	
    executablePath = [ searchPath stringByAppendingPathComponent: executable ];
	
    if ( [[ NSFileManager defaultManager ]
		  fileExistsAtPath: executablePath ] ) {
		return( executablePath );
    }
	
    /* try again with a default path */
    executablePath = nil;
    executablePath = [ NSString stringWithFormat: @"/usr/bin/%@", executable ];
	
    if ( ! [[ NSFileManager defaultManager ]
			fileExistsAtPath: executablePath ] ) {
        executablePath = nil;
    }
	
    return( executablePath );
}

- ( char )objectTypeFromOctalRepresentation: ( NSString * )octalRep
{
    if ( [ octalRep isEqualToString: @"01" ] ) return( 'p' );
    else if ( [ octalRep isEqualToString: @"02" ] ) return( 'c' );
    else if ( [ octalRep isEqualToString: @"04" ] ) return( 'd' );
    else if ( [ octalRep isEqualToString: @"06" ] ) return( 'b' );
    else if ( [ octalRep isEqualToString: @"010" ] ) return( '-' );
    else if ( [ octalRep isEqualToString: @"012" ] ) return( 'l' );
    else if ( [ octalRep isEqualToString: @"014" ] ) return( 's' );
    else if ( [ octalRep isEqualToString: @"016" ] ) return( 'D' );
    else return( '-' );
}

- ( NSString * )stringRepresentationOfOctalMode
{
    NSString	*type = nil;
    char	tmp[ 11 ] = "----------";
    int		i = 1, j = 0, len = [ self length ];
    
    /*
     * if we're dealing with a server that outputs modes and types
     * as an octal string, start creating the mode string from
     * the appropriate point
     */
    if ( len == 6 ) {
        i = 3;
    } else if ( len == 7 ) {
        i = 4;
    } else {
        i = 1;
    }
	
    for ( j = 1; i < len; i++, j += 3 ) {
        switch( [ self characterAtIndex: i ] ) {
			case '0':
				break;
			case '1':
				tmp[ j + 2 ] = 'x';
				break;
			case '2':
				tmp[ j + 1 ] = 'w';
				break;
			case '3':
				tmp[ j + 1 ] = 'w';
				tmp[ j + 2 ] = 'x';
				break;
			case '4':
				tmp[ j ] = 'r';
				break;
			case '5':
				tmp[ j ] = 'r';
				tmp[ j + 2 ] = 'x';
				break;
			case '6':
				tmp[ j ] = 'r';
				tmp[ j + 1 ] = 'w';
				break;
			case '7':
				tmp[ j ] = 'r';
				tmp[ j + 1 ] = 'w';
				tmp[ j + 2 ] = 'x';
				break;
        }
    }
    
    if ( len == 6 ) {
        i = 3;
    } else if ( len == 7 ) {
        i = 4;
    } else {
        i = 1;
    }
    
    switch( [ self characterAtIndex: ( i - 1 ) ] ) {
		case '0':
			break;
		case '1':
			/* sticky bit */
			tmp[ 9 ] = 't';
			break;
		case '2':
			/* setgid */
			if ( tmp[ 6 ] != 'x' ) {
				tmp[ 6 ] = 'S';
			} else {
				tmp[ 6 ] = 's';
			}
			
			break;
			case '4':
			/* setuid */
			if ( tmp[ 3 ] != 'x' ) {
				tmp[ 3 ] = 'S';
			} else {
				tmp[ 3 ] = 's';
			}
			
			break;
    }
    
    if ( len == 6 ) {
        type = [ self substringToIndex: 2 ];
        tmp[ 0 ] = [ self objectTypeFromOctalRepresentation: type ];
    } else if ( len == 7 ) {
        type = [ self substringToIndex: 3 ];
        tmp[ 0 ] = [ self objectTypeFromOctalRepresentation: type ];
    } else {
        tmp[ 0 ] = ' ';
    }
	
    return( [ NSString stringWithUTF8String: tmp ] );
}
+ ( NSString * )stringWithBytesOfUnknownExternalEncoding: ( char * )bytes
												  length: ( unsigned )len
{
    int                     i, enccount = 0;
    CFStringRef             convertedString = NULL;
    CFStringEncoding        encodings[] = { kCFStringEncodingISOLatin2,
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
	kCFStringEncodingNextStepLatin };
	
    if ( bytes == NULL ) {
        return( nil );
    }
    
    enccount = ( sizeof( encodings ) / sizeof( CFStringEncoding ));
    
    for ( i = 0; i < enccount; i++) {
        if ( ! CFStringIsEncodingAvailable( encodings[ i ] )) {
            continue;
        }
        
        if (( convertedString = CFStringCreateWithBytes( kCFAllocatorDefault,
														( UInt8 * )bytes, len, encodings[ i ], true )) != NULL ) {
            break;
        }
    }
	
    return(( NSString * )convertedString );
}

+ ( NSString * )stringWithBytesOfUnknownEncoding: ( char * )bytes
										  length: ( unsigned )len
{
    int                     i, enccount = 0;
    CFStringRef             convertedString = NULL;
    CFStringEncoding        encodings[] = { kCFStringEncodingUTF8,
		kCFStringEncodingISOLatin1,
		kCFStringEncodingWindowsLatin1,
	kCFStringEncodingNextStepLatin };
    
    if ( bytes == NULL ) {
        return( nil );
    }
    
    enccount = ( sizeof( encodings ) / sizeof( CFStringEncoding ));
    
    for ( i = 0; i < enccount; i++) {
        if (( convertedString = CFStringCreateWithBytes( kCFAllocatorDefault,
														( UInt8 * )bytes, len, encodings[ i ], false )) != NULL ) {
            break;
        }
    }
	
    if ( convertedString == NULL ) {
        convertedString = ( CFStringRef )[ NSString stringWithBytesOfUnknownExternalEncoding: bytes
																					  length: len ];
    }
    
    if ( convertedString != NULL ) {
        [ ( NSString * )convertedString autorelease ];
    }
	
    return(( NSString * )convertedString );
}
@end

@implementation NSAttributedString (Connection)

+ (NSAttributedString *)attributedStringWithString:(NSString *)str attributes:(NSDictionary *)attribs
{
	return [[[NSAttributedString alloc] initWithString:str attributes:attribs] autorelease];
}

@end

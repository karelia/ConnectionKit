/*
 Copyright (c) 2007, Greg Hulands <ghulands@mac.com>
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

#import "NSFileManager+Connection.h"

#import "CKAbstractConnection.h"

#import "NSCalendarDate+Connection.h"
#import "NSString+Connection.h"

#import "RegexKitLite.h"


//Exception Names
NSString *CKFailedToParseDirectoryListingException = @"CKFailedToParseDirectoryListingException";


int filenameSort(id obj1, id obj2, void *context)
{
    NSString *f1 = [obj1 objectForKey:[cxFilenameKey lastPathComponent]];
	NSString *f2 = [obj2 objectForKey:[cxFilenameKey lastPathComponent]];
	
	return [f1 caseInsensitiveCompare:f2];
}


@implementation NSFileManager (Connection)

+ (NSString *)fixFilename:(NSString *)filename withAttributes:(NSMutableDictionary *)attributes
{
	NSString *fname = [NSString stringWithString:[filename stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	NSString *type = [attributes objectForKey:NSFileType];
	if ([type isEqualToString:NSFileTypeDirectory]) 
	{
		if ([fname hasSuffix:@"/"])
			fname = [fname substringToIndex:[fname length] - 1];
	}
	if ([type isEqualToString:NSFileTypeSymbolicLink]) 
	{
		if ([fname hasSuffix:@"@"])
			fname = [fname substringToIndex:[fname length] - 1];
	}
	if ([fname hasSuffix:@"@"]) //We get @'s on the filename for aliases on Mac OS X Server.
	{
		[attributes setObject:NSFileTypeSymbolicLink forKey:NSFileType];
		fname = [fname substringToIndex:[fname length] - 1];
	}
	NSNumber *permissions = [attributes objectForKey:NSFilePosixPermissions];
	if (permissions)
	{
		unsigned long perms = [permissions unsignedLongValue];
		if ((perms & 01) || (perms & 010) || (perms & 0100))
		{
			if ([fname hasSuffix:@"*"])
				fname = [fname substringToIndex:[fname length] - 1];
		}
	}
	return fname;
}

/* 
 "-rw-r--r--   1 root     other        531 Jan 29 03:26 README"
 "dr-xr-xr-x   2 root     other        512 Apr  8  1994 etc"
 "dr-xr-xr-x   2 root     512 Apr  8  1994 etc"
 "lrwxrwxrwx   1 root     other          7 Jan 25 00:17 bin -> usr/bin"
 Also produced by Microsofts FTP servers for Windows:
 "----------   1 owner    group         1803128 Jul 10 10:18 ls-lR.Z"
 "d---------   1 owner    group               0 May  9 19:45 Softlib"
 Windows also produces this crap 
 "10-20-05  05:19PM       <DIR>          fordgt/"
 "10-21-05  08:14AM                 4927 index.html"
 Also WFTPD for MSDOS: 
 "-rwxrwxrwx   1 noone    nogroup      322 Aug 19  1996 message.ftp" 
 Also NetWare:
 "d [R----F--] supervisor            512       Jan 16 18:53    login" 
 "- [R----F--] rhesus             214059       Oct 20 15:27    cx.exe"
 Also NetPresenz for the Mac:
 "-------r--         326  1391972  1392298 Nov 22  1995 MegaPhone.sit"
 "drwxrwxr-x               folder        2 May 10  1996 network"
 */

#define CONDITIONALLY_ADD NSString *fn = [attributes objectForKey:cxFilenameKey]; \
if (![fn isEqualToString:@"."] && \
![fn isEqualToString:@".."]) \
{ \
[attributedLines addObject:attributes]; \
}

+ (BOOL)wordIsInteger:(NSString *)word
{
	return [word isEqualToString:[[NSNumber numberWithInt:[word intValue]] stringValue]];
}

+ (NSString *)filenameFromIndex:(int)index inWords:(NSArray *)words attributes:(NSMutableDictionary *)attributes
{
	NSMutableString *tempStr = [NSMutableString string];
	while (index < [words count])
	{
		[tempStr appendFormat:@"%@ ", [words objectAtIndex:index]];
		index++;
	}
	return [self fixFilename:tempStr withAttributes:attributes];
}
+ (NSArray *)_linesFromListing:(NSString *)listing
{
	NSString *lineEnding = @"\r\n";
	//Determine how we break lines
	if ([listing rangeOfString:@"\r\n"].location == NSNotFound)
	{
		//We don't have \r\n, what about \n?
		if ([listing rangeOfString:@"\n"].location == NSNotFound)
		{
			//No way to separate lines, error.
			KTLog(CKParsingDomain, KTLogError, @"Could not determine line endings, try refreshing directory");
			NSException *exception = [NSException exceptionWithName:CKFailedToParseDirectoryListingException reason:@"Could not determine line endings." userInfo:nil];
			@throw exception;
			return nil;
		}
		lineEnding = @"\n";
	}
	return [listing componentsSeparatedByString:lineEnding];
}
+ (NSArray *)_wordsFromLine:(NSString *)line
{
	NSArray *words = [line componentsSeparatedByString:@" "]; //Is NOT the same as componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]. Separating by character set interprets multiple whitespaces next to each other as a _single_ separator. We don't want that
	NSMutableArray *finalWords = [NSMutableArray arrayWithArray:words];
	
	//Remove all blank spaces before the date. After the date, blank spaces (even next to each other) are _valid_ characters in a filename. They cannot be removed.
	NSString *dateString = [self _dateStringFromListing:line];
	if (!dateString)
		return finalWords;
	NSUInteger lastDateWordIndex = NSNotFound;
	NSUInteger currentLocation = [dateString length] - 1;
	while (currentLocation >= 0)
	{
		unichar currentCharacter = [dateString characterAtIndex:currentLocation];
		if (currentCharacter == ' ')
		{
			//Everything after this index is part of the last word.
			NSString *lastDateWord = [dateString substringFromIndex:currentLocation+1];
			lastDateWordIndex = [words indexOfObject:lastDateWord];
			break;
		}
		currentLocation--;
	}
	if (lastDateWordIndex == NSNotFound)
	{
		NSLog(@"Error Parsing Words: Parsed last date word is not in words array.");
		return nil;
	}
	
	/*
	 We loop by index instead of fast enumeration or an enumerator because we _need_ the index anyway. We need the index because we cannot remove objects from finalWords using removeObject, as it would simply remove _all_ the objects that return YES to isEqual:, which in the case of NSString, is more than just the object we've iterated to –– it would include all objects of equivalent value (i.e., all empty strings). That being said, we could use -removeObjectIdenticalTo:, but the documentation states that -removeObjectIdenticalTo: simply asks for the index, which we already have if loop by index ourselves.
	 */
	NSUInteger currentIndex = 0;
	NSMutableIndexSet *indexesOfBlankSpacesBeforeDate = [NSMutableIndexSet indexSet];
	while (currentIndex <= lastDateWordIndex)
	{
		NSString *word = [words objectAtIndex:currentIndex];
		if ([word length] <= 0 || [word characterAtIndex:0] == ' ')
			[indexesOfBlankSpacesBeforeDate addIndex:currentIndex];
		currentIndex++;
	}
	[finalWords removeObjectsAtIndexes:indexesOfBlankSpacesBeforeDate];
	return finalWords;
}

+ (NSString *)_dateStringFromListing:(NSString *)listing
{
	//This regex finds the entire date. "May 12 2006" or "May 12 12:15"
	NSString *anyMonthRegex = @"((Jan)|(Feb)|(Mar)|(Apr)|(May)|(Jun)|(Jul)|(Aug)|(Sep)|(Oct)|(Nov)|(Dec))";
	NSString *anyDayRegex = @"((0*[1-9])|([12][0-9])|(3[01]))";
	NSString *anyTimeRegex = @"(([012]*[0-9]):([0-5][0-9]))";
	NSString *anyYearRegex = @"[0-9]{4}";
	NSString *anyDateRegex = [NSString stringWithFormat:@"%@( )+%@( )+(%@|%@)", anyMonthRegex, anyDayRegex, anyTimeRegex, anyYearRegex, nil];
	NSRange dateRange = [listing rangeOfRegex:anyDateRegex];
	if (dateRange.location == NSNotFound)
		return nil;
    
	return [listing substringWithRange:dateRange];
}
+ (int)_filenameColumnIndexFromLine:(NSString *)line
{
	/*
     * Look for the date, and base the filename column index as the column after that.
     * If we can't find the date or "." or "..", use popular-assumptions about the filename column index based on the number of columns we have.
     */
	int filenameColumnIndex = -1;
	NSString *date = [self _dateStringFromListing:line];
	NSArray *words = [self _wordsFromLine:line];
	
	if (date)
	{
		//Filename is after the date column.
		NSString *lastColumnStringOfDate = [[date componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lastObject];
		int lastDateColumnIndex = [words indexOfObject:lastColumnStringOfDate];
		if (lastDateColumnIndex != NSNotFound)
			filenameColumnIndex = lastDateColumnIndex + 1;
	}
    
	if (filenameColumnIndex == -1)
	{
		//If we can't find the date or "." or "..", use popular-assumptions about the filename column index based on the number of columns we have.
		switch ([words count])
		{
			case 10:
				//-rwx------ 1 user group           2252 May 22 04:20 Project-Video Planning.rtf
				filenameColumnIndex = 8;
				break;
			case 9:
				//-rwx------ 1 user group           2252 May 22 04:20 myFile.tiff
				filenameColumnIndex = 7;
				break;
			case 8: //No Group
				//-rwx------ 1 user            2252 May 22 04:20 myFile.tiff
				filenameColumnIndex = 6;
				break;
			default:
				filenameColumnIndex = [words count] - 1;
				break;
		}			
	}
    
	return filenameColumnIndex;
}
+ (NSArray *)attributedFilesFromListing:(NSString *)listing
{
	if ([listing length] == 0)
		return [NSArray array];
	
	NSMutableArray *attributedLines = [NSMutableArray array];
    
	NSArray *lines = [NSFileManager _linesFromListing:listing];
	
	NSEnumerator *lineEnumerator = [lines objectEnumerator];
	NSString *line;
	while ((line = [lineEnumerator nextObject]))
	{
		if ([line length] <= 0)
			continue;
		
		NSArray *words = [NSFileManager _wordsFromLine:line];
		
		//index should be 
		// 0 - type and permissions
		// 1 - number of links
		// 2 - owner
		// 3 - group / size
		// 4 - size / date - month
		// 5 - date - month / date - day 
		// 6 - date - day / date - year or time
		// 7 - date - year or time / filename
		// 8 - filename / -> link arrow
		// 9 - link arrow / link target
		// 10 - link target
		
		if ([words count] < 4)
			continue;
        
		NSString *wordZero = [words objectAtIndex:0];
		NSString *wordOne = [words objectAtIndex:1];
		NSString *wordTwo = [words objectAtIndex:2];
		NSString *wordThree = [words objectAtIndex:3];
		NSString *wordFour = ([words count] >= 5) ? [words objectAtIndex:4] : nil;
		NSString *wordFive = ([words count] >= 6) ? [words objectAtIndex:5] : nil;
		NSString *wordSix = ([words count] >= 7) ? [words objectAtIndex:6] : nil;
		NSString *wordSeven = ([words count] >= 8) ? [words objectAtIndex:7] : nil;
		
		NSCalendarDate *date = nil;
		NSNumber *referenceCount = nil;
		NSNumber *size = nil;
		
		NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
		
		if ([wordOne hasSuffix:@"PM"] || [wordOne hasSuffix:@"AM"]) //Disgusting MSDOS Server
		{
			//11-25-05 03:42PM   <DIR>     folder/
			//02-18-08 04:57PM          0123 file
			NSString *dateString = [NSString stringWithFormat:@"%@ %@", wordZero, wordOne];
			date = [NSCalendarDate dateWithString:dateString calendarFormat:@"%m-%d-%y %I:%M%p"];
			
			if ([wordTwo isEqualToString:@"<DIR>"])
			{
				[attributes setObject:NSFileTypeDirectory forKey:NSFileType];
			}
			else
			{
				size = [NSNumber numberWithInt:[wordTwo intValue]];
				[attributes setObject:NSFileTypeRegular forKey:NSFileType];
			}
			[NSFileManager parseFilenameAndSymbolicLinksFromIndex:3 ofWords:words withAttributes:attributes];
		}		
		else if ([wordOne isEqualToString:@"folder"]) //netprez folder
		{
			[self parsePermissions:wordZero withAttributes:attributes];
			referenceCount = [NSNumber numberWithInt:[wordTwo intValue]];
			date = [NSCalendarDate getDateFromMonth:wordThree day:wordFour yearOrTime:wordFive];
			[NSFileManager parseFilenameAndSymbolicLinksFromIndex:6 ofWords:words withAttributes:attributes];
		}
		else if ([NSFileManager wordIsInteger:wordTwo] && [NSFileManager wordIsInteger:wordFour] && [wordFive intValue] >= 0 && [wordSix intValue] <= 31 && [wordSix intValue] > 0)
		{
			/* "drwxr-xr-x    2 32224    bainbrid     4096 Nov  8 20:56 aFolder" */ 
			[self parsePermissions:wordZero withAttributes:attributes];
			referenceCount = [NSNumber numberWithInt:[wordOne intValue]];
			date = [NSCalendarDate getDateFromMonth:wordFive day:wordSix yearOrTime:wordSeven];
			size = [NSNumber numberWithDouble:[wordFour doubleValue]];
			[NSFileManager parseFilenameAndSymbolicLinksFromIndex:8 ofWords:words withAttributes:attributes];
		}
		else if ([NSFileManager wordIsInteger:wordTwo] && [wordFive intValue] <= 31 && [wordFive intValue] > 0) // netprez file
		{
			/* "-------r--         326  1391972  1392298 Nov 22  1995 MegaPhone.sit" */ 
			[self parsePermissions:wordZero withAttributes:attributes];
			referenceCount = [NSNumber numberWithInt:[wordOne intValue]];
			date = [NSCalendarDate getDateFromMonth:wordFour day:wordFive yearOrTime:wordSix];
			size = [NSNumber numberWithDouble:[wordThree doubleValue]];
			[NSFileManager parseFilenameAndSymbolicLinksFromIndex:7 ofWords:words withAttributes:attributes];
		}
		else if ([wordOne isEqualToString:@"FTP"] && [wordTwo isEqualToString:@"User"]) //Trellix FTP Server
		{
			[self parsePermissions:wordZero withAttributes:attributes];
			size = [NSNumber numberWithDouble:[wordThree doubleValue]];
			date = [NSCalendarDate getDateFromMonth:wordFour day:wordFive yearOrTime:wordSix];
			[self parseFilenameAndSymbolicLinksFromIndex:7 ofWords:words withAttributes:attributes];
		}
		else //Everything else
		{
			//Permissions
			[self parsePermissions:wordZero withAttributes:attributes];
			
			//Reference Count
			referenceCount = [NSNumber numberWithInt:[wordOne intValue]];
			
			//Account
			[attributes setObject:wordTwo forKey:NSFileOwnerAccountName]; //Account
			
			//Date
			NSString *dateString = [NSFileManager _dateStringFromListing:line]; //Date
			if (!dateString)
			{
				//Much of what we do from this point is based on finding the date. This is a serious bug, and should be addressed. Log it out, report an error.
				NSLog(@"Could not parse date from line %@ of listing %@", line, listing);
				NSException *exception = [NSException exceptionWithName:CKFailedToParseDirectoryListingException reason:LocalizedStringInConnectionKitBundle(@"Error parsing directory listing", @"Directory Parsing Error") userInfo:nil];
				@throw exception;
			}
            
			NSArray *dateComponents = [dateString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			NSString *month = [dateComponents objectAtIndex:0];
			NSString *day = [dateComponents objectAtIndex:1];
			NSString *yearOrTime = [dateComponents objectAtIndex:2];			
			date = [NSCalendarDate getDateFromMonth:month day:day yearOrTime:yearOrTime];
			
			//Size
			int monthColumnIndex = [words indexOfObject:month];
			int sizeColumnIndex = monthColumnIndex - 1;
			size = [NSNumber numberWithDouble:[[words objectAtIndex:sizeColumnIndex] doubleValue]];
			
			//Group
			NSString *group = [NSString string];
			int currentIndex = 3; //Account's columnIndex is 2. Everything in between account and size is group.
			while (currentIndex < sizeColumnIndex)
			{
				group = [group stringByAppendingString:[words objectAtIndex:currentIndex]];
				currentIndex++;
			}
			[attributes setObject:group forKey:NSFileGroupOwnerAccountName];
			
			//Filename
			int filenameColumnIndex = [NSFileManager _filenameColumnIndexFromLine:line];
			[self parseFilenameAndSymbolicLinksFromIndex:filenameColumnIndex ofWords:words withAttributes:attributes];
		}
		
		if (date)
			[attributes setObject:date forKey:NSFileModificationDate];
		if (referenceCount)
			[attributes setObject:referenceCount forKey:NSFileReferenceCount];
		if (size)
			[attributes setObject:size forKey:NSFileSize];
		CONDITIONALLY_ADD	
	}
	
	return [attributedLines sortedArrayUsingFunction:filenameSort context:NULL];
}
+ (void)parseFilenameAndSymbolicLinksFromIndex:(int)index ofWords:(NSArray *)words withAttributes:(NSMutableDictionary *)attributes
{
	NSString *fileType = [attributes objectForKey:NSFileType];
	if ([fileType isEqualToString:NSFileTypeCharacterSpecial] || [fileType isEqualToString:NSFileTypeBlockSpecial])
	{
		index++;
		if (index >= [words count]) // sftp listings do not have the extra column
			index = [words count] - 1;
	}
	
	if ([fileType isEqualToString:NSFileTypeSymbolicLink])
	{
		NSMutableArray *filenameBits = [NSMutableArray array];
		while (index < [words count])
		{
			NSString *bit = [words objectAtIndex:index];
			if ([bit rangeOfString:@"->"].location != NSNotFound)
			{
				index++;
				break;
			}
			[filenameBits addObject:bit];
			index++;
		}
		NSArray *symBits = [words subarrayWithRange:NSMakeRange(index, [words count] - index)];
		NSString *filenameStr = [filenameBits componentsJoinedByString:@" "];
		filenameStr = [filenameStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString *symTarget = [symBits componentsJoinedByString:@" "];
		symTarget = [symTarget stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		
		[attributes setObject:[self fixFilename:filenameStr withAttributes:attributes] forKey:cxFilenameKey];
		[attributes setObject:[self fixFilename:symTarget withAttributes:attributes] forKey:cxSymbolicLinkTargetKey];
	}
	else
	{
		NSArray *filenameBits = [words subarrayWithRange:NSMakeRange(index, [words count] - index)];
		NSString *filenameStr = [filenameBits componentsJoinedByString:@" "];
		[attributes setObject:[self fixFilename:filenameStr withAttributes:attributes] forKey:cxFilenameKey];
	}
}
+ (void)parsePermissions:(NSString *)perm withAttributes:(NSMutableDictionary *)attributes
{
	char *data = (char *)[perm UTF8String];
	
	//what type of file is it
	switch (*data)
	{
		case '-': [attributes setObject:NSFileTypeRegular forKey:NSFileType]; break;
		case 'l': [attributes setObject:NSFileTypeSymbolicLink forKey:NSFileType]; break;
		case 'd': [attributes setObject:NSFileTypeDirectory forKey:NSFileType]; break;
		case 'c': [attributes setObject:NSFileTypeCharacterSpecial forKey:NSFileType]; break;
		case 'b': [attributes setObject:NSFileTypeBlockSpecial forKey:NSFileType]; break;
		default: [attributes setObject:NSFileTypeUnknown forKey:NSFileType]; break;
	}
	data++;
	//permisions
	switch (*data)
	{
		case 'r':
		case '-': //unix style listing
		{
			unsigned long perm = 0;
			//owner
			if (*data++ == 'r')		perm |= 0400;
			if (*data++ == 'w')		perm |= 0200;
			if (*data++ == 'x')		perm |= 0100;
			//group
			if (*data++ == 'r')		perm |= 040;
			if (*data++ == 'w')		perm |= 020;
			if (*data++ == 'x')		perm |= 010;
			//world
			if (*data++ == 'r')		perm |= 04;
			if (*data++ == 'w')		perm |= 02;
			if (*data++ == 'x')		perm |= 01;
			// clang flags data++ above as not being read, but it's just being scanned and skipped
			[attributes setObject:[NSNumber numberWithUnsignedLong:perm] forKey:NSFilePosixPermissions];
			break;
		}
		case ' ': //[---------]
		{
			while (*data != ']')
				data++;
			data++; // clang flags this but data is just being scanned past here
			break;
		}
		default:
			KTLog(CKParsingDomain, KTLogError, @"Unknown FTP Permission state");
	}
}

- (unsigned long long)sizeOfPath:(NSString *)path
{
	NSDictionary *attribs = [self attributesOfItemAtPath:path error:NULL];
	if (attribs)
	{
		return [[attribs objectForKey:NSFileSize] unsignedLongLongValue];
	}
	return 0;
}

@end

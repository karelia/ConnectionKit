/*
 Copyright (c) 2004-2006 Karelia Software. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Karelia Software nor the names of its contributors may be used to 
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
#import "NSData+Connection.h"
#import <zlib.h>
#include <sasl/saslutil.h>

@implementation NSData (Connection)

- (NSString *)base64Encoding
{
	NSString* retVal = nil;
	/* base64 encode
	 *  in      -- input data
	 *  inlen   -- input data length
	 *  out     -- output buffer (will be NUL terminated)
	 *  outmax  -- max size of output buffer
	 * result:
	 *  outlen  -- gets actual length of output buffer (optional)
	 * 
	 * Returns SASL_OK on success, SASL_BUFOVER if result won't fit
	 */
	
	NSUInteger bufSize = 4 * [self length] / 3 + 100;
	char *buffer = malloc(bufSize);
	unsigned actualLength = 0;
	int status = sasl_encode64([self bytes], [self length], buffer, bufSize, &actualLength); 	
	
	if (SASL_OK == status)
	{
		retVal = [[[NSString alloc] initWithBytes: buffer length: actualLength encoding: NSASCIIStringEncoding] autorelease];
		
	}
    // Clean up
    free(buffer);
    return retVal;	
}

- (NSString *)descriptionAsUTF8String
{
	return [[[NSString alloc] initWithData:self encoding:NSUTF8StringEncoding] autorelease];
}

- (NSString *)descriptionAsASCIIString
{
	return [[[NSString alloc] initWithData:self encoding:NSASCIIStringEncoding] autorelease];
}

- (NSString *)shortDescription
{
	NSUInteger width = [[NSUserDefaults standardUserDefaults] integerForKey:@"NSDataDescriptionWidth"];
	NSUInteger maxBytes = [[NSUserDefaults standardUserDefaults] integerForKey:@"NSDataDescriptionBytes"];
	if (!width) width = 32;
	if (width > 64) width = 64;	// let's be reasonable people!
	
	if (!maxBytes) maxBytes = 1024;

	unsigned char *bytes = (unsigned char *)[self bytes];
	NSUInteger length = [self length];
	NSMutableString *buf = [NSMutableString stringWithFormat:@"%@ %ld bytes:\n", [self className], (unsigned long) length];
	for (NSUInteger i = 0 ; i < length ; i += width )
	{
		if (i > maxBytes)		// don't print too much!
		{
			[buf appendString:@"\n...\n"];
			break;
		}
		for (NSUInteger j = 0 ; j < width ; j++ )
		{
			int offset = i+j;
			if (offset < length)
			{
				[buf appendFormat:@"%02X ",bytes[offset]];
			}
			else
			{
				[buf appendFormat:@"   "];
			}
		}
		[buf appendString:@"| "];
		for (NSUInteger j = 0 ; j < width ; j++ )
		{
			NSUInteger offset = i+j;
			if (offset < length)
			{
				unsigned char theChar = bytes[offset];
				if (theChar < 32 || theChar > 127)
				{
					theChar ='.';
				}
				[buf appendFormat:@"%c", theChar];
			}
		}
		[buf appendString:@"\n"];
	}
	if (length)
	{
		[buf deleteCharactersInRange:NSMakeRange([buf length]-1, 1)];
	}
	return buf;
}

// These are from cocoadev.com

- (NSData *)inflate
{
	if ([self length] == 0) return self;
	
	unsigned full_length = [self length];
	unsigned half_length = [self length] / 2;
	
	NSMutableData *decompressed = [NSMutableData dataWithLength: full_length + half_length];
	BOOL done = NO;
	int status;
	
	z_stream strm;
	strm.next_in = (Bytef *)[self bytes];
	strm.avail_in = [self length];
	strm.total_out = 0;
	strm.zalloc = Z_NULL;
	strm.zfree = Z_NULL;
	
	if (inflateInit (&strm) != Z_OK) return nil;
	while (!done)
	{
		// Make sure we have enough room and reset the lengths.
		if (strm.total_out >= [decompressed length])
			[decompressed increaseLengthBy: half_length];
		strm.next_out = [decompressed mutableBytes] + strm.total_out;
		strm.avail_out = [decompressed length] - strm.total_out;
		
		// Inflate another chunk.
		status = inflate (&strm, Z_SYNC_FLUSH);
		if (status == Z_STREAM_END) done = YES;
		else if (status != Z_OK) break;
	}
	if (inflateEnd (&strm) != Z_OK) return nil;
	
	// Set real length.
	if (done)
	{
		[decompressed setLength: strm.total_out];
		return [NSData dataWithData: decompressed];
	}
	else return nil;
}

- (NSData *)deflate
{
	if ([self length] == 0) return self;
	
	z_stream strm;
	
	strm.zalloc = Z_NULL;
	strm.zfree = Z_NULL;
	strm.opaque = Z_NULL;
	strm.total_out = 0;
	strm.next_in=(Bytef *)[self bytes];
	strm.avail_in = [self length];
	
	if (deflateInit(&strm, Z_DEFAULT_COMPRESSION) != Z_OK) return nil;
	
	NSMutableData *compressed = [NSMutableData dataWithLength:16384];  // 16K chuncks for expansion
	
	do {
		
		if (strm.total_out >= [compressed length])
			[compressed increaseLengthBy: 16384];
		
		strm.next_out = [compressed mutableBytes] + strm.total_out;
		strm.avail_out = [compressed length] - strm.total_out;
		
		deflate(&strm, Z_FINISH);  
		
	} while (strm.avail_out == 0);
	
	deflateEnd(&strm);
	
	[compressed setLength: strm.total_out];
	return [NSData dataWithData: compressed];
}

- (NSRange)rangeOfData:(NSData *)data
{
	return [self rangeOfData:data range:NSMakeRange(0, [self length])];
}

- (NSRange)rangeOfData:(NSData *)data range:(NSRange)range
{
	NSRange r = NSMakeRange(NSNotFound, 0);
	if (!data || [data length] == 0)
		return r;
	
	uint8_t *find = (uint8_t *)[data bytes];
	uint8_t *str = (uint8_t *)[self bytes];
	unsigned i = 0, j = 1, start = 0; // , end = 0;
	
	//wind it forward to the start of the range
	unsigned offset = range.location;
	
	while (i + offset < [self length])
	{
		if (str[i + offset] == find[0])
		{
			start = i;
			j = 1;
			while (j < [data length] && i + offset + j < [self length])
			{
				if (str[i + offset + j] != find[j])
				{
					break;
				}
				j++;
			}
			//end = j;
			if (j == [data length])
			{
				r.location = start + offset;
				r.length = [data length];
				break;
			}
		}
		i++;
	}
	
	return r;
}

@end

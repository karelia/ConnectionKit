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
#import <openssl/ssl.h>
#import <openssl/hmac.h>

@implementation NSData (Connection)

- (NSString *)base64Encoding
{
	BIO * mem = BIO_new(BIO_s_mem());
	BIO * b64 = BIO_new(BIO_f_base64());
    BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
    mem = BIO_push(b64, mem);
	
	BIO_write(mem, [self bytes], [self length]);
    BIO_flush(mem);
	
	char * base64Pointer;
    long base64Length = BIO_get_mem_data(mem, &base64Pointer);
	
	NSString * base64String = [NSString stringWithCString:base64Pointer
												   length:base64Length];
	
	BIO_free_all(mem);
    return base64String;
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
	unsigned int width = [[NSUserDefaults standardUserDefaults] integerForKey:@"NSDataDescriptionWidth"];
	unsigned int maxBytes = [[NSUserDefaults standardUserDefaults] integerForKey:@"NSDataDescriptionBytes"];
	if (!width) width = 32;
	if (width > 64) width = 64;	// let's be reasonable people!
	
	if (!maxBytes) maxBytes = 1024;

	unsigned char *bytes = (unsigned char *)[self bytes];
	unsigned length = [self length];
	NSMutableString *buf = [NSMutableString stringWithFormat:@"%@ %d bytes:\n", [self className], length];
	int i, j;
	
	for ( i = 0 ; i < length ; i += width )
	{
		if (i > maxBytes)		// don't print too much!
		{
			[buf appendString:@"\n...\n"];
			break;
		}
		for ( j = 0 ; j < width ; j++ )
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
		for ( j = 0 ; j < width ; j++ )
		{
			int offset = i+j;
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

// these are from http://people.no-distance.net/ol/software/s3/ BSD Licensed

- (NSData *)md5Digest
{
	EVP_MD_CTX mdctx;
	unsigned char md_value[EVP_MAX_MD_SIZE];
	unsigned int md_len;
	EVP_DigestInit(&mdctx, EVP_md5());
	EVP_DigestUpdate(&mdctx, [self bytes], [self length]);
	EVP_DigestFinal(&mdctx, md_value, &md_len);
	return [NSData dataWithBytes:md_value length:md_len];
}

- (NSData *)sha1Digest
{
	EVP_MD_CTX mdctx;
	unsigned char md_value[EVP_MAX_MD_SIZE];
	unsigned int md_len;
	EVP_DigestInit(&mdctx, EVP_sha1());
	EVP_DigestUpdate(&mdctx, [self bytes], [self length]);
	EVP_DigestFinal(&mdctx, md_value, &md_len);
	return [NSData dataWithBytes:md_value length:md_len];
}

- (NSData *)sha1HMacWithKey:(NSString*)key
{
	HMAC_CTX mdctx;
	unsigned char md_value[EVP_MAX_MD_SIZE];
	unsigned int md_len;
	const char* k = [key cStringUsingEncoding:NSUTF8StringEncoding];
	const unsigned char *data = [self bytes];
	int len = [self length];
	
	HMAC_CTX_init(&mdctx);
	HMAC_Init(&mdctx,k,strlen(k),EVP_sha1());
	HMAC_Update(&mdctx,data, len);
	HMAC_Final(&mdctx, md_value, &md_len);
	HMAC_CTX_cleanup(&mdctx);
	return [NSData dataWithBytes:md_value length:md_len];
}


@end

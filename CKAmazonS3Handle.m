//
//  CK_AmazonS3Stream.m
//  ConnectionKit
//
//  Created by Mike on 23/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKAmazonS3Handle.h"

#import "CKHTTPConnection.h"

#import <CommonCrypto/CommonHMAC.h>


@interface CKAmazonS3Handle ()
- (void)addAuthenticationToRequest;
- (NSString *)requestSignature;
- (NSString *)stringToSign;
- (NSString *)canonicalizedResource;
- (NSString *)canonicalizedAmzHeaders;
@end


char *NewBase64Encode(const void *inputBuffer,
                      size_t length,
                      bool separateLines,
                      size_t *outputLength);


#pragma mark -


@implementation CKAmazonS3Handle

#pragma mark Init

- (id)initWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential;
{
    [self init];
    
    _request = [request mutableCopy];
    _credential = [credential retain];
    
    return self;
}

- (BOOL)createStreamWithOffset:(off_t)offset error:(NSError **)outError
{
    [self addAuthenticationToRequest];
    CFHTTPMessageRef message = [_request makeHTTPMessage];
    _stream = NSMakeCollectable(CFReadStreamCreateForHTTPRequest(NULL, message));
    
    [_stream setProperty:(id)kCFBooleanTrue
                      forKey:(NSString *)kCFStreamPropertyHTTPShouldAutoredirect];
    
    if (offset == 0)
    {
        [_stream open];
    }
    else
    {
        if (outError) *outError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                      code:ESPIPE
                                                  userInfo:nil];
        return NO;
    }
    
    return YES;
}

#pragma mark Received Data

- (int)read:(uint8_t *)buffer size:(size_t)size offset:(off_t)offset error:(NSError **)outError;
{
    // Open the stream if needed
    if (!_stream)
    {
        [self createStreamWithOffset:offset error:outError];
    }
    
    
    
    // Read from stream if in the right place
    int result = -1;
    if (offset == _expectedOffset)
    {
        result = [self read:buffer size:size error:outError];
        if (result > 0)
        {
            _expectedOffset += result;
        }
    }
    else
    {
        if (outError) *outError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                      code:ESPIPE
                                                  userInfo:nil];
    }
    
    return result;
}

/*  The key method. It reads the next lump of data from the stream, not caring about offsets
 */
- (int)read:(uint8_t *)buffer size:(size_t)size error:(NSError **)outError;
{
    int result = 0;
    NSError *error = nil;
    
    
    // Open the stream if needed
    if (!_stream)
    {
        if (![self createStreamWithOffset:0 error:&error]) result = -1;
    }
    
    
    // Read
    if (result > -1)
    {
        result = [_stream read:buffer maxLength:size];
        if (result < 0) error = [_stream streamError];
        
        
        // The response comes down the pipe first and determines how we treat the rest of the data (i.e. could fail the read, turning the data into an error)
        if (!_haveProcessedResponse)
        {
            NSHTTPURLResponse *response = [self response];
            if (response)
            {
                _haveProcessedResponse = YES;   // do this early so error handling can read in more data if it wants
                
                if ([response statusCode] >= 300)   // OMG, it's an error
                {
                    // TODO: Read in the response body and convert it to an error object
                    NSMutableData *errorData = [[NSMutableData alloc] initWithBytes:buffer length:result];
                    NSData *errorData2 = [self readDataToEndOfFile:&error];
                    if (errorData2) // reading the remaining data could have failed
                    {
                        [errorData appendData:errorData2];
                        
                        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                                  response, @"URLResponse",
                                                  errorData, @"ReceivedData",
                                                  nil];
                        
                        error = [NSError errorWithDomain:NSURLErrorDomain
                                                    code:NSURLErrorUnknown
                                                userInfo:userInfo];                        
                    }
                    
                    [errorData release];
                    result = -1;
                }
            }
        }
    }
    
    
    if (result < 0 && outError) *outError = error;
    return result;
}

- (NSData *)readDataToEndOfFile:(NSError **)outError;
{
    // Read data
    NSMutableData *result = [[NSMutableData alloc] init];
    while ([_stream streamStatus] < NSStreamStatusAtEnd)
    {
        uint8_t buf[1024];
        int len = [self read:buf size:1024 error:outError];
        if (len < 0)
        {
            [result release], result = nil;
        }
        else
        {
            [result appendBytes:(const void *)buf length:len];
        }
    }
    
    return [result autorelease];
}

// If possible, constructs a response object from the HTTP response. Does not block.
- (NSHTTPURLResponse *)response;
{
    NSHTTPURLResponse *result = nil;
    
    CFHTTPMessageRef responseMessage = (CFHTTPMessageRef)[_stream propertyForKey:(NSString *)kCFStreamPropertyHTTPResponseHeader];
    if (responseMessage && CFHTTPMessageIsHeaderComplete(responseMessage))
    {
        NSURL *URL = [_stream propertyForKey:(NSString *)kCFStreamPropertyHTTPFinalURL];
        result = [NSHTTPURLResponse responseWithURL:URL HTTPMessage:responseMessage];
    }
    
    return result;
}

#pragma mark Close

- (void)close;
{
    [_stream close];
    [_stream release], _stream = nil;
}

#pragma mark Authentication

- (void)addAuthenticationToRequest;
{
    NSString *AWSAccessKeyId = [_credential user];
    
    NSString *authorization = [NSString stringWithFormat:
                               @"AWS %@:%@",
                               AWSAccessKeyId,
                               [self requestSignature]];
    
	[_request setValue:authorization forHTTPHeaderField:@"Authorization"];
}

- (NSString *)requestSignature;
{
    NSData *secretAccessKeyID = [[_credential password] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *stringToSignData = [[self stringToSign] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char md_value[CC_SHA1_DIGEST_LENGTH];
    
    CCHmac(kCCHmacAlgSHA1,
           [secretAccessKeyID bytes], [secretAccessKeyID length],
           [stringToSignData bytes], [stringToSignData length],
           &md_value);
    
    NSData *signatureData = [[NSData alloc] initWithBytes:md_value length:CC_SHA1_DIGEST_LENGTH];
    
    
    
    //  ------------------------------------------------------------
    // iPhone SDK has no built-in means for base 64 encoding. Thanks to http://cocoawithlove.com/2009/06/base64-encoding-options-on-mac-and.html for this implementation.
    //  Created by Matt Gallagher on 2009/06/03.
    //  Copyright 2009 Matt Gallagher. All rights reserved.
    //
    //  Permission is given to use this source code file, free of charge, in any
    //  project, commercial or otherwise, entirely at your risk, with the condition
    //  that any redistribution (in part or whole) of source code must retain
    //  this copyright and permission notice. Attribution in compiled projects is
    //  appreciated but not required.
    
    size_t outputLength;
	char *outputBuffer =
    NewBase64Encode([signatureData bytes], [signatureData length], true, &outputLength);
	
	NSString *result = [[NSString alloc] initWithBytes:outputBuffer
                                                length:outputLength
                                              encoding:NSASCIIStringEncoding];
	free(outputBuffer);
    
    //  ------------------------------------------------------------
    
    
    [signatureData release];
    return [result autorelease];
}

- (NSString *)stringToSign;
{
    // S3 authentication relies in part on the date the request was made. This may already have been specified. If not, generate it now
    NSString *contentType = [_request valueForHTTPHeaderField:@"Content-Type"];
    if (!contentType) contentType = @"";
	
    NSString *result = [NSString stringWithFormat:
                        @"%@\n%@\n%@\n%@\n%@%@",
                        [_request HTTPMethod],
                        contentType,
                        @"",                            // placeholder for MD5 hash
                        @"",                            // will use x-amz-date instead of standard Date header
                        [self canonicalizedAmzHeaders], // already includes a trailing \n
                        [self canonicalizedResource]];
    
    return result;
}

- (NSString *)canonicalizedResource;
{
    // Canonicalized resource string is based around the URL path (HTTP header URI)
    NSURL *URL = [_request URL];
    
    CFStringRef path = CFURLCopyPath((CFURLRef)[URL absoluteURL]);  // maintain trailing slash. Oddly, doesn't seem to do unescaping
    NSMutableString *buffer = [(NSString *)path mutableCopy];
    CFRelease(path);
    
    // Stick in bucket name too if it's specified by subdomain
    NSString *host = [URL host];
    if ([host length] > [@"s3.amazonaws.com" length])
    {
        NSString *subdomain = [host substringToIndex:([host length] - [@"s3.amazonaws.com" length] - 1)];
        [buffer insertString:[@"/" stringByAppendingString:subdomain] atIndex:0];
    }
    
    // Include subresource
    NSString *query = [URL query];
    if ([query rangeOfString:@"="].location == NSNotFound)
    {
        [buffer appendFormat:@"?%@", query];
    }
    
    NSString *result = [[buffer copy] autorelease];
    [buffer release];
    return result;
}

- (NSString *)canonicalizedAmzHeaders;
{
    // Cocoa doesn't let us get at the date header from a request before it's sent (makes sense really!), so we're using x-amz-date instead. Need to set it here if not already in place
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    [formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	[formatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss 'GMT'"];
	
    NSDate *date = [[NSDate alloc] init];
    NSString *httpDate = [formatter stringFromDate:date];
    [_request setValue:httpDate forHTTPHeaderField:@"x-amz-date"];
    [date release];
    
    
    
    NSMutableString *result = [NSMutableString string];
    
    NSArray *headerFieldKeys = [[_request allHTTPHeaderFields] allKeys];
    NSArray *sortedHeaderFieldKeys = [headerFieldKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    for (NSString *aKey in sortedHeaderFieldKeys)
    {
        // Includes only S3-specific fields. Everything is lower-cased. Compress excess whitespace down to a single space.
        NSString *lowercaseKey = [aKey lowercaseString];
        if ([lowercaseKey hasPrefix:@"x-amz-"])
		{
			NSString *value = [_request valueForHTTPHeaderField:aKey];
            NSAssert1([value rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location == NSNotFound,
                      @"Wasn't expecting Amazon S3 request header field to contain a newline character:\n%@",
                      value);
            [result appendFormat:@"%@:%@\n", lowercaseKey, value];
		}
    }
    
    return result;
}

@end


#pragma mark -


//  Created by Matt Gallagher on 2009/06/03.
//  Copyright 2009 Matt Gallagher. All rights reserved.
//
//  Permission is given to use this source code file, free of charge, in any
//  project, commercial or otherwise, entirely at your risk, with the condition
//  that any redistribution (in part or whole) of source code must retain
//  this copyright and permission notice. Attribution in compiled projects is
//  appreciated but not required.


static unsigned char base64EncodeLookup[65] =
"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";


#define BINARY_UNIT_SIZE 3
#define BASE64_UNIT_SIZE 4


char *NewBase64Encode(
                      const void *buffer,
                      size_t length,
                      bool separateLines,
                      size_t *outputLength)
{
	const unsigned char *inputBuffer = (const unsigned char *)buffer;
	
#define MAX_NUM_PADDING_CHARS 2
#define OUTPUT_LINE_LENGTH 64
#define INPUT_LINE_LENGTH ((OUTPUT_LINE_LENGTH / BASE64_UNIT_SIZE) * BINARY_UNIT_SIZE)
#define CR_LF_SIZE 2
	
	//
	// Byte accurate calculation of final buffer size
	//
	size_t outputBufferSize =
    ((length / BINARY_UNIT_SIZE)
     + ((length % BINARY_UNIT_SIZE) ? 1 : 0))
    * BASE64_UNIT_SIZE;
	if (separateLines)
	{
		outputBufferSize +=
        (outputBufferSize / OUTPUT_LINE_LENGTH) * CR_LF_SIZE;
	}
	
	//
	// Include space for a terminating zero
	//
	outputBufferSize += 1;
    
	//
	// Allocate the output buffer
	//
	char *outputBuffer = (char *)malloc(outputBufferSize);
	if (!outputBuffer)
	{
		return NULL;
	}
    
	size_t i = 0;
	size_t j = 0;
	const size_t lineLength = separateLines ? INPUT_LINE_LENGTH : length;
	size_t lineEnd = lineLength;
	
	while (true)
	{
		if (lineEnd > length)
		{
			lineEnd = length;
		}
        
		for (; i + BINARY_UNIT_SIZE - 1 < lineEnd; i += BINARY_UNIT_SIZE)
		{
			//
			// Inner loop: turn 48 bytes into 64 base64 characters
			//
			outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
			outputBuffer[j++] = base64EncodeLookup[((inputBuffer[i] & 0x03) << 4)
                                                   | ((inputBuffer[i + 1] & 0xF0) >> 4)];
			outputBuffer[j++] = base64EncodeLookup[((inputBuffer[i + 1] & 0x0F) << 2)
                                                   | ((inputBuffer[i + 2] & 0xC0) >> 6)];
			outputBuffer[j++] = base64EncodeLookup[inputBuffer[i + 2] & 0x3F];
		}
		
		if (lineEnd == length)
		{
			break;
		}
		
		//
		// Add the newline
		//
		outputBuffer[j++] = '\r';
		outputBuffer[j++] = '\n';
		lineEnd += lineLength;
	}
	
	if (i + 1 < length)
	{
		//
		// Handle the single '=' case
		//
		outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
		outputBuffer[j++] = base64EncodeLookup[((inputBuffer[i] & 0x03) << 4)
                                               | ((inputBuffer[i + 1] & 0xF0) >> 4)];
		outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i + 1] & 0x0F) << 2];
		outputBuffer[j++] =	'=';
	}
	else if (i < length)
	{
		//
		// Handle the double '=' case
		//
		outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
		outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0x03) << 4];
		outputBuffer[j++] = '=';
		outputBuffer[j++] = '=';
	}
	outputBuffer[j] = 0;
	
	//
	// Set the output length and return the buffer
	//
	if (outputLength)
	{
		*outputLength = j;
	}
	return outputBuffer;
}


//
//  CKAmazonS3HTTPConnection.m
//  ConnectionKit
//
//  Created by Mike on 28/06/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKAmazonS3RESTOperation.h"

#import "CKHTTPConnection.h"
#import <CommonCrypto/CommonHMAC.h>


NSString *const CKAmazonErrorCodeKey = @"AmazonErrorCode";


@interface CKAmazonS3RESTOperation ()
- (void)addAuthenticationToRequest;
- (NSString *)requestSignature;
- (NSString *)requestStringToSign;
- (NSString *)canonicalizedResource;
- (NSString *)canonicalizedAmzHeaders;
@end


char *NewBase64Encode(const void *inputBuffer,
                      size_t length,
                      bool separateLines,
                      size_t *outputLength);



#pragma mark -


@implementation CKAmazonS3RESTOperation

#pragma mark Init & Dealloc

- (id)initWithRequest:(NSURLRequest *)request
           credential:(NSURLCredential *)credential
             delegate:(id <CKAmazonS3RESTOperationDelegate>)delegate;
{
    NSParameterAssert(request);
    NSParameterAssert(credential);
    NSParameterAssert([credential user]);
    
    [self init];
    
    _request = [request mutableCopy];
    _credential = [credential retain];
    _delegate = delegate;
    
    return self;
}

- (void)dealloc
{
    [_request release];
    [_credential release];
    // Connection should have been released before this
    
    [super dealloc];
}

#pragma mark NSOperation overrides

- (void)start
{
    CFRetain(self); // want to be sure operation is not accidentally deallocated mid-connection
    
    [self willChangeValueForKey:@"isExecuting"];
    _isExecuting = YES;
    [self didChangeValueForKey:@"isExecuting"];
    
    [self main];
}

- (BOOL)isFinished { return _isFinished; }

- (BOOL)isExecuting { return _isExecuting; }

- (BOOL)isConcurrent { return YES; }

- (void)operationDidEnd:(BOOL)finished error:(NSError *)error
{
    // Connection is no longer needed
    [_connection cancel];
    [_connection release];  _connection = nil;
    
    // Mark as finished etc.
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    _isExecuting = NO;
    _isFinished = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
    
    // Let delegate know
    if (finished)
    {
        [_delegate amazonS3OperationDidFinishLoading:self];
    }
    else
    {
        [_delegate amazonS3Operation:self didFailWithError:error];
    }
    
    // Retained at start of connection
    CFRelease(self);
}

#pragma mark Connection

- (void)main
{
    // All S3 operations should be authenticated using Amazon's unique scheme
    [self addAuthenticationToRequest];
    
    _connection = [[NSURLConnection alloc] initWithRequest:_request delegate:self];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // Amazon uses its own authentication scheme so this should never happen!
    NSError *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorUserAuthenticationRequired userInfo:nil];
    [self connection:connection didFailWithError:error];
    [error release];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
{
    if ([response isKindOfClass:[NSHTTPURLResponse class]])
    {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if ([httpResponse statusCode] >= 300)   // 3xx errors are likey to be redirects, which NSURLConnection handles
        {
            // TODO: Construct an error from the XML payload
            [self operationDidEnd:NO error:nil];
        }
        else
        {
            [_delegate amazonS3Operation:self didReceiveResponse:httpResponse];
        }
    }
    else
    {
        // TODO: Fail with error or assertion?
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    [_delegate amazonS3Operation:self didReceiveData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
{
    [self operationDidEnd:YES error:nil];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
{
    [self operationDidEnd:NO error:error];
}

#pragma mark Authentication

- (void)addAuthenticationToRequest
{    
    NSString *AWSAccessKeyId = [_credential user];
    
    NSString *authorization = [NSString stringWithFormat:
                               @"AWS %@:%@",
                               AWSAccessKeyId,
                               [self requestSignature]];
    
	[_request setValue:authorization forHTTPHeaderField:@"Authorization"];
}

- (NSString *)requestSignature
{
    NSData *secretAccessKeyID = [[_credential password] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *stringToSignData = [[self requestStringToSign] dataUsingEncoding:NSUTF8StringEncoding];
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

- (NSString *)requestStringToSign
{
    // S3 authentication relies in part on the date the request was made. This may already have been specified. If not, generate it now
    NSString *date = [_request valueForHTTPHeaderField:@"Date"];
    if (!date)
    {
        CFHTTPMessageRef HTTPMessage = [_request makeHTTPMessage];
        date = [NSMakeCollectable(CFHTTPMessageCopyHeaderFieldValue(HTTPMessage, CFSTR("Date"))) autorelease];
        [_request setValue:date forHTTPHeaderField:@"Date"];
    }
    
    
    NSString *contentType = [_request valueForHTTPHeaderField:@"Content-Type"];
    if (!contentType) contentType = @"";
	
    NSString *result = [NSString stringWithFormat:
                        @"%@\n%@\n%@\n%@\n%@%@",
                        [_request HTTPMethod],
                        contentType,
                        @"",                            // placeholder for MD5 hash
                        date,
                        [self canonicalizedAmzHeaders], // already includes a trailing \n
                        [self canonicalizedResource]];
    
    return result;
}

- (NSString *)canonicalizedResource
{
    // Canonicalized resource string is based around the URL path (HTTP header URI)
    NSURL *URL = [_request URL];
    NSMutableString *buffer = [[URL path] mutableCopy];
    
    // Stick in bucket name too if it's specified by subdomain
    NSString *host = [URL host];
    if ([host length] > [@"amazonaws.com" length])
    {
        NSString *subdomain = [host substringToIndex:([host length] - [@"amazonaws.com" length])];
        [buffer insertString:subdomain atIndex:0];
    }
    
    // Include subresource
    NSString *query = [URL query];
    if ([query rangeOfString:@"="].location == NSNotFound)
    {
        [buffer appendFormat:@"?%@", query];
    }
        
    NSString *result = [buffer stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    [buffer release];
    return result;
}

- (NSString *)canonicalizedAmzHeaders
{
    NSMutableString *result = [NSMutableString string];
    
    NSArray *headerFieldKeys = [[_request allHTTPHeaderFields] allKeys];
    NSArray *sortedHeaderFieldKeys = [headerFieldKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    for (NSString *aKey in sortedHeaderFieldKeys)
    {
        // Includes only S3-specific fields. Everything is lower-cased. Compress excess whitespace down to a single space.
        NSString *lowercaseKey = [aKey lowercaseString];
        if ([lowercaseKey hasPrefix:@"x-amz"])
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


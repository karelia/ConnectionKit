// This code derives from Aaron Jacobs's OneButton Socket, which was
// at the time of writing normally licensed under the terms of the
// GNU General Public License.  You can find the "standard" version
// in the CVS repository of OneButton FTP (www.onebutton.org).
//
// The SPECIFIC INCARNATION of OneButton Socket upon which this
// code is based was specially distributed to Greg Hulands on 2006-01-05
// under the terms of a modified BSD-style license rather than the GPL.
// This does not indicate that any other version of OneButton Socket
// is or will be distributed under any license but the GPL.

/*
 * Copyright (c) 2005, Aaron Jacobs.
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above two paragraph
 *       note about licensing of OneButton Socket, the above copyright notice,
 *       this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of Aaron Jacobs nor the names of OneButton Socket or
 *       OneButton FTP may be used to endorse or promote products derived from
 *       this software without specific prior written permission from Aaron Jacobs.
 *
 * THIS SOFTWARE IS PROVIDED BY AARON JACOBS "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL AARON JACOBS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
 * OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 * WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */

#import "ONBSSLContext.h"
#import "ONBSSLIdentity.h"

@interface ONBSSLContext ( ONBSSLContextPrivateMethods )

- (OSStatus)ONB_handleSSLReadToData:(void *)data size:(size_t *)size;
- (OSStatus)ONB_handleSSLWriteFromData:(const void *)data size:(size_t *)size;

@end

OSStatus SSLReadFunction(SSLConnectionRef connection, void *data, size_t *dataLength)
{
	return [(ONBSSLContext *)connection ONB_handleSSLReadToData:data size:dataLength];
}

OSStatus SSLWriteFunction(SSLConnectionRef connection, const void *data, size_t *dataLength)
{
	return [(ONBSSLContext *)connection ONB_handleSSLWriteFromData:data size:dataLength];
}

@implementation ONBSSLContext

-  (id)init
{
	if (! (self = [super init]))
		return nil;
	
	[self setSSLIdentity:nil];
	
	return self;
}

- (void)dealloc
{
	[self setSSLIdentity:nil];
	[super dealloc];
}

- (int)handshakeWithInputData:(NSMutableData *)inputData
					outputData:(NSMutableData *)outputData
{
	int ret;

	// If we haven't yet set up the SSL context, we should do so now.
	if (! ONB_sslContext)
	{
		if (ret = SSLNewContext((Boolean)[self sslServerMode], &ONB_sslContext))
		{
			NSLog(@"Error creating new context");
			return ret;
		}
		
		if (ret = SSLSetIOFuncs(ONB_sslContext, SSLReadFunction, SSLWriteFunction))
		{
			NSLog(@"Error setting IO Functions");
			return ret;
		}
		
		if (ret = SSLSetConnection(ONB_sslContext, self))
		{
			NSLog(@"Error setting connection");
			return ret;
		}
		
		if (ret = SSLSetEnableCertVerify(ONB_sslContext, (Boolean)[self verifySSLCertificates]))
		{
			NSLog(@"Error calling SSLSetEnableCertVerify");
			return ret;
		}
		
		SecIdentityRef identity = [[self sslIdentity] identityRef];
		if (identity || [self sslServerMode])
		{
			CFArrayRef certificates = CFArrayCreate(kCFAllocatorDefault,
													(const void **)&identity,
													identity ? 1 : 0,
													NULL);
			
			ret = SSLSetCertificate(ONB_sslContext, certificates);
			CFRelease(certificates);
			
			if (ret)
			{
				NSLog(@"Error setting certificates: %d", ret);
				return ret;
			}
			else
				NSLog(@"Set up certificates");
		}
	}
	
	ONB_inputData = inputData;
	ONB_outputData = outputData;
	ret = SSLHandshake(ONB_sslContext);
	
	if (ret == errSSLWouldBlock)
		return 0;
	
	if (! ret)
		return 1;
	
	return ret;
}

- (NSData *)encryptData:(NSData *)data inputData:(NSMutableData *)inputData
{
	if ((! data) || (! [data length]))
		return [NSData data];

	ONB_inputData = inputData;
	ONB_outputData = [NSMutableData dataWithCapacity:2*[data length]];
	unsigned int totalLength = [data length];
	unsigned int processed = 0;
	const void *buffer = [data bytes];
	
	while (processed < totalLength)
	{
		size_t written = 0;
		
		int ret;
		if (ret = SSLWrite(ONB_sslContext, buffer + processed, totalLength - processed, &written))
			return nil;

		processed += written;
	}
	
	return [NSData dataWithData:ONB_outputData];
}

- (NSData *)decryptData:(NSMutableData *)data outputData:(NSMutableData *)outputData
{
	if ((! data) || (! [data length]))
		return [NSData data];
	
	ONB_inputData = data;
	ONB_outputData = outputData;
	NSMutableData *decryptedData = [NSMutableData dataWithCapacity:[data length]];
	int ret = 0;
	
	while (! ret)
	{
		size_t read = 0;
		char buf[1024];
		
		ret = SSLRead(ONB_sslContext, buf, 1024, &read);
		if (ret && (ret != errSSLWouldBlock) && (ret != errSSLClosedGraceful))
		{
			NSLog(@"Error in SSLRead: %d", ret);
			return nil;
		}
		
		[decryptedData appendBytes:buf length:read];
	}
	
	return [NSData dataWithData:decryptedData];
}

- (BOOL)verifySSLCertificates
{
	return ONB_verifySSLCerts;
}

- (void)setVerifySSLCertificates:(BOOL)verifySSLCertificates
{
	ONB_verifySSLCerts = verifySSLCertificates;
}

- (ONBSSLIdentity *)sslIdentity
{
	return ONB_sslIdentity;
}

- (BOOL)sslServerMode
{
	return ONB_sslServerMode;
}

- (void)setSSLServerMode:(BOOL)sslServerMode
{
	ONB_sslServerMode = sslServerMode;
}

- (void)setSSLIdentity:(ONBSSLIdentity *)sslIdentity
{
	[ONB_sslIdentity autorelease];
	ONB_sslIdentity = [sslIdentity retain];
}

- (OSStatus)ONB_handleSSLWriteFromData:(const void *)data size:(size_t *)size
{
	[ONB_outputData appendBytes:data length:*size];
	return noErr;
}

- (OSStatus)ONB_handleSSLReadToData:(void *)data size:(size_t *)size
{
	size_t askedSize = *size;
	*size = MIN(askedSize, [ONB_inputData length]);
	if (! *size)
	{
		return errSSLWouldBlock;
	}
	
	NSRange byteRange = NSMakeRange(0, *size);
	[ONB_inputData getBytes:data range:byteRange];
	[ONB_inputData replaceBytesInRange:byteRange withBytes:NULL length:0];
	
	if (askedSize > *size)
		return errSSLWouldBlock;
	
	return noErr;
}

@end
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

#import <Foundation/Foundation.h>


//! @abstract A collection of widely used methods that complement NSString.
@interface NSString (Connection)

//! @group Class Methods
/*!
	@abstract Returns a string describing the given byte-count in the most abbreviated form.
	@param sizeInBytes The number of bytes. 
	@discussion This method uses the same calculation that Mac OS X Snow Leopard does in determining file sizes -- that is, it uses powers of 10, not 2. Specifically, for example, 1 MB is equivalent to 1000 KB, etc. If sizeInBytes is less than 1 KB (i.e., less than 1000 bytes), it is returned as "sizeInBytes bytes".
	@result An abbreviated form that accurately describes the given sizeInBytes in bytes.
 */
+ (NSString *)formattedFileSize:(CGFloat)sizeInBytes;

//! @abstract Returns a universally unique identifier. Typically used for uniquely identifying objects.
+ (NSString *)UUID;

/*!
	@abstract Returns an NSString with the given bytes of an unknown encoding.
	@param bytes The bytes to convert to an NSString.
	@param length The number of bytes that bytes points to.	
	@discussion This method should only be used when the encoding of the bytes is unknown. It is more efficient to use the dedicated NSString initialization methods if the encoding is known.
	@result An NSString containing length characters taken from bytes.
 */
+ (NSString *)stringWithBytesOfUnknownEncoding:(char *)bytes length:(NSUInteger)length;

//! @group Encoding
/*!
	@abstract Encodes the receiver into a string appropriate for usage within a URL.
	@discussion This includes escaping all invalid characters for a URL, in addition to the '@' character, as it's used as a separator between the username/password and host, and the ':' character, as it's used to separate the username and password
	@result A string made by encoding the receiver into a string appropriate for usage within a URL.
 */
- (NSString *)encodeLegallyForURL;

/*!
	@abstract Encodes the receiver into a string appropriate for usage as a URI.
	@discussion This method is exclusively for usage with URIs. If you are encoding a string for a URL, use encodeLegallyForURL. If you are encoding a URI string for an Amazon S3 connection, use encodeLegallyForAmazonS3URI.
	@result A string made by encoding the receiver into a string appropriate for usage as a URI.
 */
- (NSString *)encodeLegallyForURI;

/*!
	@abstract Encodes the receiver into a string appropriate for usage as a URI over an Amazon S3 connection.
	@discussion This method is exclusively for usage with Amazon S3 URIs. If you are encoding a generic URI, use encodeLegallyForURI. If you are encoding a string for a URL, use encodeLegallyForURL.
	@result A string made by encoding the receiver into a string appropriate for usage as a URI over an Amazon S3 connection.
 */
- (NSString *)encodeLegallyForAmazonS3URI;

//! @group Convenience Methods

/*!
	@abstract Returns whether or not the receiver contains the given substring.
	@param substring The substring to search for within the receiver.
	@discussion This method is case insensitive.
	@result YES if the receiver contains the given substring, NO otherwise.
 */
- (BOOL)containsSubstring:(NSString *)substring;

/*!
	@abstract Returns the first path component of the receiver.
	@discussion Unless the receiver is equal to @"/", the first component is never the leading slash.
	@result The first path component of the receiver.
 */
- (NSString *)firstPathComponent;

/*!
	@abstract Returns the receiver, less the first path component.
	@discussion The first path component is determined by calling firstPathComponent on the receiver.
	@result A stirng made by removing the first path component from the receiver.
 */
- (NSString *)stringByDeletingFirstPathComponent;

/*! 
	@abstract Returns a string made by standardizing the receiver, and prefixing a leading "/", if one does not exist already.
	@discussion Path standardization is done by calling stringByStandardizingPath.
	@result A string made by standardizing the receiver and ensuring it is prefixed with a leading slash.
 */
- (NSString *)stringByStandardizingPathWithLeadingSlash;

//! @group URL Cooperation

/*!
	@abstract Returns a string made by standardizing the path components of the URL as represented by the receiver.
	@discussion This method ensures we only have one leading slash, and have no trailing slashes.
	@result A string made by standardizing the URL components of the receiver.
 */
- (NSString *)stringByStandardizingURLComponents;

/*!
	@abstract Returns a string made by appending the given URLComponent to the end of the receiver.
	@param The URL component to append.
	@result A string made by appending the given URL component to the end of the receiver.
 */
- (NSString *)stringByAppendingURLComponent:(NSString *)URLComponent;

@end
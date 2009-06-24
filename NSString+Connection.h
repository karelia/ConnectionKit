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


@interface NSString (Connection)

- (NSString *)encodeLegally;
- (NSString *)encodeLegallyForS3;
+ (NSString *)stringWithData:(NSData *)data encoding:(NSStringEncoding)encoding;

// Paths
- (NSString *)firstPathComponent;
- (NSString *)stringByDeletingFirstPathComponent;
- (NSString *)stringByDeletingFirstPathComponent2;
- (NSString *)stringByStandardizingHTTPPath;
- (NSString *)stringByAppendingDirectoryTerminator;

- (NSString *)stringByAppendingURLComponent:(NSString *)URLComponent;
- (NSString *)stringByStandardizingURLComponents;
+ (NSString *)formattedFileSize:(double)size;
+ (NSString *)formattedSpeed:(double)speed;
+ (id)uuid;
- (NSArray *)componentsSeparatedByCharactersInSet:(NSCharacterSet *)set;
- (BOOL)containsSubstring:(NSString *)substring;

//SFTP
+ ( NSString * )pathForExecutable: ( NSString * )executable;
- ( char )objectTypeFromOctalRepresentation: ( NSString * )octalRep;
- ( NSString * )stringRepresentationOfOctalMode;
+ ( NSString * )stringWithBytesOfUnknownEncoding: ( char * )bytes length: ( unsigned )len;
@end

@interface NSAttributedString (Connection)
+ (NSAttributedString *)attributedStringWithString:(NSString *)str attributes:(NSDictionary *)attribs;
@end

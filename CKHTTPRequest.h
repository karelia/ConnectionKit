/*
 Copyright (c) 2004-2006, Greg Hulands <ghulands@mac.com>
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

@class CKHTTPResponse;

@interface CKHTTPRequest : NSObject 
{
	NSString			*myMethod;
	NSString			*myURI;
	id					myUserInfo;
	
	NSMutableDictionary *myHeaders;
	NSMutableData		*myContent;
	unsigned			myHeaderLength;
	
	NSMutableDictionary *myPost;
	NSMutableDictionary *myUploads;
}

+ (id)requestWithMethod:(NSString *)method uri:(NSString *)uri;

- (id)initWithMethod:(NSString *)method uri:(NSString *)uri;

- (void)setHeader:(NSString *)val forKey:(NSString *)key;
- (void)addHeader:(NSString *)val forKey:(NSString *)key;
- (id)headerForKey:(NSString *)key;
- (NSDictionary *)headers;

- (void)setUserInfo:(id)ui;
- (id)userInfo;

- (void)setPostValue:(id)value forKey:(NSString *)key;
- (void)uploadFile:(NSString *)path forKey:(NSString *)key;
- (void)uploadData:(NSData *)data withFilename:(NSString *)name forKey:(NSString *)key;

- (void)appendContent:(NSData *)data;
- (void)appendContentString:(NSString *)str;
- (void)setContent:(NSData *)data;
- (void)setContentString:(NSString *)str;

- (NSData *)content;
- (NSString *)contentString;
- (NSString *)method;
- (NSString *)uri;

- (unsigned)contentLength;

- (void)serializeContentWithPacket:(NSMutableData *)packet; // subclasses override. packet is still in the header section at this point. only append your own headers if required, not your content
- (NSData *)serialized;
- (unsigned)headerLength; //only will contain a valid value after serialized is called

- (CKHTTPResponse *)responseWithData:(NSData *)data;

@end

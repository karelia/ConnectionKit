/*
 Copyright (c) 2005, Greg Hulands <ghulands@mac.com>
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
#import "StreamBasedConnection.h"

typedef enum {
	NNTP = 300
} NNTPState;

@interface NNTPConnection : StreamBasedConnection 
{
	NSMutableString *_inputBuffer;
	NSString *_currentNewsGroup;
	
	struct __newsflags {
		unsigned canPost: 1;
		unsigned isSlave: 1;
		unsigned unused: 30;
	} _newsflags;
}

@end

// Directory Contents Keys
extern NSString *NNTPFirstMessageKey;
extern NSString *NNTPLastMessageKey;
extern NSString *NNTPCanPostToGroupKey;
extern NSString *NNTPHeadersKey;
extern NSString *NNTPBodyKey;

// RFC 850 Required Header Keys
extern NSString *NNTPRelayVersionHeaderKey;
extern NSString *NNTPPostingVersionHeaderKey;
extern NSString *NNTPFromHeaderKey;
extern NSString *NNTPDateHeaderKey;
extern NSString *NNTPNewsGroupsHeaderKey;
extern NSString *NNTPSubjectHeaderKey;
extern NSString *NNTPMessageIDHeaderKey;
extern NSString *NNTPPathHeaderKey;
// RFC 850 Optional Header Keys
extern NSString *NNTPReplyToHeaderKey;
extern NSString *NNTPSenderHeaderKey;
extern NSString *NNTPFollowUpToHeaderKey;
extern NSString *NNTPDateReceivedHeaderKey;
extern NSString *NNTPExpiresHeaderKey;
extern NSString *NNTPReferencesHeaderKey;
extern NSString *NNTPControlHeaderKey;

@interface NSObject (NNTPConnectionDelegate)


@end

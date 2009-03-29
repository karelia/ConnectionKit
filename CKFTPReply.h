//
//  CKFTPResponse.h
//  Connection
//
//  Created by Mike on 24/03/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


// Terminology taken from RFC 959


typedef enum {
    CKFTPReplyTypePositivePreliminary = 1,
    CKFTPReplyTypePositiveCompletion = 2,
    CKFTPReplyTypePositiveIntermediate = 3,
    CKFTPReplyTypeTransientNegativeCompletion = 4,
    CKFTPReplyTypePermanentNegativeCompletion = 5
} CKFTPReplyType;


typedef enum {
    CKFTPReplyFunctionGroupSyntax = 0,
    CKFTPReplyFunctionGroupInformation = 1,
    CKFTPReplyFunctionGroupConnections = 2,
    CKFTPReplyFunctionGroupAuthenticationAndAccounting = 3,
    CKFTPReplyFunctionGroupUnspecified = 4,
    CKFTPReplyFunctionGroupFileSystem = 5
} CKFTPReplyFunctionGroup;


@interface CKFTPReply : NSObject <NSCopying>
{
    @protected
    NSUInteger  _replyCode;
    NSArray     *_textLines;
}

- (id)initWithReplyCode:(NSUInteger)code textLines:(NSArray *)lines;
- (id)initWithReplyCode:(NSUInteger)code text:(NSString *)text;

- (NSUInteger)replyCode;
- (NSString *)replyCodeString;
- (CKFTPReplyType)replyType;                    // the result of these two methods is undefined if
- (CKFTPReplyFunctionGroup)functionalGrouping;  // replyCode is invalid.

- (NSArray *)textLines;

- (NSArray *)serializedTelnetLines;
- (NSString *)description;  // overriden to nicely print -serializedTelnetLines
@end


// A semi-mutable subclass CKFTPReply that allows one to gradually fill it up with received data.
// CKStreamedFTPReply conforms to the NSCopying protocol through its superclass, and observes the
// standard mutable-immutable beahviour. i.e copying a CKStreamedFTPReply will return a CKFTPReply.
@interface CKStreamedFTPReply : CKFTPReply
{
    @private
    NSMutableData   *_data;
    NSUInteger      _scanLocation;
    NSMutableArray  *_multilineReplyBuffer;  // only initialised and used for multiline replies
}

- (id)init;  // use instead of -initWithReplyCode:text:

/*!
 @method appendData:nextData:
 @abstract Appends the received data to try and complete the reply. If there is more data after
 the end of the reply, it is returned by reference.
 @param data
 @param excess The leftover data not part of this reply. You can use this to start constructing
 more replies.
 @result YES if the data was valid and successfully appended. NO if the data was rejected.
 @discussion Raises an exception if the reply is already complete. We relax the RFC 959 spec
 slightly by allowing lines to terminate in either <CR><LF> or <LF>
 */
- (BOOL)appendData:(NSData *)data nextData:(NSData **)excess;

// Converts any instances of <CR><NUL> into <CR>
+ (NSData *)dataByUnescapingTelnetCarriageReturnsInData:(NSData *)data;

- (NSData *)data;   // the data received so far
- (BOOL)isComplete;
- (BOOL)hasReplyCode;   // whether enough data has been received to know the reply code

@end

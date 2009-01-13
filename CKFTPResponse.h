//
//  CKFTPResponse.h
//  Connection
//
//  Created by Mike on 13/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//


//  Immutable class to represent an FTP response in a similar fashion to NSURLResponse.


#import <Foundation/Foundation.h>


@interface CKFTPResponse : NSObject <NSCopying>
{
@private
    int     _code;
    NSArray *_lines;
}

/*!
 @method initWithLines:
 @abstract FTP servers return a response consisting of one or more lines. Creates a repsonse
 object from the provided lines.
 @param responseLines An array of NSStrings, each one a line of the response.
 @result The initialized NSURLResponse or nil if the supplied lines are not a valid FTP response.
 @discussion This is the designated initializer for CKFTPResponse.
 */
- (id)initWithLines:(NSArray *)responseLines;

/*!
 @method initWithString:
 @abstract Convenience method to initalize a CKFTPResponse when only the first line has been received
 @param responseString The first line of the response
 @result The initialized NSURLResponse or nil if the string is not a valid FTP response.
 */
- (id)initWithString:(NSString *)responseString;

/*!
 @method code
 @result The FTP response code. Will be in the range 100-599.
 */
- (unsigned)code;

/*!
 @method lines
 @result An array of NSString objects that were returned by the server. Contains at least one line.
 */
- (NSArray *)lines;

/*!
 @method isMark
 @abstract Multi-line responses are required to begin with the response code follwed by a hyphen.
 @result YES if the response is incomplete and awaiting more lines.
 */
- (BOOL)isMark;

@end

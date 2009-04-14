//
//  CKFTPRequest.h
//  Connection
//
//  Created by Mike on 24/03/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//


// All terminology follows RFC 959


#import <Cocoa/Cocoa.h>


@interface CKFTPCommand : NSObject <NSCopying>
{
    NSString    *_commandCode;
    NSString    *_argumentField;
}

+ (CKFTPCommand *)commandWithCode:(NSString *)code argumentField:(NSString *)argumentField;
+ (CKFTPCommand *)commandWithCode:(NSString *)code;

/*! 
 @param code Must be 3 or 4 ASCII characters otherwise an exception is raised.
 @param argumentField Optional. Passing an empty string will raise an exception.
 @discussion Designated initializer.
 */
- (id)initWithCommandCode:(NSString *)code argumentField:(NSString *)argumentField;
- (id)initWithCommandCode:(NSString *)code;

- (NSString *)commandCode;
- (NSString *)argumentField;

/*!
 @method serializedCommand
 @abstract Serialises the command in a fashion suitable for sending to an FTP server.
 @result The serialized command.
 @discussion Includes the <CR><LF> sequence used to indicate the end of the command.
 */
- (NSData *)serializedCommand;

- (NSString *)description;  // Puts the command code and argument field together

@end


// TODO: How should illegal characters be handled?
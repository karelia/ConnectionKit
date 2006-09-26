//
//  NSString+Connection.h
//  Connection
//
//  Created by Greg Hulands on 19/09/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSString (Connection)
- (NSString *)encodeLegally;
+ (NSString *)stringWithData:(NSData *)data encoding:(NSStringEncoding)encoding;
- (NSString *)firstPathComponent;
- (NSString *)stringByDeletingFirstPathComponent;

@end

@interface NSAttributedString (Connection)
+ (NSAttributedString *)attributedStringWithString:(NSString *)str attributes:(NSDictionary *)attribs;
@end

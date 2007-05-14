//
//  NSFileManager+Connection.h
//  Connection
//
//  Created by Greg Hulands on 16/03/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface NSFileManager (Connection)

- (void)recursivelyCreateDirectory:(NSString *)path attributes:(NSDictionary *)attributes;
- (unsigned long long)sizeOfPath:(NSString *)path;

@end

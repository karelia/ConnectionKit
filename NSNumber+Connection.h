//
//  NSNumber+Connection.h
//  Connection
//
//  Created by Greg Hulands on 7/09/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface NSNumber (Connection)

- (BOOL)isExecutable;
- (NSString *)permissionsStringValue;

@end

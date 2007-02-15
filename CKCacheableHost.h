//
//  CKCacheableHost.h
//  Connection
//
//  Created by Greg Hulands on 16/02/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface CKCacheableHost : NSObject 
{
	
}

+ (NSHost *)hostWithName:(NSString *)name;
+ (NSHost *)hostWithAddress:(NSString *)address;

@end

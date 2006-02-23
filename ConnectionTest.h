//
//  ConnectionTest.h
//  Marvel
//
//  Created by Dan Wood on 11/29/04.
//  Copyright (c) 2004 Biophony, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface ConnectionTest : NSObject {

	NSMutableDictionary *myCallbackDictionary;
	unsigned long 		myUniqueNumber;
	
	NSThread			*myMainThread;	// not retained.  Just for diagnostics.

	NSString *myCurrentDirectory;
	
}

- (NSMutableDictionary *)callbackDictionary;
- (void)setCallbackDictionary:(NSMutableDictionary *)aCallbackDictionary;

- (NSString *)currentDirectory;
- (void)setCurrentDirectory:(NSString *)aCurrentDirectory;


@end

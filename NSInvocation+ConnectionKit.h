//
//  NSInvocation+ConnectionKit.h
//  Connection
//
//  Created by Mike on 22/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface NSInvocation (ConnectionKit)
+ (NSInvocation *)invocationWithTarget:(id)aTarget selector:(SEL)aSelector arguments:(NSArray *)anArgumentArray;
+ (NSInvocation *)invocationWithTarget:(id)aTarget selector:(SEL)aSelector;
@end

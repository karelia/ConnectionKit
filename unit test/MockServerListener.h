// --------------------------------------------------------------------------
//! @author Sam Deane
//
//  Copyright 2012 Sam Deane, Elegant Chaos. All rights reserved.
//  This source code is distributed under the terms of Elegant Chaos's 
//  liberal license: http://www.elegantchaos.com/license/liberal
// --------------------------------------------------------------------------

#import <Foundation/Foundation.h>

@interface MockServerListener : NSObject

typedef BOOL (^ConnectionBlock)(int socket);

@property (readonly, nonatomic) NSUInteger port;

+ (MockServerListener*)listenerWithPort:(NSUInteger)port connectionBlock:(ConnectionBlock)block;

- (id)initWithPort:(NSUInteger)port connectionBlock:(ConnectionBlock)block;

- (BOOL)start;
- (void)stop:(NSString*)reason;

@end

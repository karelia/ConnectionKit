// --------------------------------------------------------------------------
//! @author Sam Deane
//
//  Copyright 2012 Sam Deane, Elegant Chaos. All rights reserved.
//  This source code is distributed under the terms of Elegant Chaos's 
//  liberal license: http://www.elegantchaos.com/license/liberal
// --------------------------------------------------------------------------

#import <Foundation/Foundation.h>

#define MockServerLog NSLog
#define MockServerAssert(x) assert((x))

@interface MockServer : NSObject<NSStreamDelegate>

@property (readonly, nonatomic) BOOL running;

+ (MockServer*)serverWithResponses:(NSDictionary*)responses;
+ (MockServer*)serverWithPort:(NSUInteger)port responses:(NSDictionary*)responses;

- (id)initWithPort:(NSUInteger)port responses:(NSDictionary*)responses;

- (void)start;
- (void)stop;
- (void)runUntilStopped;

@end

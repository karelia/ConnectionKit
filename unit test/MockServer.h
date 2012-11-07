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

@property (strong, nonatomic) NSData* data;
@property (readonly, nonatomic) NSUInteger port;
@property (strong, nonatomic) NSOperationQueue* queue;
@property (readonly, atomic) BOOL running;

+ (MockServer*)serverWithResponses:(NSArray*)responses;
+ (MockServer*)serverWithPort:(NSUInteger)port responses:(NSArray*)responses;

- (id)initWithPort:(NSUInteger)port responses:(NSArray*)responses;

- (void)start;
- (void)stop;
- (void)runUntilStopped;

- (NSDictionary*)standardSubstitutions;

@end

extern NSString *const CloseCommand;
extern NSString *const InitialResponseKey;

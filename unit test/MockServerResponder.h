// --------------------------------------------------------------------------
//! @author Sam Deane
//
//  Copyright 2012 Sam Deane, Elegant Chaos. All rights reserved.
//  This source code is distributed under the terms of Elegant Chaos's 
//  liberal license: http://www.elegantchaos.com/license/liberal
// --------------------------------------------------------------------------

#import <Foundation/Foundation.h>

@class MockServer;

@interface MockServerResponder : NSObject

@property (strong, nonatomic, readonly) NSArray* initialResponse;

+ (MockServerResponder*)responderWithResponses:(NSArray*)responses;

- (id)initWithResponses:(NSArray*)responses;

- (NSArray*)responseForRequest:(NSString*)request substitutions:(NSDictionary*)substitutions;

@end

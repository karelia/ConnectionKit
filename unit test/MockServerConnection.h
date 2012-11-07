// --------------------------------------------------------------------------
//! @author Sam Deane
//
//  Copyright 2012 Sam Deane, Elegant Chaos. All rights reserved.
//  This source code is distributed under the terms of Elegant Chaos's 
//  liberal license: http://www.elegantchaos.com/license/liberal
// --------------------------------------------------------------------------

#import <Foundation/Foundation.h>

@class MockServer;
@class MockServerResponder;

@interface MockServerConnection : NSObject<NSStreamDelegate>

+ (MockServerConnection*)connectionWithSocket:(int)socket responder:(MockServerResponder*)responder server:(MockServer*)server;

- (id)initWithSocket:(int)socket responder:(MockServerResponder*)responder server:(MockServer *)server;

- (void)cancel;

@end

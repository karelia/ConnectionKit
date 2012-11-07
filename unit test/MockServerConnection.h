//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MockServer;
@class MockServerResponder;

@interface MockServerConnection : NSObject<NSStreamDelegate>

+ (MockServerConnection*)connectionWithSocket:(int)socket responder:(MockServerResponder*)responder server:(MockServer*)server;

- (id)initWithSocket:(int)socket responder:(MockServerResponder*)responder server:(MockServer *)server;

- (void)cancel;

@end

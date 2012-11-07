// --------------------------------------------------------------------------
//! @author Sam Deane
//
//  Copyright 2012 Sam Deane, Elegant Chaos. All rights reserved.
//  This source code is distributed under the terms of Elegant Chaos's 
//  liberal license: http://www.elegantchaos.com/license/liberal
// --------------------------------------------------------------------------

#import <Foundation/Foundation.h>

#import <sys/socket.h>
#import <netinet/in.h>   // for IPPROTO_TCP, sockaddr_in

#import "MockServer.h"
#import "MockServerConnection.h"
#import "MockServerListener.h"
#import "MockServerResponder.h"

@interface MockServer()

@property (strong, nonatomic) MockServerConnection* connection;
@property (strong, nonatomic) MockServerListener* listener;
@property (strong, nonatomic) MockServerResponder* responder;
@property (assign, atomic) BOOL running;

@end

@implementation MockServer

@synthesize connection = _connection;
@synthesize data = _data;
@synthesize listener = _listener;
@synthesize queue = _queue;
@synthesize responder = _responder;
@synthesize running = _running;

NSString *const CloseCommand = @"«close»";
NSString *const InitialResponseKey = @"«initial»";

#pragma mark - Object Lifecycle

+ (MockServer*)serverWithResponses:(NSArray*)responses
{
    MockServer* server = [[MockServer alloc] initWithPort:0 responses:responses];

    return [server autorelease];
}

+ (MockServer*)serverWithPort:(NSUInteger)port responses:(NSArray*)responses
{
    MockServer* server = [[MockServer alloc] initWithPort:port responses:responses];

    return [server autorelease];
}

- (id)initWithPort:(NSUInteger)port responses:(NSArray*)responses
{
    if ((self = [super init]) != nil)
    {
        self.queue = [NSOperationQueue currentQueue];
        self.responder = [MockServerResponder responderWithResponses:responses];
        self.listener = [MockServerListener listenerWithPort:port connectionBlock:^BOOL(int socket) {
            MockServerAssert(socket != 0);

            BOOL ok = self.connection == nil;
            if (ok)
            {
                MockServerLog(@"received connection");
                self.connection = [MockServerConnection connectionWithSocket:socket responder:self.responder server:self];
            }

            return ok;
        }];
    }

    return self;
}

- (void)dealloc
{
    [_connection release];
    [_data release];
    [_queue release];
    [_responder release];
    
    [super dealloc];
}

#pragma mark - Public API

- (void)start
{
    BOOL success = [self.listener start];
    if (success)
    {
        MockServerAssert(self.port != 0);
        MockServerLog(@"server started on port %ld", self.port);
        self.running = YES;
    }
}

- (void)stop
{
    [self.connection cancel];
    [self.listener stop:@"stopped externally"];
    self.running = NO;
}

- (void)runUntilStopped
{
    while (self.running)
    {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
        }
    }
}

- (NSUInteger)port
{
    return self.listener.port;
}

@end

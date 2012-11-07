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

@property (strong, nonatomic) MockServerListener* extraListener;
@property (strong, nonatomic) MockServerConnection* extraConnection;

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

    [_extraConnection release];
    [_extraListener release];

    [super dealloc];
}

#pragma mark - Public API

- (void)start
{
    BOOL success = [self.listener start];
    if (success)
    {
        [self makeDataListener];

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

#pragma mark - Substitutions


- (NSDictionary*)standardSubstitutions
{
    NSUInteger extraPort = self.extraListener.port;
    NSDictionary* substitutions =
    @{
    @"$address" : @"127.0.0.1",
    @"$server" : @"fakeserver 20121107",
    @"$size" : [NSString stringWithFormat:@"%ld", (long) [self.data length]],
    @"$pasv" : [NSString stringWithFormat:@"127,0,0,1,%ld,%ld", extraPort / 256L, extraPort % 256L]
    };

    return substitutions;
}

#pragma mark - Data Connection

- (void)makeDataListener
{
    __block MockServer* server = self;
    self.extraListener = [MockServerListener listenerWithPort:0 connectionBlock:^BOOL(int socket) {

        MockServerLog(@"got connection on data listener");
        BOOL ok = self.extraConnection == nil;
        if (ok)
        {
            NSArray* responses = @[ @[InitialResponseKey, server.data, CloseCommand ] ];
            MockServerResponder* responder = [MockServerResponder responderWithResponses:responses];
            server.extraConnection = [MockServerConnection connectionWithSocket:socket responder:responder server:server];

            // we're done with the listener now
            [server performSelector:@selector(disposeDataListener) withObject:nil afterDelay:0.0];
        }

        return ok;
    }];

    [self.extraListener start];
}

- (void)disposeDataListener
{
    [self.extraListener stop:@"finished with data listener"];
    self.extraListener = nil;
}

@end

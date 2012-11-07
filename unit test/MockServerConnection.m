// --------------------------------------------------------------------------
//! @author Sam Deane
//
//  Copyright 2012 Sam Deane, Elegant Chaos. All rights reserved.
//  This source code is distributed under the terms of Elegant Chaos's
//  liberal license: http://www.elegantchaos.com/license/liberal
// --------------------------------------------------------------------------

#import <Foundation/Foundation.h>

#import "MockServerConnection.h"

#import "MockServer.h"
#import "MockServerListener.h"
#import "MockServerResponder.h"

@interface MockServerConnection()

@property (strong, nonatomic) NSInputStream* input;
@property (strong, nonatomic) NSOutputStream* output;
@property (strong, nonatomic) NSMutableData* outputData;
@property (strong, nonatomic) MockServerResponder* responder;
@property (strong, nonatomic) MockServer* server;

// TODO: move these elsewhere?
@property (strong, nonatomic) MockServerListener* extraListener;
@property (strong, nonatomic) MockServerConnection* extraConnection;

@end

@implementation MockServerConnection

@synthesize input   = _input;
@synthesize output = _output;
@synthesize outputData = _outputData;
@synthesize responder = _responder;
@synthesize server = _server;

#pragma mark - Object Lifecycle

+ (MockServerConnection*)connectionWithSocket:(int)socket responder:(MockServerResponder*)responder server:(MockServer *)server
{
    MockServerConnection* connection = [[MockServerConnection alloc] initWithSocket:socket responder:responder server:server];

    return [connection autorelease];
}

- (id)initWithSocket:(int)socket responder:(MockServerResponder*)responder server:(MockServer *)server
{
    if ((self = [super init]) != nil)
    {
        self.server = server;
        self.responder = responder;
        self.outputData = [NSMutableData data];

        CFReadStreamRef readStream;
        CFWriteStreamRef writeStream;
        CFStreamCreatePairWithSocket(NULL, socket, &readStream, &writeStream);

        self.input = [self setupStream:(NSStream*)readStream];
        self.output = [self setupStream:(NSStream*)writeStream];

        [self makeExtraListener];
    }

    return self;
}

- (void)dealloc
{
    [_input release];
    [_output release];
    [_outputData release];
    [_server release];

    [_extraConnection release];
    [_extraListener release];
    
    [super dealloc];
}

#pragma mark - Public API

- (void)cancel
{
    [self disconnectStreams:@"cancelled"];
}

#pragma mark - Data Processing

- (void)processInput
{
    uint8_t buffer[32768];
    NSInteger bytesRead = [self.input read:buffer maxLength:sizeof(buffer)];
    if (bytesRead == -1)
    {
        [self disconnectStreams:@"Network read error"];
    }

    else if (bytesRead == 0)
    {
        [self disconnectStreams:@"No more data"];
    }

    else
    {
        NSUInteger extraPort = self.extraListener.port;
        NSDictionary* substitutions = @{ @"$pasv" : [NSString stringWithFormat:@"127,0,0,1,%ld,%ld", extraPort / 256L, extraPort % 256L] };
        NSString* request = [[NSString alloc] initWithBytes:buffer length:bytesRead encoding:NSUTF8StringEncoding];
        MockServerLog(@"got request '%@'", request);
        NSArray* commands = [self.responder responseForRequest:request substitutions:substitutions];
        if (commands)
        {
            [self processCommands:commands];
        }
        else
        {
            // if nothing matched, close the connection
            // to prevent this, add a key of ".*" as the last response in the array
            [self processCommands:@[CloseCommand]];
        }

        [request release];
    }
}

- (void)processClose
{
    MockServerLog(@"closed connection");
    [self.output close];
    [self.input close];
}

- (void)queueOutput:(id)string
{
    MockServerLog(@"queued output %@", string);
    [self.outputData appendData:[string dataUsingEncoding:NSUTF8StringEncoding]];
    [self processOutput];
}

- (void)processCommands:(NSArray*)commands
{
    NSTimeInterval delay = 0.0;
    for (id command in commands)
    {
        if ([command isKindOfClass:[NSNumber class]])
        {
            delay += [command doubleValue];
        }
        else
        {
            SEL method;
            if ([command isEqual:CloseCommand])
            {
                method = @selector(processClose);
            }
            else if ([command isEqual:ListenCommand])
            {
                method = @selector(processListen);
            }
            else
            {
                method = @selector(queueOutput:);
            }

            [self performSelector:method withObject:command afterDelay:delay];
        }
    }
}

- (void)processListen
{
    if (self.extraListener)
    {
        MockServerLog(@"asked to make another extra listener - ignoring");
    }
    else
    {
    }
}

- (void)makeExtraListener
{
    MockServerLog(@"asked to make a listening connection");
    self.extraListener = [MockServerListener listenerWithPort:0 connectionBlock:^BOOL(int socket) {

        MockServerLog(@"got connection on extra listener");
        BOOL ok = self.extraConnection == nil;
        if (ok)
        {
            NSArray* responses = @[ @[InitialResponseKey, @"This is a test response", CloseCommand ] ];
            MockServerResponder* responder = [MockServerResponder responderWithResponses:responses];
            self.extraConnection = [MockServerConnection connectionWithSocket:socket responder:responder server:self.server];

            // we're done with the listener now
            MockServerListener* listener = self.extraListener;
            [listener retain];
            [listener stop:@"passive connection made"];
            self.extraListener = nil;
            [listener autorelease];
        }

        return ok;
    }];

    [self.extraListener start];
}

- (void)processOutput
{
    NSUInteger bytesToWrite = [self.outputData length];
    if (bytesToWrite)
    {
        NSUInteger written = [self.output write:[self.outputData bytes] maxLength:bytesToWrite];
        [self.outputData replaceBytesInRange:NSMakeRange(0, written) withBytes:nil length:0];

        MockServerLog(@"wrote %ld bytes", (long)written);
    }
}

#pragma mark - Streams

- (id)setupStream:(NSStream*)stream
{
    MockServerAssert(stream);

    [stream setProperty:(id)kCFBooleanTrue forKey:(NSString *)kCFStreamPropertyShouldCloseNativeSocket];
    stream.delegate = self;
    [stream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [stream open];
    CFRelease(stream);

    return stream;
}

- (void)cleanupStream:(NSStream*)stream
{
    if (stream)
    {
        stream.delegate = nil;
        [stream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [stream close];
    }
}
- (void)disconnectStreams:(NSString*)reason
{
    [self cleanupStream:self.input];
    self.input = nil;

    [self cleanupStream:self.output];
    self.output = nil;

    MockServerLog(@"disconnected: %@", reason);
}

- (NSString*)nameForStream:(NSStream*)stream
{
    NSString* result;
    if (stream == self.input)
    {
        result = @"input";
    }
    else if (stream == self.output)
    {
        result = @"output";
    }
    else
    {
        result = @"unknown";
    }

    return result;
}

- (void)stream:(NSStream*)stream handleEvent:(NSStreamEvent)eventCode
{
    MockServerAssert((stream == self.input) || (stream == self.output));

    switch (eventCode)
    {
        case NSStreamEventOpenCompleted:
        {
            MockServerLog(@"opened %@ stream", [self nameForStream:stream]);
            if (stream == self.input)
            {
                [self processCommands:self.responder.initialResponse];
            }
            break;
        }

        case NSStreamEventHasBytesAvailable:
        {
            [self processInput];
            break;
        }

        case NSStreamEventHasSpaceAvailable:
        {
            MockServerAssert(stream == self.output);     // should never happen for the input stream
            [self processOutput];
            break;
        }

        case NSStreamEventErrorOccurred:
        {
            MockServerLog(@"got error for %@ stream", [self nameForStream:stream]);
            [self disconnectStreams:@"Stream open error"];
            break;
        }

        case NSStreamEventEndEncountered:
        {
            MockServerLog(@"got eof for %@ stream", [self nameForStream:stream]);
            break;
        }

        default:
        {
            MockServerLog(@"unknown event for %@ stream", [self nameForStream:stream]);
            MockServerAssert(NO);
            break;
        }
    }
}

@end

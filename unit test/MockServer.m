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

@interface MockServer()

@property (strong, nonatomic) NSInputStream* input;
@property (assign, nonatomic) CFSocketRef listener;
@property (strong, nonatomic) NSOutputStream* output;
@property (strong, nonatomic) NSMutableData* outputData;
@property (assign, nonatomic) NSUInteger port;
@property (strong, nonatomic) NSArray* requests;
@property (strong, nonatomic) NSArray* responses;
@property (strong, nonatomic) NSArray* initialResponse;
@property (assign, atomic) BOOL running;

@end

@implementation MockServer

@synthesize input   = _input;
@synthesize listener = _listener;
@synthesize output = _output;
@synthesize outputData = _outputData;
@synthesize port = _port;
@synthesize queue = _queue;
@synthesize requests = _requests;
@synthesize responses = _responses;
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
        self.port = port;
        self.outputData = [NSMutableData data];
        self.queue = [NSOperationQueue currentQueue];

        // process responses array - we pull out some special responses, and pre-calculate all the regular expressions
        NSRegularExpressionOptions options = NSRegularExpressionDotMatchesLineSeparators;
        NSMutableArray* processed = [NSMutableArray arrayWithCapacity:[responses count]];
        NSMutableArray* expressions = [NSMutableArray arrayWithCapacity:[responses count]];
        for (NSArray* response in responses)
        {
            NSUInteger length = [response count];
            if (length > 0)
            {
                NSString* key = response[0];
                NSArray* commands = [response subarrayWithRange:NSMakeRange(1, length - 1)];
                if ([key isEqualToString:InitialResponseKey])
                {
                    self.initialResponse = commands;
                }
                else
                {
                    NSError* error = nil;
                    NSRegularExpression* expression = [NSRegularExpression regularExpressionWithPattern:key options:options error:&error];
                    if (expression)
                    {
                        [expressions addObject:expression];
                        [processed addObject:commands];
                    }
                }
            }
        }
        self.requests = expressions;
        self.responses = processed;

        MockServerLog(@"made server at port %ld", (long) port);
    }

    return self;
}

- (void)dealloc
{
    [_input release];
    [_output release];
    [_outputData release];
    [_queue release];
    [_responses release];
    [_requests release];
    
    [super dealloc];
}

#pragma mark - Public API

- (void)start
{
    [self startServer];
}

- (void)stop
{
    [self stopServer:@"Stopped externally"];
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


#pragma mark - Start / Stop

- (void)startServer
{
    int socket;

    BOOL success = [self makeSocket:&socket];
    if (success)
    {
        success = [self bindSocket:socket];
    }

    if (success)
    {
        success = [self listenOnSocket:socket];
    }

    if (success && (self.port == 0))
    {
        success = [self retrievePortForSocket:socket];
    }

    if (success)
    {
        success = [self makeCFSocketForSocket:socket];
    }

    if (success)
    {
        MockServerAssert(self.port != 0);
        NSLog(@"server started on port %ld", self.port);
        self.running = YES;
    }
    else
    {
        [self stopServer:@"Start failed"];
        if (socket != -1)
        {
            int err = close(socket);
            if (!err)
            {
                MockServerLog(@"couldn't close socket %d", socket);
            }
        }
    }
}

- (void)stopServer:(NSString *)reason
{

    if (self.input)
    {
        [self disconnectStreams:@"Cancelled"];
    }

    if (self.listener)
    {
        CFSocketInvalidate(self.listener);
        CFRelease(self.listener);
        self.listener = NULL;
    }

    self.running = NO;
    NSLog(@"server stopped with reason %@", reason);
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
        NSString* request = [[NSString alloc] initWithBytes:buffer length:bytesRead encoding:NSUTF8StringEncoding];
        NSRange wholeString = NSMakeRange(0, [request length]);

        MockServerLog(@"got request '%@'", request);

        BOOL matched = NO;
        NSUInteger count = [self.requests count];
        for (NSUInteger n = 0; n < count; ++n)
        {
            NSRegularExpression* expression = self.requests[n];
            NSTextCheckingResult* match = [expression firstMatchInString:request options:0 range:wholeString];
            if (match)
            {
                MockServerLog(@"matched with request pattern %@", expression);
                NSArray* commands = self.responses[n];
                [self processCommands:commands request:request match:match];
                matched = YES;
                break;
            }
        }

        if (!matched)
        {
            // if nothing matched, close the connection
            // to prevent this, add a key of ".*" as the last response in the array
            [self performSelector:@selector(processClose) withObject:nil afterDelay:0.0];
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

- (void)processCommands:(NSArray*)commands request:(NSString*)request match:(NSTextCheckingResult*)match
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
            else
            {
                BOOL containsTokens = [command rangeOfString:@"$"].location != NSNotFound;
                if (containsTokens)
                {
                    // always add the request as $0
                    NSMutableDictionary* replacements = [NSMutableDictionary dictionary];
                    [replacements setObject:request forKey:@"$0"];

                    // add any matched subgroups
                    if (match)
                    {
                        NSUInteger count = match.numberOfRanges;
                        for (NSUInteger n = 1; n < count; ++n)
                        {
                            NSString* token = [NSString stringWithFormat:@"$%ld", (long) n];
                            NSRange range = [match rangeAtIndex:n];
                            NSString* replacement = [request substringWithRange:range];
                            [replacements setObject:replacement forKey:token];
                        }
                    }

                    // perform replacements
                    NSMutableString* replaced = [NSMutableString stringWithString:command];
                    [replacements enumerateKeysAndObjectsUsingBlock:^(id key, id replacement, BOOL *stop) {
                        [replaced replaceOccurrencesOfString:key withString:replacement options:0 range:NSMakeRange(0, [replaced length])];
                    }];

                    MockServerLog(@"expanded response %@ as %@", command, replaced);
                    command = replaced;
                }
                
                method = @selector(queueOutput:);
            }
            
            [self performSelector:method withObject:command afterDelay:delay];
        }
    }
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
    else
    {
        MockServerLog(@"nothing to write");
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
                [self processCommands:self.initialResponse request:nil match:nil];
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

#pragma mark - Sockets

- (void)acceptConnectionOnSocket:(int)socket
{
    MockServerAssert(socket >= 0);

    if ((self.input) || (self.output))
    {
        MockServerLog(@"received connection twice - ignoring second one");
        int error = close(socket);
        MockServerAssert(error == 0);
    }
    else
    {
        MockServerLog(@"received connection");

        CFReadStreamRef readStream;
        CFWriteStreamRef writeStream;
        CFStreamCreatePairWithSocket(NULL, socket, &readStream, &writeStream);

        self.input = [self setupStream:(NSStream*)readStream];
        self.output = [self setupStream:(NSStream*)writeStream];
    }
}

static void callbackAcceptConnection(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    MockServer* obj = (MockServer*)info;
    MockServerAssert(type == kCFSocketAcceptCallBack);
    MockServerAssert(obj && (obj.listener == s));
    MockServerAssert(data);

    if (obj && data && (type == kCFSocketAcceptCallBack))
    {
        int socket = *((int*)data);
        [obj acceptConnectionOnSocket:socket];
    }
}

- (BOOL)makeSocket:(int*)socketOut
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (socketOut)
        *socketOut = fd;

    BOOL result = (fd != -1);

    if (result)
    {
        MockServerLog(@"got socket %d", fd);
    }
    else
    {
        MockServerLog(@"couldn't make socket");
    }

    return result;
}

- (BOOL)bindSocket:(int)socket
{
    struct sockaddr_in  addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len    = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(self.port);
    addr.sin_addr.s_addr = INADDR_ANY;
    int err = bind(socket, (const struct sockaddr *) &addr, sizeof(addr));
    BOOL result = (err == 0);
    if (!result)
    {
        MockServerLog(@"couldn't bind socket %d, error %d", socket, err);
    }
    
    return result;
}

- (BOOL)listenOnSocket:(int)socket
{
    int err = listen(socket, 5);
    BOOL result = err == 0;

    if (!result)
    {
        MockServerLog(@"couldn't listen on socket %d", socket);
    }

    return result;
}

- (BOOL)retrievePortForSocket:(int)socket
{
    // If we bound to port 0 the kernel will have assigned us a port.
    // use getsockname to find out what port number we actually got.
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len    = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(self.port);
    addr.sin_addr.s_addr = INADDR_ANY;
    socklen_t addrLen = sizeof(addr);
    int err = getsockname(socket, (struct sockaddr *) &addr, &addrLen);
    BOOL result = (err == 0);
    if (result)
    {
        MockServerAssert(addrLen == sizeof(addr));
        self.port = ntohs(addr.sin_port);
    }
    else
    {
        MockServerLog(@"couldn't retrieve socket port");
    }

    return result;
}

- (BOOL)makeCFSocketForSocket:(int)socket
{
    CFSocketContext context = { 0, (void *) self, NULL, NULL, NULL };

    MockServerAssert(self.listener == NULL);
    self.listener = CFSocketCreateWithNative(NULL, socket, kCFSocketAcceptCallBack, callbackAcceptConnection, &context);

    BOOL result = (self.listener != nil);
    if (result)
    {
        CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, self.listener, 0);
        MockServerAssert(source);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        CFRelease(source);
    }
    else
    {
        MockServerLog(@"couldn't make CFSocket for socket %d", socket);
    }

    return result;
}

@end

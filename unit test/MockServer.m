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
@property (strong, nonatomic) NSDictionary* responses;
@property (assign, nonatomic) BOOL running;

@end

@implementation MockServer

@synthesize running = _running;
@synthesize port = _port;
@synthesize responses = _responses;
@synthesize outputData = _outputData;
@synthesize input   = _input;
@synthesize output = _output;
@synthesize listener = _listener;

#pragma mark - Object Lifecycle

+ (MockServer*)serverWithResponses:(NSDictionary*)responses
{
    MockServer* server = [[MockServer alloc] initWithPort:0 responses:responses];

    return [server autorelease];
}

+ (MockServer*)serverWithPort:(NSUInteger)port responses:(NSDictionary*)responses
{
    MockServer* server = [[MockServer alloc] initWithPort:port responses:responses];

    return [server autorelease];
}

- (id)initWithPort:(NSUInteger)port responses:(NSDictionary*)responses
{
    if ((self = [super init]) != nil)
    {
        self.port = port;
        self.responses = responses;
        self.outputData = [NSMutableData data];
        MockServerLog(@"made server at port %ld", (long) port);
    }

    return self;
}

- (void)dealloc
{
    [_input release];
    [_output release];
    [_outputData release];

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
        NSString* string = [[NSString alloc] initWithBytes:buffer length:bytesRead encoding:NSUTF8StringEncoding];
        MockServerLog(@"got data %@", string);

        NSString* output = @"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=iso-8859-1\r\n\r\n<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\"><html><head><title>example</title></head><body>example result</body></html>\n";

        [self.outputData appendData:[output dataUsingEncoding:NSUTF8StringEncoding]];
        [self performSelector:@selector(processOutput) withObject:nil afterDelay:0.0];

        [string release];
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
        [self.output close];
        [self.input close];
    }
}

#pragma mark - Streams

- (id)setupStream:(NSStream*)stream
{
    MockServerAssert(stream);
    CFRelease(stream);

    [stream setProperty:(id)kCFBooleanTrue forKey:(NSString *)kCFStreamPropertyShouldCloseNativeSocket];
    stream.delegate = self;
    [stream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [stream open];

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
    MockServerAssert(CFSocketGetNative(self.listener) == socket);
    if ((self.input) || (self.output))
    {
        MockServerLog(@"received connection twice - something wrong");
        int error = close(socket);
        MockServerAssert(error == 0);
    }
    else
    {
        MockServerLog(@"received connection");

        MockServerAssert(socket >= 0);
        MockServerAssert((self.input == nil) && (self.output == nil));

        CFReadStreamRef     readStream;
        CFWriteStreamRef    writeStream;
        CFStreamCreatePairWithSocket(NULL, socket, &readStream, &writeStream);

        self.input = [self setupStream:(NSStream*)readStream];
        self.output = [self setupStream:(NSStream*)writeStream];
    }
}

static void callbackAcceptConnection(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    MockServerAssert(type == kCFSocketAcceptCallBack);
    MockServerAssert(data);
    MockServerAssert(info);

    if (info && data && (type == kCFSocketAcceptCallBack))
    {
        int socket = *((int*)data);
        MockServer* obj = (MockServer*)info;
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

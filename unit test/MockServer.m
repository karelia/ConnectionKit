// --------------------------------------------------------------------------
//! @author Sam Deane
//
//  Copyright 2012 Sam Deane, Elegant Chaos. All rights reserved.
//  This source code is distributed under the terms of Elegant Chaos's 
//  liberal license: http://www.elegantchaos.com/license/liberal
// --------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <SenTestingKit/SenTestingKit.h>

#import <sys/socket.h>
#import <netinet/in.h>   // for IPPROTO_TCP, sockaddr_in

#define MockServerLog NSLog
#define MockServerAssert(x) assert((x))

@interface ECTestServer : NSObject<NSStreamDelegate>
{
    NSUInteger _port;
    NSDictionary* _responses;
    dispatch_queue_t _queue;
}

+ (ECTestServer*)serverWithPort:(NSUInteger)port responses:(NSDictionary*)responses;
- (id)initWithPort:(NSUInteger)port responses:(NSDictionary*)responses;

@end

@interface ECTestServer()

@property (assign, nonatomic) NSUInteger port;
@property (strong, nonatomic) NSDictionary* responses;
@property (strong, nonatomic) NSMutableData* outputData;

@property (nonatomic, assign, readwrite) CFSocketRef        listeningSocket;
@property (nonatomic, strong, readwrite) NSInputStream *    input;
@property (nonatomic, strong, readwrite) NSOutputStream *   output;

@end

@implementation ECTestServer

@synthesize port = _port;
@synthesize responses = _responses;
@synthesize outputData = _outputData;
@synthesize input   = _input;
@synthesize output = _output;
@synthesize listeningSocket = _listeningSocket;

+ (ECTestServer*)serverWithPort:(NSUInteger)port responses:(NSDictionary*)responses
{
    ECTestServer* server = [[ECTestServer alloc] initWithPort:port responses:responses];

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

- (void)startReceive:(int)fd
{
    MockServerLog(@"received connection");

    CFReadStreamRef     readStream;
    CFWriteStreamRef    writeStream;

    MockServerAssert(fd >= 0);
    MockServerAssert(self.input == nil);      // can't already be receiving
    MockServerAssert(self.output == nil);      // can't already be receiving

    // Open a stream based on the existing socket file descriptor.  Then configure
    // the stream for async operation.

    CFStreamCreatePairWithSocket(NULL, fd, &readStream, &writeStream);
    MockServerAssert(readStream);
    MockServerAssert(writeStream);

    self.input = (NSInputStream*)readStream;
    self.output = (NSOutputStream*)writeStream;

    CFRelease(readStream);
    CFRelease(writeStream);

    [self.input setProperty:(id)kCFBooleanTrue forKey:(NSString *)kCFStreamPropertyShouldCloseNativeSocket];
    [self.output setProperty:(id)kCFBooleanTrue forKey:(NSString *)kCFStreamPropertyShouldCloseNativeSocket];

    self.input.delegate = self;
    self.output.delegate = self;

    [self.input scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.output scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

    [self.input open];
    [self.output open];
}

- (void)disconnect:(NSString*)reason
{
    if (self.input != nil)
    {
        self.input.delegate = nil;
        [self.input removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [self.input close];
        self.input = nil;
    }

    if (self.output != nil)
    {
        self.output.delegate = nil;
        [self.output removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [self.output close];
        self.output = nil;
    }

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

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
// An NSStream delegate callback that's called when events happen on our
// network stream.
{
    MockServerAssert((aStream == self.input) || (aStream == self.output));

    switch (eventCode)
    {
        case NSStreamEventOpenCompleted:
        {
            MockServerLog(@"opened %@ stream", [self nameForStream:aStream]);
            break;
        }

        case NSStreamEventHasBytesAvailable:
        {
            NSInteger       bytesRead;
            uint8_t         buffer[32768];

            // Pull some data off the network.

            bytesRead = [self.input read:buffer maxLength:sizeof(buffer)];
            if (bytesRead == -1)
            {
                [self disconnect:@"Network read error"];
            }

            else if (bytesRead == 0)
            {
                [self disconnect:@"No more data"];
            }
            else
            {
                NSData* data = [NSData dataWithBytesNoCopy:buffer length:bytesRead];
                [self processInput:data];
            }
            break;
        }

        case NSStreamEventHasSpaceAvailable:
        {
            MockServerAssert(aStream == self.output);     // should never happen for the input stream
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
            break;
        }

        case NSStreamEventErrorOccurred:
        {
            MockServerLog(@"got error for %@ stream", [self nameForStream:aStream]);
            [self disconnect:@"Stream open error"];
            break;
        }

        case NSStreamEventEndEncountered:
        {
            MockServerLog(@"got eof for %@ stream", [self nameForStream:aStream]);
            break;
        }

        default:
        {
            MockServerLog(@"unknown event for %@ stream", [self nameForStream:aStream]);
            MockServerAssert(NO);
            break;
        }
    }
}

- (void)processInput:(NSData*)data
{
    NSString* string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    MockServerLog(@"got data %@", string);

    NSString* output = @"<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">\n<html><head>\n<title>400 Bad Request</title>\n</head><body>\n<h1>Bad Request</h1>\n<p>Your browser sent a request that this server could not understand.<br />\n</p>\n<hr>\n<address>Apache/2.2.14 (Ubuntu) Server at downloads.elegantchaos.com Port 80</address>\n</body></html>";
    [self.outputData appendData:[output dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)acceptConnection:(int)fd
{
    int     junk;

    // If we already have a connection, reject this new one.  This is one of the
    // big simplifying assumptions in this code.  A real server should handle
    // multiple simultaneous connections.

    if (self.input)
    {
        junk = close(fd);
        MockServerAssert(junk == 0);
    } else {
        [self startReceive:fd];
    }
}

static void AcceptCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
// Called by CFSocket when someone connects to our listening socket.
// This implementation just bounces the request up to Objective-C.
{
    ECTestServer *  obj;

#pragma unused(type)
    MockServerAssert(type == kCFSocketAcceptCallBack);
#pragma unused(address)
    // MockServerAssert(address == NULL);
    MockServerAssert(data);

    obj = ( ECTestServer *) info;
    MockServerAssert(obj != nil);

    MockServerAssert(s == obj->_listeningSocket);
#pragma unused(s)

    [obj acceptConnection:*(int *)data];
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
    struct sockaddr_in  addr;
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
    // Use CFSocket to integrate the socket into our runloop.

    CFSocketContext context = { 0, (void *) self, NULL, NULL, NULL };

    MockServerAssert(self->_listeningSocket == NULL);
    self->_listeningSocket = CFSocketCreateWithNative(NULL, socket, kCFSocketAcceptCallBack, AcceptCallback, &context);

    BOOL result = (self->_listeningSocket != nil);

    if (result)
    {
        CFRunLoopSourceRef  rls;

        rls = CFSocketCreateRunLoopSource(NULL, self.listeningSocket, 0);
        MockServerAssert(rls);

        CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);

        CFRelease(rls);
    }
    else
    {
        MockServerLog(@"couldn't make CFSocket for socket %d", socket);
    }

    return result;
}

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
        [self disconnect:@"Cancelled"];
    }

    if (self.listeningSocket)
    {
        CFSocketInvalidate(self.listeningSocket);
        CFRelease(self->_listeningSocket);
        self->_listeningSocket = NULL;
    }

    NSLog(@"server stopped with reason %@", reason);
}


@end

@interface ServerExample : SenTestCase

@property (assign, atomic) BOOL exitRunLoop;

@end

@implementation ServerExample

@synthesize exitRunLoop = _exitRunLoop;

#pragma mark - Tests

// --------------------------------------------------------------------------
/// Some tests need the run loop to run for a while, for example
/// to perform an asynchronous network request.
/// This method runs until something external (such as a
/// delegate method) sets the exitRunLoop flag.
// --------------------------------------------------------------------------

- (void)runUntilTimeToExit
{
    self.exitRunLoop = NO;
    while (!self.exitRunLoop)
    {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
    }
}

- (void)timeToExitRunLoop
{
    self.exitRunLoop = YES;
}


- (void)testServer
{
    ECTestServer* server = [ECTestServer serverWithPort:10000 responses:@{ @"blah" : @"blah" }];
    STAssertNotNil(server, @"got server");
    [server startServer];

    NSURL* url = [NSURL URLWithString:@"http://127.0.0.1:10000/index.html"];

    __block NSString* string = nil;

    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:url] queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse* response, NSData* data, NSError* error)
    {
        if (error)
        {
            NSLog(@"got error %@", error);
        }
        else
        {
            string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }

        [self timeToExitRunLoop];
    }];

    [self runUntilTimeToExit];

    STAssertEqualObjects(string, @"blah", @"wrong response");
    [string release];

    server.responses = nil;
}

@end
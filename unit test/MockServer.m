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
@property (assign, nonatomic) dispatch_queue_t queue;


@property (nonatomic, assign, readonly ) BOOL               isStarted;
@property (nonatomic, assign, readonly ) BOOL               isReceiving;
@property (nonatomic, assign, readwrite) CFSocketRef        listeningSocket;
@property (nonatomic, strong, readwrite) NSInputStream *    networkStream;

@end

@implementation ECTestServer

@synthesize port = _port;
@synthesize responses = _responses;
@synthesize queue = _queue;

@synthesize networkStream   = _networkStream;
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
        self.queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    }

    return self;
}

- (void)dealloc
{
    dispatch_release(self.queue);

    [super dealloc];
}

- (BOOL)isReceiving
{
    return (self.networkStream != nil);
}

- (void)startReceive:(int)fd
{
    CFReadStreamRef     readStream;

    assert(fd >= 0);
    assert(self.networkStream == nil);      // can't already be receiving

    // Open a stream based on the existing socket file descriptor.  Then configure
    // the stream for async operation.

    CFStreamCreatePairWithSocket(NULL, fd, &readStream, NULL);
    assert(readStream != NULL);

    self.networkStream = ( NSInputStream *) readStream;

    CFRelease(readStream);

    [self.networkStream setProperty:(id)kCFBooleanTrue forKey:(NSString *)kCFStreamPropertyShouldCloseNativeSocket];

    self.networkStream.delegate = self;
    [self.networkStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

    [self.networkStream open];
}

- (void)stopReceiveWithStatus:(NSString *)statusString
{
    if (self.networkStream != nil) {
        self.networkStream.delegate = nil;
        [self.networkStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [self.networkStream close];
        self.networkStream = nil;
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
// An NSStream delegate callback that's called when events happen on our
// network stream.
{
    assert(aStream == self.networkStream);
#pragma unused(aStream)

    switch (eventCode) {
        case NSStreamEventOpenCompleted: {
        } break;
        case NSStreamEventHasBytesAvailable: {
            NSInteger       bytesRead;
            uint8_t         buffer[32768];

            // Pull some data off the network.

            bytesRead = [self.networkStream read:buffer maxLength:sizeof(buffer)];
            if (bytesRead == -1) {
                [self stopReceiveWithStatus:@"Network read error"];
            } else if (bytesRead == 0) {
                [self stopReceiveWithStatus:nil];
            } else {
                NSLog(@"read bytes %ld", bytesRead);
                // TODO: write response
            }
        } break;
        case NSStreamEventHasSpaceAvailable: {
            assert(NO);     // should never happen for the output stream
        } break;
        case NSStreamEventErrorOccurred: {
            [self stopReceiveWithStatus:@"Stream open error"];
        } break;
        case NSStreamEventEndEncountered: {
            // ignore
        } break;
        default: {
            assert(NO);
        } break;
    }
}

- (void)acceptConnection:(int)fd
{
    int     junk;

    // If we already have a connection, reject this new one.  This is one of the
    // big simplifying assumptions in this code.  A real server should handle
    // multiple simultaneous connections.

    if ( self.isReceiving ) {
        junk = close(fd);
        assert(junk == 0);
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
    assert(type == kCFSocketAcceptCallBack);
#pragma unused(address)
    // assert(address == NULL);
    assert(data != NULL);

    obj = ( ECTestServer *) info;
    assert(obj != nil);

    assert(s == obj->_listeningSocket);
#pragma unused(s)

    [obj acceptConnection:*(int *)data];
}

- (void)startServer
{
    BOOL                success;
    int                 err;
    int                 fd;
    int                 junk;
    struct sockaddr_in  addr;

    // Create a listening socket and use CFSocket to integrate it into our
    // runloop.  We bind to port 0, which causes the kernel to give us
    // any free port, then use getsockname to find out what port number we
    // actually got.

    fd = socket(AF_INET, SOCK_STREAM, 0);
    success = (fd != -1);

    if (success) {
        memset(&addr, 0, sizeof(addr));
        addr.sin_len    = sizeof(addr);
        addr.sin_family = AF_INET;
        addr.sin_port   = htons(self.port);
        addr.sin_addr.s_addr = INADDR_ANY;
        err = bind(fd, (const struct sockaddr *) &addr, sizeof(addr));
        success = (err == 0);
    }
    if (success) {
        err = listen(fd, 5);
        success = (err == 0);
    }
    if (success) {
        socklen_t   addrLen;

        addrLen = sizeof(addr);
        err = getsockname(fd, (struct sockaddr *) &addr, &addrLen);
        success = (err == 0);

        if (success) {
            assert(addrLen == sizeof(addr));
            self.port = ntohs(addr.sin_port);
        }
    }
    if (success) {
        CFSocketContext context = { 0, (void *) self, NULL, NULL, NULL };

        assert(self->_listeningSocket == NULL);
        self->_listeningSocket = CFSocketCreateWithNative(
                                                          NULL,
                                                          fd,
                                                          kCFSocketAcceptCallBack,
                                                          AcceptCallback,
                                                          &context
                                                          );
        success = (self->_listeningSocket != NULL);

        if (success) {
            CFRunLoopSourceRef  rls;

            fd = -1;        // listeningSocket is now responsible for closing fd

            rls = CFSocketCreateRunLoopSource(NULL, self.listeningSocket, 0);
            assert(rls != NULL);

            CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);

            CFRelease(rls);
        }
    }


    // Clean up after failure.

    if ( success ) {
        assert(self.port != 0);
        NSLog(@"server started on port %ld", self.port);
    } else {
        [self stopServer:@"Start failed"];
        if (fd != -1) {
            junk = close(fd);
            assert(junk == 0);
        }
    }
}

- (void)stopServer:(NSString *)reason
{
    if (self.isReceiving) {
        [self stopReceiveWithStatus:@"Cancelled"];
    }
    if (self.listeningSocket != NULL) {
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

    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:url] queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse* response, NSData* data, NSError* error)
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
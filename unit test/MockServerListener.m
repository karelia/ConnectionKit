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

#import "MockServerListener.h"

#import "MockServer.h"
#import "MockServerConnection.h"
#import "MockServerResponder.h"

@interface MockServerListener()

@property (copy, nonatomic) ConnectionBlock connectionBlock;
@property (assign, nonatomic) CFSocketRef listener;
@property (assign, nonatomic) NSUInteger port;

@end

@implementation MockServerListener

@synthesize listener = _listener;
@synthesize port = _port;

#pragma mark - Object Lifecycle

+ (MockServerListener*)listenerWithPort:(NSUInteger)port connectionBlock:(ConnectionBlock)block
{
    MockServerListener* listener = [[MockServerListener alloc] initWithPort:port connectionBlock:block];

    return [listener autorelease];
}

- (id)initWithPort:(NSUInteger)port connectionBlock:(ConnectionBlock)block
{
    if ((self = [super init]) != nil)
    {
        self.connectionBlock = block;
        self.port = port;
        MockServerLog(@"made listener at port %ld", (long) port);
    }

    return self;
}

- (void)dealloc
{

    [super dealloc];
}

#pragma mark - Public API


#pragma mark - Start / Stop

- (BOOL)start
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
        NSLog(@"listener started on port %ld", self.port);
    }
    else
    {
        [self stop:@"Start failed"];
        if (socket != -1)
        {
            int err = close(socket);
            if (!err)
            {
                MockServerLog(@"couldn't close socket %d", socket);
            }
        }
    }

    return success;
}

- (void)stop:(NSString*)reason
{
    if (self.listener)
    {
        CFSocketInvalidate(self.listener);
        CFRelease(self.listener);
        self.listener = NULL;
    }

    MockServerLog(@"listener stopped because: %@", reason);
}


#pragma mark - Sockets

- (void)acceptConnectionOnSocket:(int)socket
{
    MockServerAssert(socket >= 0);

    BOOL ok = self.connectionBlock(socket);
    if (!ok)
    {
        MockServerLog(@"connection failed, closing socket");
        int error = close(socket);
        MockServerAssert(error == 0);
    }
}

static void callbackAcceptConnection(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    MockServerListener* obj = (MockServerListener*)info;
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

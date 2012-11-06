// --------------------------------------------------------------------------
//! @author Sam Deane
//
//  Copyright 2012 Sam Deane, Elegant Chaos. All rights reserved.
//  This source code is distributed under the terms of Elegant Chaos's 
//  liberal license: http://www.elegantchaos.com/license/liberal
// --------------------------------------------------------------------------

#import "MockServer.h"
#import <SenTestingKit/SenTestingKit.h>

@interface MockServerTests : SenTestCase

@end

@implementation MockServerTests

static NSString *const HTTPHeader = @"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=iso-8859-1\r\n\r\n";
static NSString*const HTTPContent = @"<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\"><html><head><title>example</title></head><body>example result</body></html>\n";

- (MockServer*)setupServer
{
    id closeCommand = [MockServer closeResponse];

    MockServer* server = [MockServer serverWithPort:0 responses:@{
                          @"^GET .* HTTP.*" : @[ HTTPHeader, HTTPContent, @(0.1), closeCommand],
                          @"^HEAD .* HTTP.*" : @[ HTTPHeader, closeCommand],
                          }];

    STAssertNotNil(server, @"got server");
    [server start];
    BOOL started = server.running;
    STAssertTrue(started, @"server started ok");
    return started ? server : nil;
}

- (NSString*)stringForScheme:(NSString*)scheme path:(NSString*)path method:(NSString*)method server:(MockServer*)server
{
    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://127.0.0.1:%ld%@", scheme, (long)server.port, path]];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;

    __block NSString* string = nil;

    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse* response, NSData* data, NSError* error)
     {
         if (error)
         {
             NSLog(@"got error %@", error);
         }
         else
         {
             string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
         }

         [server stop];
     }];

    [server runUntilStopped];

    return string;
}

#pragma mark - Tests

- (void)testHTTPGet
{
    MockServer* server = [self setupServer];
    if (server)
    {
        NSString* string = [self stringForScheme:@"http" path:@"/index.html" method:@"GET" server:server];

        STAssertEqualObjects(string, HTTPContent, @"wrong response");
        [string release];
    }
}

- (void)testHTTPHead
{
    MockServer* server = [self setupServer];
    if (server)
    {
        NSString* string = [self stringForScheme:@"http" path:@"/index.html" method:@"HEAD" server:server];

        STAssertEqualObjects(string, @"", @"wrong response");
        [string release];
    }
}

@end
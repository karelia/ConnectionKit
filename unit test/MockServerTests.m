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

#pragma mark - Tests

- (void)testServer
{
    NSString* expectedRequest = @"GET /index.html HTTP/1.1";
    NSString* expectedResponse = @"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=iso-8859-1\r\n\r\n";
    NSString* expectedContent = @"<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\"><html><head><title>example</title></head><body>example result</body></html>\n";

    id closeCommand = [MockServer closeResponse];

    MockServer* server = [MockServer serverWithPort:0 responses:@{ expectedRequest : @[ expectedResponse, expectedContent, @(0.1), closeCommand] }];
    
    STAssertNotNil(server, @"got server");
    [server start];
    BOOL started = server.running;
    STAssertTrue(started, @"server started ok");

    if (started)
    {
        NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/index.html", (long)server.port]];

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

             [server stop];
         }];

        [server runUntilStopped];
        
        STAssertEqualObjects(string, expectedContent, @"wrong response");
        [string release];
    }
}

@end
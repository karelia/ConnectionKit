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

@property (assign, atomic) BOOL exitRunLoop;

@end

@implementation MockServerTests

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
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
        }
    }
}

- (void)timeToExitRunLoop
{
    self.exitRunLoop = YES;
}


- (void)testServer
{
    MockServer* server = [MockServer serverWithPort:0 responses:@{ @"blah" : @"blah" }];
    STAssertNotNil(server, @"got server");
    [server startServer];
    BOOL started = server.listeningSocket != nil;
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

             [self timeToExitRunLoop];
         }];

        [self runUntilTimeToExit];
        
        STAssertEqualObjects(string, @"<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\"><html><head><title>example</title></head><body>example result</body></html>\n", @"wrong response");
        [string release];
    }

    server.responses = nil;
}

@end
//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "MockServer.h"
#import <SenTestingKit/SenTestingKit.h>

@interface MockServerTests : SenTestCase

@end

@implementation MockServerTests

static NSString *const HTTPHeader = @"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=iso-8859-1\r\n\r\n";
static NSString*const HTTPContent = @"<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\"><html><head><title>example</title></head><body>example result</body></html>\n";

- (NSArray*)httpResponses
{
    NSArray* responses = @[
    @[ @"^GET .* HTTP.*", HTTPHeader, HTTPContent, @(0.1), CloseCommand],
    @[@"^HEAD .* HTTP.*", HTTPHeader, CloseCommand],
    ];

    return responses;
}

- (NSArray*)ftpResponses
{
    NSArray* responses = @[
    @[InitialResponseKey, @"220 $address FTP server ($server) ready.\r\n" ],
    @[@"USER user", @"331 User user accepted, provide password.\r\n"],
    @[@"PASS pass", @"230 User user logged in.\r\n"],
    @[@"SYST", @"215 UNIX Type: L8 Version: $server\r\n" ],
    @[@"PWD", @"257 \"/\" is the current directory.\r\n" ],
    @[@"TYPE I", @"200 Type set to I.\r\n" ],
    @[@"CWD /", @"250 CWD command successful.\r\n" ],
    @[@"PASV", @"227 Entering Passive Mode ($pasv)\r\n"],
    @[@"SIZE test.txt", @"213 $size\r\n"],
    @[@"RETR /test.txt", @"150 Opening BINARY mode data connection for '/test.txt' ($size bytes).\r\n"],
    @[@"(\\w+).*", @"500 '$1': command not understood.", CloseCommand],
    ];

    return responses;
}

- (MockServer*)setupServerWithResponses:(NSArray*)responses
{
    MockServer* server = [MockServer serverWithPort:0 responses:responses];

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
    return [self stringForRequest:request server:server];
}

- (NSString*)stringForScheme:(NSString*)scheme path:(NSString*)path server:(MockServer*)server
{
    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://127.0.0.1:%ld%@", scheme, (long)server.port, path]];
    NSURLRequest* request = [NSURLRequest requestWithURL:url];
    return [self stringForRequest:request server:server];
}

- (NSString*)stringForRequest:(NSURLRequest*)request server:(MockServer*)server
{
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

    return [string autorelease];
}

#pragma mark - Tests

- (void)testHTTPGet
{
    MockServer* server = [self setupServerWithResponses:[self httpResponses]];
    if (server)
    {
        NSString* string = [self stringForScheme:@"http" path:@"/index.html" method:@"GET" server:server];
        STAssertEqualObjects(string, HTTPContent, @"wrong response");
    }
}

- (void)testHTTPHead
{
    MockServer* server = [self setupServerWithResponses:[self httpResponses]];
    if (server)
    {
        NSString* string = [self stringForScheme:@"http" path:@"/index.html" method:@"HEAD" server:server];
        STAssertEqualObjects(string, @"", @"wrong response");
    }
}

- (void)testFTP
{
    MockServer* server = [self setupServerWithResponses:[self ftpResponses]];
    if (server)
    {
        NSString* testData = @"This is some test data";
        server.data = [testData dataUsingEncoding:NSUTF8StringEncoding];
        NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"ftp://user:pass@127.0.0.1:%ld/test.txt", (long)server.port]];
        NSURLRequest* request = [NSURLRequest requestWithURL:url];

        NSString* string = [self stringForRequest:request server:server];
        STAssertEqualObjects(string, testData, @"wrong response");
    }
}

@end
//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "MockServer.h"
#import "CK2FileTransferSession.h"
#import <SenTestingKit/SenTestingKit.h>

@interface CK2FileTransferSessionTests : SenTestCase<CK2FileTransferSessionDelegate>

@end

@implementation CK2FileTransferSessionTests

static NSString *const ExampleListing = @"total 1\r\n-rw-------   1 user  staff     3 Mar  6  2012 file1.txt\r\n-rw-------   1 user  staff     3 Mar  6  2012 file2.txt\r\n\r\n";

- (NSArray*)ftpResponses
{
    NSArray* responses = @[
    @[InitialResponseKey, @"220 $address FTP server ($server) ready.\r\n" ],
    @[@"USER (\\w+)", @"331 User $1 accepted, provide password.\r\n"],
    @[@"PASS (\\w+)", @"230 User user logged in.\r\n"],
    @[@"SYST", @"215 UNIX Type: L8 Version: $server\r\n" ],
    @[@"PWD", @"257 \"/\" is the current directory.\r\n" ],
    @[@"TYPE (\\w+)", @"200 Type set to $1.\r\n" ],
    @[@"CWD .*", @"250 CWD command successful.\r\n" ],
    @[@"PASV", @"227 Entering Passive Mode ($pasv)\r\n"],
    @[@"SIZE test.txt", @"213 $size\r\n"],
    @[@"RETR /test.txt", @"150 Opening BINARY mode data connection for '/test.txt' ($size bytes).\r\n"],
    @[@"LIST", @(0.1), @"150 Opening ASCII mode data connection for '/bin/ls'.\r\n", @(0.1), @"226 Transfer complete.\r\n"],
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

#pragma mark - Delegate

- (void)fileTransferSession:(CK2FileTransferSession *)session didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSURLCredential* credential = [NSURLCredential credentialWithUser:@"user" password:@"pass" persistence:NSURLCredentialPersistenceNone];
    [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
}

- (void)fileTransferSession:(CK2FileTransferSession *)session appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript
{
    NSLog(@"> %@", info);
}

#pragma mark - Tests

- (NSURL*)URLForPath:(NSString*)path server:(MockServer*)server
{
    NSURL* result = [NSURL URLWithString:[NSString stringWithFormat:@"ftp://127.0.0.1:%ld/%@", server.port, path]];
    return result;
}

- (void)testContentsOfDirectoryAtURL
{
    MockServer* server = [self setupServerWithResponses:[self ftpResponses]];
    if (server)
    {
        server.data = [ExampleListing dataUsingEncoding:NSUTF8StringEncoding];

        CK2FileTransferSession* session = [[CK2FileTransferSession alloc] init];
        session.delegate = self;
        NSURL* url = [self URLForPath:@"/directory/" server:server];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [session contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

            if (error)
            {
                STFail(@"got error %@", error);
            }
            else
            {
                NSUInteger count = [contents count];
                STAssertTrue(count == 2, @"should have two results");
                if (count == 2)
                {
                    NSURL* file1 = [self URLForPath:@"/directory/file1.txt" server:server];
                    STAssertTrue([contents[0] isEqual:file1], @"got file 1");
                    NSURL* file2 = [self URLForPath:@"/directory/file2.txt" server:server];
                    STAssertTrue([contents[1] isEqual:file2], @"got file 2");
                }
            }
            
            [server stop];
        }];

        [server runUntilStopped];
        [session release];
    }
}

- (void)testEnumerateContentsOfURL
{
    MockServer* server = [self setupServerWithResponses:[self ftpResponses]];
    if (server)
    {
        server.data = [ExampleListing dataUsingEncoding:NSUTF8StringEncoding];

        CK2FileTransferSession* session = [[CK2FileTransferSession alloc] init];
        session.delegate = self;
        NSURL* url = [self URLForPath:@"/directory/" server:server];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        NSMutableArray* expectedURLS = [NSMutableArray arrayWithArray:@[
            url,
            [self URLForPath:@"/directory/file1.txt" server:server],
            [self URLForPath:@"/directory/file2.txt" server:server]
        ]];

        [session enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *item) {
            NSLog(@"got item %@", item);
            STAssertTrue([expectedURLS containsObject:item], @"got expected item");
            [expectedURLS removeObject:item];
        } completionHandler:^(NSError *error) {
            if (error)
            {
                STFail(@"got error %@", error);
            }
            [server stop];
        }];

        [server runUntilStopped];
        [session release];
    }
}

@end
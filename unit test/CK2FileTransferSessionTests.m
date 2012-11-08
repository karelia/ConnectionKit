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

- (NSArray*)ftpResponses
{
    NSArray* responses = @[
    @[InitialResponseKey, @"220 $address FTP server ($server) ready.\r\n" ],
    @[@"USER user", @"331 User user accepted, provide password.\r\n"],
    @[@"PASS pass", @"230 User user logged in.\r\n"],
    @[@"SYST", @"215 UNIX Type: L8 Version: $server\r\n" ],
    @[@"PWD", @"257 \"/\" is the current directory.\r\n" ],
    @[@"TYPE (\\w+)", @"200 Type set to $1.\r\n" ],
    @[@"CWD directory", @"250 CWD command successful.\r\n" ],
    @[@"PASV", @"227 Entering Passive Mode ($pasv)\r\n"],
    @[@"SIZE test.txt", @"213 $size\r\n"],
    @[@"RETR /test.txt", @"150 Opening BINARY mode data connection for '/test.txt' ($size bytes).\r\n"],
    @[@"LIST", @"150: Opening ASCII mode data connection for '/bin/ls'.\r\n"],
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

- (void)testFTP
{
    MockServer* server = [self setupServerWithResponses:[self ftpResponses]];
    if (server)
    {
        CK2FileTransferSession* session = [[CK2FileTransferSession alloc] init];
        session.delegate = self;
        NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"ftp://127.0.0.1:%ld/directory", (long) server.port]];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [session contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

            [server stop];
        }];

        [server runUntilStopped];
        [session release];
    }
}

@end
//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "MockServer.h"
#import "MockServerFTPResponses.h"

#import "CK2FileTransferSession.h"
#import <SenTestingKit/SenTestingKit.h>

@interface CK2FileTransferSessionTests : SenTestCase<CK2FileTransferSessionDelegate>

@property (strong, nonatomic) MockServer* server;
@property (strong, nonatomic) CK2FileTransferSession* session;

@end

@implementation CK2FileTransferSessionTests

static NSString *const ExampleListing = @"total 1\r\n-rw-------   1 user  staff     3 Mar  6  2012 file1.txt\r\n-rw-------   1 user  staff     3 Mar  6  2012 file2.txt\r\n\r\n";

+ (NSArray*)ftpInitialResponse
{
    return @[InitialResponseKey, @"220 $address FTP server ($server) ready.\r\n" ];
}

- (BOOL)setupSessionWithResponses:(NSArray*)responses
{
    self.server = [MockServer serverWithPort:0 responses:responses];
    STAssertNotNil(self.server, @"got server");

    if (self.server)
    {
        [self.server start];
        BOOL started = self.server.running;
        STAssertTrue(started, @"server started ok");

        self.server.data = [ExampleListing dataUsingEncoding:NSUTF8StringEncoding];
        self.session = [[CK2FileTransferSession alloc] init];
        self.session.delegate = self;
    }

    return self.session != nil;
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

- (void)tearDown
{
    self.session = nil;
    self.server = nil;
}
- (NSURL*)URLForPath:(NSString*)path
{
    NSURL* result = [NSURL URLWithString:[NSString stringWithFormat:@"ftp://127.0.0.1:%ld/%@", self.server.port, path]];
    return result;
}

- (void)testContentsOfDirectoryAtURL
{
    if ([self setupSessionWithResponses:[MockServerFTPResponses standardResponses]])
    {
        NSURL* url = [self URLForPath:@"/directory/"];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.session contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

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
                    NSURL* file1 = [self URLForPath:@"/directory/file1.txt"];
                    STAssertTrue([contents[0] isEqual:file1], @"got file 1");
                    NSURL* file2 = [self URLForPath:@"/directory/file2.txt"];
                    STAssertTrue([contents[1] isEqual:file2], @"got file 2");
                }
            }
            
            [self.server stop];
        }];
        
        [self.server runUntilStopped];
    }
}

- (void)testContentsOfDirectoryAtURLBadLogin
{
    if ([self setupSessionWithResponses:[MockServerFTPResponses badLoginResponses]])
    {
        NSURL* url = [self URLForPath:@"/directory/"];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.session contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

            STAssertNotNil(error, @"should get error");
            STAssertTrue([error code] == NSURLErrorUserAuthenticationRequired, @"should get authentication error");
            STAssertTrue([contents count] == 0, @"shouldn't get content");

            [self.server stop];
        }];
        
        [self.server runUntilStopped];
    }
}

- (void)testEnumerateContentsOfURL
{
    if ([self setupSessionWithResponses:[MockServerFTPResponses standardResponses]])
    {
        NSURL* url = [self URLForPath:@"/directory/"];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        NSMutableArray* expectedURLS = [NSMutableArray arrayWithArray:@[
                                        url,
                                        [self URLForPath:@"/directory/file1.txt"],
                                        [self URLForPath:@"/directory/file2.txt"]
                                        ]];

        [self.session enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *item) {
            NSLog(@"got item %@", item);
            STAssertTrue([expectedURLS containsObject:item], @"got expected item");
            [expectedURLS removeObject:item];
        } completionHandler:^(NSError *error) {
            if (error)
            {
                STFail(@"got error %@", error);
            }
            [self.server stop];
        }];
        
        [self.server runUntilStopped];
    }
}

- (void)testEnumerateContentsOfURLBadLogin
{
    if ([self setupSessionWithResponses:[MockServerFTPResponses badLoginResponses]])
    {
        NSURL* url = [self URLForPath:@"/directory/"];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.session enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *item) {
            STFail(@"shouldn't get any items");
        } completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            STAssertTrue([error code] == NSURLErrorUserAuthenticationRequired, @"should get authentication error");

            [self.server stop];
        }];

        [self.server runUntilStopped];
    }
}

- (void)testCreateDirectoryAtURL
{
    //- (void)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates completionHandler:(void (^)(NSError *error))handler;
}

- (void)testCreateFileAtURL
{
    //
    //// 0 bytesWritten indicates writing has ended. This might be because of a failure; if so, error will be filled in
    //- (void)createFileAtURL:(NSURL *)url contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
}

- (void)testCreateFileAtURL2
{
    //
    //- (void)createFileAtURL:(NSURL *)destinationURL withContentsOfURL:(NSURL *)sourceURL withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
}

- (void)testRemoveFileAtURL
{
    //
    //- (void)removeFileAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
}

- (void)testSetResourceValues
{
    //// Only NSFilePosixPermissions is recognised at present. Note that some servers don't support this so will return an error (code 500)
    //// All other attributes are ignored
    //- (void)setResourceValues:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
    
}

@end
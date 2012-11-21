//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "KSMockServer.h"
#import "KSMockServerRegExResponder.h"
#import "KSMockServerFTPResponses.h"

#import "CK2FileManager.h"
#import <SenTestingKit/SenTestingKit.h>
#import <DAVKit/DAVKit.h>

#define TEST_WITH_REAL_SERVER 0

@interface CK2FileManagerWebDAVTests : SenTestCase<CK2FileManagerDelegate>

@property (strong, nonatomic) KSMockServer* server;
@property (strong, nonatomic) CK2FileManager* session;
@property (assign, nonatomic) BOOL running;
@property (strong, nonatomic) NSString* user;
@property (strong, nonatomic) NSString* password;

@end

@implementation CK2FileManagerWebDAVTests

- (BOOL)setupSession
{
    self.session = [[CK2FileManager alloc] init];
    self.session.delegate = self;

    return self.session != nil;
}

- (BOOL)setupSessionWithRealServer
{
    self.user = @"demo";
    self.password = @"demo";
    return [self setupSession];
}

- (BOOL)setupSessionWithResponses:(NSArray*)responses
{
#if TEST_WITH_REAL_SERVER
    return [self setupSessionWithRealServer];
#else
    self.user = @"user";
    self.password = @"pass";
    KSMockServerRegExResponder* responder = [KSMockServerRegExResponder responderWithResponses:responses];
    self.server = [KSMockServer serverWithPort:0 responder:responder];
    STAssertNotNil(self.server, @"got server");

    if (self.server)
    {
        [self.server start];
        BOOL started = self.server.running;
        STAssertTrue(started, @"server started ok");

        [self setupSession];
    }
    return self.session != nil;
#endif
}

#pragma mark - Delegate
- (void)fileManager:(CK2FileManager *)manager didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge.previousFailureCount > 0)
    {
        NSLog(@"cancelling authentication");
        [challenge.sender cancelAuthenticationChallenge:challenge];
    }
    else
    {
        NSLog(@"authenticating as %@ %@", self.user, self.password);
        NSURLCredential* credential = [NSURLCredential credentialWithUser:self.user password:self.password persistence:NSURLCredentialPersistenceNone];
        [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
    }
}

- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript
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
#if TEST_WITH_REAL_SERVER
    NSURL* url = [[NSURL URLWithString:@"https://www.crushftp.com/demo/"] URLByAppendingPathComponent:path];
#else
    NSURL* result = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/%@", self.server.port, path]];
#endif

    return result;
}


- (void)stop
{
#if TEST_WITH_REAL_SERVER
    self.running = NO;
#else
    [self.server stop];
}

- (void)runUntilStopped
{
#if TEST_WITH_REAL_SERVER
    self.running = YES;
    while (self.running)
    {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
        }
    }
#else
    [self.server runUntilStopped];
#endif
}

- (NSArray*)webDAVResponses
{
    NSURL* url = [[NSBundle bundleForClass:[self class]] URLForResource:@"webdav" withExtension:@"json"];
    NSError* error = nil;
    NSData* data = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:&error];
    NSArray* result = @[];
    if (data)
    {
        result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    }

    if (!result)
    {
        NSLog(@"error parsing responses file: %@", error);
    }

    return result;
}


- (void)testContentsOfDirectoryAtURLRealServer
{
    NSArray* responses = [self webDAVResponses];
    if ([self setupSessionWithResponses:responses])
    {
        NSURL* url = [self URLForPath:@""];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;

        // do the test with the wrong password
        self.password = @"wrong";
        [self.session contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

            STAssertNotNil(error, @"should have error");

            [self stop];
        }];
        [self runUntilStopped];

        // do test with the right password
        self.password = @"demo";
        [self.session contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

            if (error)
            {
                STFail(@"got error %@", error);
            }
            else
            {
                NSUInteger count = [contents count];
                STAssertTrue(count > 0, @"should have results");
                STAssertTrue(![contents containsObject:url], @"contents shouldn't include url of directory itself, they were: %@", contents);
            }
            
            [self stop];
        }];
        [self runUntilStopped];
    }
}

- (void)testCreateAndRemoveDirectoryOnRealServerAtURL:(NSURL*)url
{
    NSArray* responses = [self webDAVResponses];
    if ([self setupSessionWithResponses:responses])
    {
        // delete directory in case it's left from last time
        [self.session removeFileAtURL:url completionHandler:^(NSError *error) {
            [self stop];
        }];
        [self runUntilStopped];

        // try to make it
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self stop];
        }];
        [self runUntilStopped];

        // try to make it again - should fail
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should have error");
            STAssertTrue([[error domain] isEqual:DAVClientErrorDomain], @"");
            STAssertEquals([error code], (NSInteger) 405, @"should have error 405, got %ld", (long) [error code]);

            [self stop];
        }];
        [self runUntilStopped];

        // try to delete directory - should work this time
        [self.session removeFileAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self stop];
        }];
        [self runUntilStopped];
    }
}

- (void)testCreateAndRemoveDirectoryAtURLRealServer
{
    NSURL* url = [self URLForPath:@"ck-test-directory"];
    [self testCreateAndRemoveDirectoryOnRealServerAtURL:url];
}

- (void)testCreateAndRemoveDirectoryAndSubdirectoryAtURLRealServer
{
    NSURL* url = [self URLForPath:@"ck-test-directory/ck-test-subdirectory"];
    [self testCreateAndRemoveDirectoryOnRealServerAtURL:url];
}

- (void)testCreateAndRemoveFileAtURLRealServer
{
    NSArray* responses = [self webDAVResponses];
    if ([self setupSessionWithResponses:responses])
    {
        NSURL* url = [self URLForPath:@"ck-test-file.txt"];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];

        // try to delete in case it's left around from last time - ignore error
        [self.session removeFileAtURL:url completionHandler:^(NSError *error) {
            [self stop];
        }];
        [self runUntilStopped];

        // try to upload
        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES progressBlock:^(NSUInteger bytesWritten, NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            if (bytesWritten == 0)
            {
                [self stop];
            }
        }];
        [self runUntilStopped];

        // try to download
        NSURL* downloadURL = [NSURL URLWithString:@"https://demo:demo@www.crushftp.com/demo/ck-test-file.txt"];
        NSURLRequest* request = [NSURLRequest requestWithURL:downloadURL];
        [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse* response, NSData* data, NSError* error) {
            STAssertNil(error, @"got unexpected error %@", error);

            NSString* received = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            STAssertTrue([received isEqualToString:@"Some test text"], @"string should have matched, was %@", received);

            [self stop];
        }];
        [self runUntilStopped];

        // try to delete - this time we do want to check the error
        [self.session removeFileAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self stop];
        }];
        [self runUntilStopped];

    }
}

#endif

@end
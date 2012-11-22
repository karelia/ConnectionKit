//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerBaseTests.h"
#import "KSMockServer.h"
#import "KSMockServerRegExResponder.h"

#import "CK2FileManager.h"
#import <SenTestingKit/SenTestingKit.h>
#import <DAVKit/DAVKit.h>

@interface CK2FileManagerWebDAVTests : CK2FileManagerBaseTests

@end

@implementation CK2FileManagerWebDAVTests

- (BOOL)setup
{
    BOOL result = [self setupSessionWithRealURL:[NSURL URLWithString:@"https://www.crushftp.com/demo/"] fakeResponses:@"webdav"];
    STAssertTrue(result, @"failed to setup");

    return result;
}

#pragma mark - Tests

- (void)testContentsOfDirectoryAtURL
{
    if ([self setup])
    {
        NSURL* url = [self URLForPath:@""];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;

        // do the test with the wrong password
        self.password = @"wrong";
        [self.session contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

            STAssertNotNil(error, @"should have error");
            STAssertTrue([error.domain isEqualToString:DAVClientErrorDomain], @"unexpected domain %@", error.domain);
            STAssertTrue(error.code == 501, @"unexpected code %ld", (long) error.code);
            [self pause];
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

- (void)testCreateAndRemoveDirectoryAtURL:(NSURL*)url
{
    // delete directory in case it's left from last time
    [self.session removeFileAtURL:url completionHandler:^(NSError *error) {
        [self pause];
    }];
    [self runUntilStopped];

    // try to make it
    [self.session createDirectoryAtURL:url withIntermediateDirectories:YES completionHandler:^(NSError *error) {
        STAssertNil(error, @"got unexpected error %@", error);

        [self pause];
    }];
    [self runUntilStopped];

    // switch the responder so that the next delete fails (has no effect if we're using the real server)
    [self useResponseSet:@"make fails"];

    // try to make it again - should fail
    [self.session createDirectoryAtURL:url withIntermediateDirectories:YES completionHandler:^(NSError *error) {
        STAssertNotNil(error, @"should have error");
        STAssertTrue([[error domain] isEqual:DAVClientErrorDomain], @"");
        STAssertEquals([error code], (NSInteger) 405, @"should have error 405, got %ld", (long) [error code]);

        [self pause];
    }];
    [self runUntilStopped];

    // try to delete directory - should work this time
    [self.session removeFileAtURL:url completionHandler:^(NSError *error) {
        STAssertNil(error, @"got unexpected error %@", error);
        [self stop];
    }];
    [self runUntilStopped];
}

- (void)testCreateAndRemoveDirectoryAtURL
{
    if ([self setup])
    {
        NSURL* url = [self URLForPath:@"ck-test-directory"];
        [self testCreateAndRemoveDirectoryAtURL:url];
    }
}

//- (void)testCreateAndRemoveDirectoryAndSubdirectoryAtURL
//{
//    if ([self setup])
//    {
//        NSURL* url = [self URLForPath:@"ck-test-directory/ck-test-subdirectory"];
//        [self testCreateAndRemoveDirectoryAtURL:url];
//    }
//}

- (void)testCreateAndRemoveFileAtURL
{
    if ([self setup])
    {
        NSURL* url = [self URLForPath:@"ck-test-file.txt"];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];

        // try to delete in case it's left around from last time - ignore error
        [self.session removeFileAtURL:url completionHandler:^(NSError *error) {
            [self pause];
        }];
        [self runUntilStopped];

        // try to upload
        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES progressBlock:^(NSUInteger bytesWritten, NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            if (bytesWritten == 0)
            {
                [self pause];
            }
        }];
        [self runUntilStopped];

#if TEST_WITH_REAL_SERVER
        // try to download
        NSURL* downloadURL = [NSURL URLWithString:@"https://demo:demo@www.crushftp.com/demo/ck-test-file.txt"];
        NSURLRequest* request = [NSURLRequest requestWithURL:downloadURL];
        [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse* response, NSData* data, NSError* error) {
            STAssertNil(error, @"got unexpected error %@", error);

            NSString* received = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            STAssertTrue([received isEqualToString:@"Some test text"], @"string should have matched, was %@", received);

            [self pause];
        }];
        [self runUntilStopped];
#endif

        // try to delete - this time we do want to check the error
        [self.session removeFileAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self stop];
        }];
        [self runUntilStopped];

    }
}

@end
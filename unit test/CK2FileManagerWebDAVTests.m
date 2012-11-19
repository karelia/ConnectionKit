//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "KSMockServer.h"
#import "KSMockServerRegExResponder.h"
#import "KSMockServerFTPResponses.h"

#import "CK2FileManager.h"
#import <SenTestingKit/SenTestingKit.h>
#import <curl/curl.h>

@interface CK2FileManagerWebDAVTests : SenTestCase<CK2FileManagerDelegate>

@property (strong, nonatomic) KSMockServer* server;
@property (strong, nonatomic) CK2FileManager* session;

@end

@implementation CK2FileManagerWebDAVTests

- (BOOL)setupSession
{
    self.session = [[CK2FileManager alloc] init];
    self.session.delegate = self;

    return self.session != nil;
}

- (BOOL)setupSessionWithResponses:(NSArray*)responses
{
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
}

#pragma mark - Delegate
- (void)fileManager:(CK2FileManager *)manager didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSURLCredential* credential = [NSURLCredential credentialWithUser:@"user" password:@"pass" persistence:NSURLCredentialPersistenceNone];
    [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
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
    NSURL* result = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/%@", self.server.port, path]];
    return result;
}

#if 0
- (void)testContentsOfDirectoryAtURL
{
    if ([self setupSessionWithResponses:[KSMockServerFTPResponses standardResponses]])
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
    if ([self setupSessionWithResponses:[KSMockServerFTPResponses badLoginResponses]])
    {
        NSURL* url = [self URLForPath:@"/directory/"];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.session contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

            STAssertNotNil(error, @"should get error");
            STAssertTrue([error code] == NSURLErrorUserAuthenticationRequired, @"should get authentication error, got %@ instead", error);
            STAssertTrue([contents count] == 0, @"shouldn't get content");

            [self.server stop];
        }];
        
        [self.server runUntilStopped];
    }
}

- (void)testEnumerateContentsOfURL
{
    if ([self setupSessionWithResponses:[KSMockServerFTPResponses standardResponses]])
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
    if ([self setupSessionWithResponses:[KSMockServerFTPResponses badLoginResponses]])
    {
        NSURL* url = [self URLForPath:@"/directory/"];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.session enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *item) {
            STFail(@"shouldn't get any items");
        } completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            STAssertTrue([error code] == NSURLErrorUserAuthenticationRequired, @"should get authentication error, got %@ instead", error);

            [self.server stop];
        }];

        [self.server runUntilStopped];
    }
}

- (void)testCreateDirectoryAtURL
{
    if ([self setupSessionWithResponses:[KSMockServerFTPResponses standardResponses]])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/newdirectory"];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self.server stop];
        }];
    }

    [self.server runUntilStopped];
}

- (void)testCreateDirectoryAtURLAlreadyExists
{
    // mostly we use the standard responses, but we use an alternative "fileExists" response to the MKD command, to force the operation to fail
    NSArray* responses = @[[KSMockServerFTPResponses mkdFileExistsResponse]];
    responses = [responses arrayByAddingObjectsFromArray:[KSMockServerFTPResponses standardResponses]];

    if ([self setupSessionWithResponses:responses])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/newdirectory"];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            long ftpCode = [[[error userInfo] objectForKey:[NSNumber numberWithInt:CURLINFO_RESPONSE_CODE]] longValue];
            STAssertTrue(ftpCode == 550, @"should get 550 from server");

            [self.server stop];
        }];
    }

    [self.server runUntilStopped];
}

- (void)testCreateDirectoryAtURLBadLogin
{
    if ([self setupSessionWithResponses:[KSMockServerFTPResponses badLoginResponses]])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/newdirectory"];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            STAssertTrue([error code] == NSURLErrorUserAuthenticationRequired, @"should get authentication error, got %@ instead", error);

            [self.server stop];
        }];

        [self.server runUntilStopped];
    }
}

- (void)testCreateFileAtURL
{
    if ([self setupSessionWithResponses:[KSMockServerFTPResponses standardResponses]])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];
        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES progressBlock:^(NSUInteger bytesWritten, NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            if (bytesWritten == 0)
            {
                [self.server stop];
            }
        }];

        [self.server runUntilStopped];
    }
}

- (void)testCreateFileAtURL2
{
    if ([self setupSessionWithResponses:[KSMockServerFTPResponses standardResponses]])
    {
        NSURL* temp = [NSURL fileURLWithPath:NSTemporaryDirectory()];
        NSURL* source = [temp URLByAppendingPathComponent:@"test.txt"];
        NSError* error = nil;
        STAssertTrue([@"Some test text" writeToURL:source atomically:YES encoding:NSUTF8StringEncoding error:&error], @"failed to write temporary file with error %@", error);

        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];

        [self.session createFileAtURL:url withContentsOfURL:source withIntermediateDirectories:YES progressBlock:^(NSUInteger bytesWritten, NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            if (bytesWritten == 0)
            {
                [self.server stop];
            }
        }];

        [self.server runUntilStopped];

        STAssertTrue([[NSFileManager defaultManager] removeItemAtURL:source error:&error], @"failed to remove temporary file with error %@", error);
    }
}

- (void)testRemoveFileAtURL
{
    if ([self setupSessionWithResponses:[KSMockServerFTPResponses standardResponses]])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        [self.session removeFileAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self.server stop];
        }];
    }

    [self.server runUntilStopped];
}

- (void)testRemoveFileAtURLFileDoesnExist
{
    // mostly we use the standard responses, but we use an alternative "fileExists" response to the MKD command, to force the operation to fail
    NSArray* responses = @[[KSMockServerFTPResponses deleFileDoesntExistResponse]];
    responses = [responses arrayByAddingObjectsFromArray:[KSMockServerFTPResponses standardResponses]];

    if ([self setupSessionWithResponses:responses])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        [self.session removeFileAtURL:url completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            long ftpCode = [[[error userInfo] objectForKey:[NSNumber numberWithInt:CURLINFO_RESPONSE_CODE]] longValue];
            STAssertTrue(ftpCode == 550, @"should get 550 from server");

            [self.server stop];
        }];

        [self.server runUntilStopped];
    }

}

- (void)testRemoveFileAtURLBadLogin
{
    if ([self setupSessionWithResponses:[KSMockServerFTPResponses badLoginResponses]])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        [self.session removeFileAtURL:url completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            STAssertTrue([error code] == NSURLErrorUserAuthenticationRequired, @"should get authentication error, got %@ instead", error);

            [self.server stop];
        }];

        [self.server runUntilStopped];
    }
}

- (void)testSetResourceValues
{
    if ([self setupSessionWithResponses:[KSMockServerFTPResponses standardResponses]])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setResourceValues:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self.server stop];
        }];

        [self.server runUntilStopped];
    }
 
}

#endif

- (void)testContentsOfDirectoryAtURLRealServer
{
    __block BOOL running = YES;
    
    if ([self setupSession])
    {
        NSURL* url = [NSURL URLWithString:@"http://www.crushftp.com/#/demo/"];
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
            
            running = NO;
        }];
        
        while (running)
        {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
            }
        }
    }
}

@end
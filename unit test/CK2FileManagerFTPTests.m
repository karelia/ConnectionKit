//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerBaseTests.h"
#import "KSMockServer.h"
#import "KSMockServerRegExResponder.h"

#import "CK2FileManager.h"
#import <SenTestingKit/SenTestingKit.h>
#import <curl/curl.h>

@interface CK2FileManagerFTPTests : CK2FileManagerBaseTests

@end

@implementation CK2FileManagerFTPTests

static NSString *const ExampleListing = @"total 1\r\n-rw-------   1 user  staff     3 Mar  6  2012 file1.txt\r\n-rw-------   1 user  staff     3 Mar  6  2012 file2.txt\r\n\r\n";

+ (NSArray*)ftpInitialResponse
{
    return @[InitialResponseKey, @"220 $address FTP server ($server) ready.\r\n" ];
}

- (BOOL)setup
{
    BOOL result = ([self setupSessionWithRealURL:[NSURL URLWithString:@"ftp://ftp.test.com"] fakeResponses:@"ftp"]);
    self.server.data = [ExampleListing dataUsingEncoding:NSUTF8StringEncoding];

    return result;
}

#pragma mark - Tests

#if !TEST_WITH_REAL_SERVER

- (void)testContentsOfDirectoryAtURL
{
    if ([self setup])
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
                    STAssertTrue([contents[0] isEqual:file1], @"got %@ not %@", contents[0], file1);
                    NSURL* file2 = [self URLForPath:@"/directory/file2.txt"];
                    STAssertTrue([contents[1] isEqual:file2], @"got %@ not %@", contents[0], file2);
                }
            }
            
            [self.server stop];
        }];
        
        [self.server runUntilStopped];
    }
}

- (void)testContentsOfDirectoryAtURLBadLogin
{
    if ([self setup])
    {
        [self useResponseSet:@"bad login"];
        NSURL* url = [self URLForPath:@"/directory/"];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.session contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

            STAssertNotNil(error, @"should get error");
            STAssertTrue([error code] == NSURLErrorUserAuthenticationRequired && [[error domain] isEqualToString:NSURLErrorDomain], @"should get authentication error, got %@ instead", error);
            STAssertTrue([contents count] == 0, @"shouldn't get content");

            [self.server stop];
        }];
        
        [self.server runUntilStopped];
    }
}

- (void)testEnumerateContentsOfURL
{
    if ([self setup])
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
    if ([self setup])
    {
        [self useResponseSet:@"bad login"];
        NSURL* url = [self URLForPath:@"/directory/"];
        NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
        [self.session enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *item) {
            STFail(@"shouldn't get any items");
        } completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            STAssertTrue([error code] == NSURLErrorUserAuthenticationRequired && [[error domain] isEqualToString:NSURLErrorDomain], @"should get authentication error, got %@ instead", error);

            [self.server stop];
        }];

        [self.server runUntilStopped];
    }
}

- (void)testCreateDirectoryAtURL
{
    if ([self setup])
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
    if ([self setupSessionWithRealURL:[NSURL URLWithString:@"ftp://ftp.test.com"] fakeResponses:@"ftp"])
    {
        [self useResponseSet:@"mkdir fail"];
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
    if ([self setup])
    {
        [self useResponseSet:@"bad login"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/newdirectory"];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            STAssertTrue([error code] == NSURLErrorUserAuthenticationRequired && [[error domain] isEqualToString:NSURLErrorDomain], @"should get authentication error, got %@ instead", error);

            [self.server stop];
        }];

        [self.server runUntilStopped];
    }
}

- (void)testCreateFileAtURL
{
    if ([self setup])
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
    if ([self setup])
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
    if ([self setup])
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
    if ([self setup])
    {
        [self useResponseSet:@"delete fail"];
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
    if ([self setup])
    {
        [self useResponseSet:@"bad login"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        [self.session removeFileAtURL:url completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            STAssertTrue([error code] == NSURLErrorUserAuthenticationRequired && [[error domain] isEqualToString:NSURLErrorDomain], @"should get authentication error, got %@ instead", error);

            [self.server stop];
        }];

        [self.server runUntilStopped];
    }
}

- (void)testSetResourceValues
{
    if ([self setup])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setResourceValues:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self.server stop];
        }];

        [self.server runUntilStopped];
    }


    //// Only NSFilePosixPermissions is recognised at present. Note that some servers don't support this so will return an error (code 500)
    //// All other attributes are ignored
    //- (void)setResourceValues:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
    
}

#endif
@end
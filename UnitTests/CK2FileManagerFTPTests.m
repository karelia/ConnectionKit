//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerBaseTests.h"

#import "KMSServer.h"
#import "KMSTranscriptEntry.h"

#import "CK2FileManager.h"
#import <SenTestingKit/SenTestingKit.h>
#import <curl/curl.h>

@interface CK2FileManagerFTPTests : CK2FileManagerBaseTests

@end

@implementation CK2FileManagerFTPTests

static NSString *const ExampleListing = @"total 1\r\n-rw-------   1 user  staff     3 Mar  6  2012 file1.txt\r\n-rw-------   1 user  staff     3 Mar  6  2012 file2.txt\r\n\r\n";

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
            
            [self pause];
        }];
        
        [self runUntilPaused];
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
            STAssertTrue([[error domain] isEqualToString:NSURLErrorDomain] && ([error code] == NSURLErrorUserAuthenticationRequired || [error code] == NSURLErrorUserCancelledAuthentication), @"should get authentication error, got %@ instead", error);
            STAssertTrue([contents count] == 0, @"shouldn't get content");

            [self pause];
        }];
        
        [self runUntilPaused];
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
            [self pause];
        }];
        
        [self runUntilPaused];
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
            STAssertTrue([[error domain] isEqualToString:NSURLErrorDomain] && ([error code] == NSURLErrorUserAuthenticationRequired || [error code] == NSURLErrorUserCancelledAuthentication), @"should get authentication error, got %@ instead", error);

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testCreateDirectoryAtURL
{
    if ([self setup])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/newdirectory"];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];
    }

    [self runUntilPaused];
}

- (void)testCreateDirectoryAtURLAlreadyExists
{
    if ([self setupSessionWithRealURL:[NSURL URLWithString:@"ftp://ftp.test.com"] fakeResponses:@"ftp"])
    {
        [self useResponseSet:@"mkdir fail"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/newdirectory"];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            long ftpCode = [[[error userInfo] objectForKey:@(CURLINFO_RESPONSE_CODE)] longValue];
            STAssertTrue(ftpCode == 550, @"should get 550 from server");

            [self pause];
        }];
    }

    [self runUntilPaused];
}

- (void)testCreateDirectoryAtURLBadLogin
{
    if ([self setup])
    {
        [self useResponseSet:@"bad login"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/newdirectory"];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            STAssertTrue([[error domain] isEqualToString:NSURLErrorDomain] && ([error code] == NSURLErrorUserAuthenticationRequired || [error code] == NSURLErrorUserCancelledAuthentication), @"should get authentication error, got %@ instead", error);

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testCreateFileAtURL
{
    if ([self setup])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];
        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];
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

        [self.session createFileAtURL:url withContentsOfURL:source withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];

        STAssertTrue([[NSFileManager defaultManager] removeItemAtURL:source error:&error], @"failed to remove temporary file with error %@", error);
    }
}

- (void)testCreateFileDenied
{
    if ([self setup])
    {
        [self useResponseSet:@"stor denied"];
        NSURL* url = [self URLForPath:@"/test.txt"];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];
        
        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, nil);
            // TODO: Test for specific error
            
            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

- (void)testCreateFileAtRootReallyGoesIntoRoot
{
    // I found we were constructing URLs wrong for the paths like: /example.txt
    // Such files were ending up in the home folder, rather than root
    
    if ([self setup])
    {
        [self useResponseSet:@"chroot jail"];
        NSURL* url = [self URLForPath:@"/test.txt"];
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];
        
        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"got unexpected error %@", error);
            
            // Make sure the file went into root, rather than home
            // Search for the last CWD command
            __block BOOL haveChangedDirectory = NO;
            [self.server.transcript enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(KMSTranscriptEntry *aTranscriptEntry, NSUInteger idx, BOOL *stop) {
                
                if (aTranscriptEntry.type == KMSTranscriptInput && [aTranscriptEntry.value hasPrefix:@"CWD "])
                {
                    *stop = YES;
                    haveChangedDirectory = YES;
                    STAssertTrue([aTranscriptEntry.value isEqualToString:@"CWD /\r\n"], @"libcurl changed to the wrong directory: %@", aTranscriptEntry.value);
                }
            }];
            
            STAssertTrue(haveChangedDirectory, @"libcurl never changed directory");
            
            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

- (void)testRemoveFileAtURL
{
    if ([self setup])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        [self.session removeItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];
    }

    [self runUntilPaused];
}

- (void)testRemoveFileAtURLFileDoesnExist
{
    if ([self setup])
    {
        [self useResponseSet:@"delete fail"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        [self.session removeItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            long ftpCode = [[[error userInfo] objectForKey:@(CURLINFO_RESPONSE_CODE)] longValue];
            STAssertTrue(ftpCode == 550, @"should get 550 from server");

            [self pause];
        }];

        [self runUntilPaused];
    }

}

- (void)testRemoveFileAtURLBadLogin
{
    if ([self setup])
    {
        [self useResponseSet:@"bad login"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        [self.session removeItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            STAssertTrue([[error domain] isEqualToString:NSURLErrorDomain] && ([error code] == NSURLErrorUserAuthenticationRequired || [error code] == NSURLErrorUserCancelledAuthentication), @"should get authentication error, got %@ instead", error);

            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetUnknownAttributes
{
    if ([self setup])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSDictionary* values = @{ @"test" : @"test" };
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];
        
        [self runUntilPaused];
    }
    
    
    //// Only NSFilePosixPermissions is recognised at present. Note that some servers don't support this so will return an error (code 500)
    //// All other attributes are ignored
    //- (void)setResourceValues:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
    
}

- (void)testSetAttributes
{
    if ([self setup])
    {
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }


    //// Only NSFilePosixPermissions is recognised at present. Note that some servers don't support this so will return an error (code 500)
    //// All other attributes are ignored
    //- (void)setResourceValues:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
    
}

- (void)testSetAttributesCHMODNotUnderstood
{
    if ([self setup])
    {
        [self useResponseSet:@"chmod not understood"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            // For servers which don't understand or support CHMOD, treat as success, like -[NSURL setResourceValue:forKey:error:] does
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesCHMODUnsupported
{
    if ([self setup])
    {
        [self useResponseSet:@"chmod unsupported"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            // For servers which don't understand or support CHMOD, treat as success, like -[NSURL setResourceValue:forKey:error:] does
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesOperationNotPermitted
{
    if ([self setup])
    {
        [self useResponseSet:@"chmod not permitted"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/test.txt"];
        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            // For servers which don't understand or support CHMOD, treat as success, like -[NSURL setResourceValue:forKey:error:] does
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain] && ([error code] == NSFileWriteUnknownError || // FTP has no hard way to know it was a permissions error
                                                                                 [error code] == NSFileWriteNoPermissionError),
                         @"should get error");
            [self pause];
        }];
        
        [self runUntilPaused];
    }
}

- (void)testBadLoginThenGoodLogin
{
    if ([self setup])
    {
        [self useResponseSet:@"bad login"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/newdirectory"];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"should get error");
            STAssertTrue([[error domain] isEqualToString:NSURLErrorDomain] && ([error code] == NSURLErrorUserAuthenticationRequired || [error code] == NSURLErrorUserCancelledAuthentication), @"should get authentication error, got %@ instead", error);

            [self.server pause];
            
            [self useResponseSet:@"default"];
            [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
                STAssertNil(error, @"got unexpected error %@", error);
                
                [self.server pause];
            }];
        }];
    }

    [self runUntilPaused];
}

#endif
@end
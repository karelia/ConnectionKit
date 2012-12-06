//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerBaseTests.h"
#import "KMSServer.h"

#import "CK2FileManager.h"
#import <SenTestingKit/SenTestingKit.h>
#import <curl/curl.h>

@interface CK2FileManagerFileTests : CK2FileManagerBaseTests

@end

@implementation CK2FileManagerFileTests

- (NSURL*)temporaryFolder
{
    NSURL* result = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"CK2FileManagerFileTests"];

    return result;
}

- (void)removeTemporaryFolder
{
    NSError* error = nil;
    NSURL* tempFolder = [self temporaryFolder];
    NSFileManager* fm = [NSFileManager defaultManager];
    [fm removeItemAtURL:tempFolder error:&error];
}

- (BOOL)makeTemporaryFolder
{
    NSError* error = nil;
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* tempFolder = [self temporaryFolder];
    BOOL ok = [fm createDirectoryAtURL:tempFolder withIntermediateDirectories:YES attributes:nil error:&error];
    STAssertTrue(ok, @"couldn't make temporary directory: %@", error);

    return ok;
}

- (NSURL*)makeTestContents
{
    BOOL ok;
    NSError* error = nil;
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* tempFolder = [self temporaryFolder];
    NSURL* testSubfolder = [tempFolder URLByAppendingPathComponent:@"subfolder"];

    NSURL* testFile = [tempFolder URLByAppendingPathComponent:@"test.txt"];
    ok = [@"Some test text" writeToURL:testFile atomically:YES encoding:NSUTF8StringEncoding error:&error];
    STAssertTrue(ok, @"couldn't make test file: %@", error);

    if (ok)
    {
        ok = [fm createDirectoryAtURL:testSubfolder withIntermediateDirectories:YES attributes:nil error:&error];
        STAssertTrue(ok, @"couldn't make test subdirectory: %@", error);
    }

    if (ok)
    {
        NSURL* otherFile = [testSubfolder URLByAppendingPathComponent:@"another.txt"];
        ok = [@"Some more text" writeToURL:otherFile atomically:YES encoding:NSUTF8StringEncoding error:&error];
        STAssertTrue(ok, @"couldn't make other test file: %@", error);
    }

    if (!ok)
    {
        tempFolder = nil;
    }
    
    return tempFolder;
}

- (void)setUp
{
    [self removeTemporaryFolder];
    [self makeTemporaryFolder];
}

- (void)tearDown
{
    [super tearDown];
    [self removeTemporaryFolder];
}

#pragma mark - Tests

- (void)testContentsOfDirectoryAtURL
{
    if ([self setupSession])
    {
        NSURL* url = [self makeTestContents];
        if (url)
        {
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
                        STAssertTrue([[contents[0] lastPathComponent] isEqual:@"subfolder"], @"got %@", contents[0]);
                        STAssertTrue([[contents[1] lastPathComponent] isEqual:@"test.txt"], @"got %@", contents[1]);
                    }
                }
                
                [self pause];
            }];
            
            [self runUntilPaused];
        }
    }
}

- (void)testEnumerateContentsOfDirectoryAtURL
{
    if ([self setupSession])
    {
        NSURL* url = [self makeTestContents];
        if (url)
        {
            NSMutableArray* expected = [@[ @"CK2FileManagerFileTests", @"test.txt", @"subfolder" ] mutableCopy];
            NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
            [self.session enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *url) {

                NSString* name = [url lastPathComponent];
                STAssertTrue([expected containsObject:name], @"unexpected name %@", name);
                [expected removeObject:name];

            } completionHandler:^(NSError *error) {
                STAssertNil(error, @"got unexpected error %@", error);
                [self pause];
            }];

            [self runUntilPaused];

            STAssertTrue([expected count] == 0, @"shouldn't have any items left");
            [expected release];
        }
    }
}

- (void)testCreateDirectoryAtURL
{
    if ([self setupSession])
    {
        NSFileManager* fm = [NSFileManager defaultManager];
        NSURL* temp = [self temporaryFolder];
        NSURL* directory = [temp URLByAppendingPathComponent:@"directory"];
        NSURL* subdirectory = [directory URLByAppendingPathComponent:@"subdirectory"];
        NSError* error = nil;

        [fm removeItemAtURL:subdirectory error:&error];
        [fm removeItemAtURL:directory error:&error];

        // try to make subdirectory with intermediate directory - should fail
        [self.session createDirectoryAtURL:subdirectory withIntermediateDirectories:NO openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileNoSuchFileError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];
        STAssertFalse([fm fileExistsAtPath:[subdirectory path]], @"directory shouldn't exist");

        // try to make subdirectory
        [self.session createDirectoryAtURL:subdirectory withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];


        BOOL isDir = NO;
        STAssertTrue([fm fileExistsAtPath:[subdirectory path] isDirectory:&isDir], @"directory doesn't exist");
        STAssertTrue(isDir, @"somehow we've ended up with a file not a directory");

        // try to make it again - should quietly work
        [self.session createDirectoryAtURL:subdirectory withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];
        STAssertTrue([fm fileExistsAtPath:[subdirectory path] isDirectory:&isDir], @"directory doesn't exist");
        STAssertTrue(isDir, @"somehow we've ended up with a file not a directory");
    }
}

- (void)testCreateDirectoryAtURLNoPermission
{
    if ([self setupSession])
    {
        NSFileManager* fm = [NSFileManager defaultManager];
        NSURL* url = [NSURL fileURLWithPath:@"/System/Test Directory"];

        // try to make subdirectory in /System - this really ought to fail
        [self.session createDirectoryAtURL:url withIntermediateDirectories:NO openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileWriteNoPermissionError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];
        STAssertFalse([fm fileExistsAtPath:[url path]], @"directory shouldn't exist");
    }
}

- (void)testCreateFileAtURL
{
    if ([self setupSession])
    {
        NSFileManager* fm = [NSFileManager defaultManager];
        NSURL* temp = [self temporaryFolder];
        NSURL* directory = [temp URLByAppendingPathComponent:@"directory"];
        NSURL* file = [directory URLByAppendingPathComponent:@"test.txt"];
        NSError* error = nil;

        [fm removeItemAtURL:file error:&error];
        [fm removeItemAtURL:directory error:&error];

        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];

        // try to make file - should fail because intermediate directory isn't present
        [self.session createFileAtURL:file contents:data withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileNoSuchFileError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];

        // try again, should work
        [self.session createFileAtURL:file contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];

        // and again - should fail because the file exists
        [self.session createFileAtURL:file contents:data withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];

    }
}

- (void)testCreateFileAtURLNoPermission
{
    if ([self setupSession])
    {
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];

        // try to make file - should fail because we don't have permission
        NSURL* url = [NSURL fileURLWithPath:@"/System/test.txt"];
        [self.session createFileAtURL:url contents:data withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileWriteNoPermissionError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];

        // try again, should fail again, but this time because we can't make the intermediate directory
        url = [NSURL fileURLWithPath:@"/System/Test Directory/test.txt"];
        [self.session createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileWriteNoPermissionError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];

    }
}

- (void)testCreateFileAtURLWithContents
{
    if ([self setupSession])
    {
        NSFileManager* fm = [NSFileManager defaultManager];
        NSURL* temp = [self temporaryFolder];
        NSURL* directory = [temp URLByAppendingPathComponent:@"directory"];
        NSURL* file = [directory URLByAppendingPathComponent:@"test.txt"];
        NSError* error = nil;

        [fm removeItemAtURL:file error:&error];
        [fm removeItemAtURL:directory error:&error];

        NSURL* source = [temp URLByAppendingPathComponent:@"source.txt"];
        STAssertTrue([@"Some test text" writeToURL:source atomically:YES encoding:NSUTF8StringEncoding error:&error], @"failed to write temporary file with error %@", error);

        // try to make file - should fail because intermediate directory isn't present
        [self.session createFileAtURL:file withContentsOfURL:source withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSPOSIXErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) ENOENT, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];

        // try again, should work
        [self.session createFileAtURL:file withContentsOfURL:source withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];

        // and again - should fail because the file exists
        [self.session createFileAtURL:file withContentsOfURL:source withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];

    }
}

- (void)testCreateFileAtURLWithContentsNoPermission
{
    if ([self setupSession])
    {
        NSError* error = nil;
        NSURL* temp = [self temporaryFolder];
        NSURL* source = [temp URLByAppendingPathComponent:@"source.txt"];
        STAssertTrue([@"Some test text" writeToURL:source atomically:YES encoding:NSUTF8StringEncoding error:&error], @"failed to write temporary file with error %@", error);

        // try to make file - should fail because we don't have permission
        NSURL* url = [NSURL fileURLWithPath:@"/System/test.txt"];
        [self.session createFileAtURL:url withContentsOfURL:source withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSPOSIXErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) EACCES, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];

        // try again, should fail again, but this time because we can't make the intermediate directory
        url = [NSURL fileURLWithPath:@"/System/Test Directory/test.txt"];
        [self.session createFileAtURL:url withContentsOfURL:source withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSPOSIXErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) ENOENT, @"unexpected error code %ld", [error code]);
            
            [self pause];
        }];
        
        [self runUntilPaused];
        
    }
}


- (void)testRemoveFileAtURL
{
    if ([self setupSession])
    {
        NSURL* temp = [self makeTestContents];
        if (temp)
        {
            NSFileManager* fm = [NSFileManager defaultManager];
            NSURL* subdirectory = [temp URLByAppendingPathComponent:@"subfolder"];
            NSURL* testFile = [subdirectory URLByAppendingPathComponent:@"another.txt"];

            STAssertTrue([fm fileExistsAtPath:[testFile path]], @"file should exist");

            // remove a file
            [self.session removeFileAtURL:testFile completionHandler:^(NSError *error) {
                STAssertNil(error, @"got unexpected error %@", error);
                [self pause];
            }];
            [self runUntilPaused];
            STAssertFalse([fm fileExistsAtPath:[testFile path]], @"removal should have worked");

            // remove it again - should obviously fail
            [self.session removeFileAtURL:testFile completionHandler:^(NSError *error) {
                STAssertNotNil(error, @"expected error");
                STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
                STAssertEquals([error code], (NSInteger) NSFileNoSuchFileError, @"unexpected error code %ld", [error code]);
                [self pause];
            }];
            [self runUntilPaused];

            // remove subdirectory - now empty, so should work
            [self.session removeFileAtURL:subdirectory completionHandler:^(NSError *error) {
                STAssertNil(error, @"got unexpected error %@", error);
                [self pause];
            }];
            [self runUntilPaused];
            STAssertFalse([fm fileExistsAtPath:[subdirectory path]], @"removal should have failed");
        }
    }

}

// NSFileManager will happily delete a directory that contains stuff, so
// currently CK2FileManager is doing the same thing.
// If we ever change that, set the following variable to 1 to test for it
#define DELETING_DIRECTORY_WITH_ITEMS_FAILS 0

- (void)testRemoveFileAtURLDirectoryContainingItems
{
    if ([self setupSession])
    {
        NSURL* temp = [self makeTestContents];
        NSURL* subdirectory = [temp URLByAppendingPathComponent:@"subfolder"];

        // remove subdirectory that has something in it - should fail
        [self.session removeFileAtURL:subdirectory completionHandler:^(NSError *error) {
            #if DELETING_DIRECTORY_WITH_ITEMS_FAILS
                STAssertNotNil(error, @"expected error");
                STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
                STAssertEquals([error code], (NSInteger) NSFileNoSuchFileError, @"unexpected error code %ld", [error code]);
            #else
                STAssertNil(error, @"got unexpected error %@", error);
            #endif
            [self pause];
        }];
        [self runUntilPaused];

        #if DELETING_DIRECTORY_WITH_ITEMS_FAILS
            NSFileManager* fm = [NSFileManager defaultManager];
            STAssertTrue([fm fileExistsAtPath:[subdirectory path]], @"removal should have failed");
        #endif
    }
    
}

- (void)testRemoveFileAtURLDoesntExist
{
    if ([self setupSession])
    {
        NSURL* temp = [self temporaryFolder];
        NSURL* testFile = [temp URLByAppendingPathComponent:@"imaginary.txt"];

        [self.session removeFileAtURL:testFile completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected error");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileNoSuchFileError, @"unexpected error code %ld", [error code]);
            [self pause];
        }];
        [self runUntilPaused];

    }
}

- (void)testSetAttributes
{
    if ([self setupSession])
    {
        NSURL* temp = [self makeTestContents];
        NSURL* url = [temp URLByAppendingPathComponent:@"test.txt"];

        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesFileDoesntExist
{
    if ([self setupSession])
    {
        NSURL* temp = [self temporaryFolder];
        NSURL* url = [temp URLByAppendingPathComponent:@"imaginary.txt"];

        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected error");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileNoSuchFileError, @"unexpected error code %ld", [error code]);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesMadeUpAttribute
{
    if ([self setupSession])
    {
        NSURL* temp = [self makeTestContents];
        NSURL* url = [temp URLByAppendingPathComponent:@"test.txt"];

        NSDictionary* values = @{ @"CompletelyBogusAttribute" : @"Chutney" };
        [self.session setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}
#if 0 // TODO: rewrite these tests for the file protocol


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


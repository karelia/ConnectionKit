//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "BaseCKTests.h"
#import "KMSServer.h"

#import "CK2FileManager.h"
#import <SenTestingKit/SenTestingKit.h>
#import <curl/curl.h>

@interface CK2FileManagerFileTests : BaseCKTests

@end

@implementation CK2FileManagerFileTests

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

#pragma mark - Tests

- (void)testContentsOfDirectoryAtURL
{
    if ([self setupTest])
    {
        NSURL* url = [self makeTestContents];
        if (url)
        {
            NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants;
            [self.manager contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:options completionHandler:^(NSArray *contents, NSError *error) {

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
    if ([self setupTest])
    {
        NSURL* url = [self makeTestContents];
        if (url)
        {
            NSString* folderName = [url lastPathComponent];
            NSMutableArray* expected = [@[ folderName, @"test.txt", @"subfolder" ] mutableCopy];
            NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants|CK2DirectoryEnumerationIncludesDirectory;
            [self.manager enumerateContentsOfURL:url includingPropertiesForKeys:nil options:options usingBlock:^(NSURL *url) {

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
    if ([self setupTest])
    {
        NSFileManager* fm = [NSFileManager defaultManager];
        NSURL* temp = [self temporaryFolder];
        NSURL* directory = [temp URLByAppendingPathComponent:@"directory"];
        NSURL* subdirectory = [directory URLByAppendingPathComponent:@"subdirectory"];
        NSError* error = nil;

        [fm removeItemAtURL:subdirectory error:&error];
        [fm removeItemAtURL:directory error:&error];

        // try to make subdirectory with intermediate directory - should fail
        [self.manager createDirectoryAtURL:subdirectory withIntermediateDirectories:NO openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileNoSuchFileError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];
        STAssertFalse([fm fileExistsAtPath:[subdirectory path]], @"directory shouldn't exist");

        // try to make subdirectory
        [self.manager createDirectoryAtURL:subdirectory withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];


        BOOL isDir = NO;
        STAssertTrue([fm fileExistsAtPath:[subdirectory path] isDirectory:&isDir], @"directory doesn't exist");
        STAssertTrue(isDir, @"somehow we've ended up with a file not a directory");

        // try to make it again - should quietly work
        [self.manager createDirectoryAtURL:subdirectory withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
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
    if ([self setupTest])
    {
        NSFileManager* fm = [NSFileManager defaultManager];
        NSURL* url = [NSURL fileURLWithPath:@"/System/Test Directory"];

        // try to make subdirectory in /System - this really ought to fail
        [self.manager createDirectoryAtURL:url withIntermediateDirectories:NO openingAttributes:nil completionHandler:^(NSError *error) {
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
    if ([self setupTest])
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
        [self.manager createFileAtURL:file contents:data withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileNoSuchFileError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];

        // try again, should work
        [self.manager createFileAtURL:file contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];
        STAssertTrue([fm fileExistsAtPath:[file path]], @"file hasn't been copied");
        NSString* string = [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:&error];
        STAssertTrue([string isEqualToString:@"Some test text"], @"bad contents of file: %@", string);

        // and again - should fail because the file exists
        [self resume];
        [self.manager createFileAtURL:file contents:data withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];

    }
}

- (void)testCreateFileAtURLNoPermission
{
    if ([self setupTest])
    {
        NSData* data = [@"Some test text" dataUsingEncoding:NSUTF8StringEncoding];

        // try to make file - should fail because we don't have permission
        NSURL* url = [NSURL fileURLWithPath:@"/System/test.txt"];
        [self.manager createFileAtURL:url contents:data withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileWriteNoPermissionError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];

        // try again, should fail again, but this time because we can't make the intermediate directory
        url = [NSURL fileURLWithPath:@"/System/Test Directory/test.txt"];
        [self.manager createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
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
    if ([self setupTest])
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
        STAssertTrue([fm fileExistsAtPath:[source path]], @"source file hasn't been created");

        // try to make file - should fail because intermediate directory isn't present
        [self.manager createFileAtURL:file withContentsOfURL:source withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileNoSuchFileError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];

        // try again, should work
        [self.manager createFileAtURL:file withContentsOfURL:source withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];

        STAssertTrue([fm fileExistsAtPath:[file path]], @"file hasn't been copied");
        NSString* string = [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:&error];
        STAssertTrue([string isEqualToString:@"Some test text"], @"bad contents of file: %@", string);

        // and again - should fail because the file exists
        [self.manager createFileAtURL:file withContentsOfURL:source withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self pause];
        }];

        [self runUntilPaused];

    }
}

- (void)testCreateFileAtURLWithContentsNoPermission
{
    if ([self setupTest])
    {
        NSError* error = nil;
        NSURL* temp = [self temporaryFolder];
        NSURL* source = [temp URLByAppendingPathComponent:@"source.txt"];
        STAssertTrue([@"Some test text" writeToURL:source atomically:YES encoding:NSUTF8StringEncoding error:&error], @"failed to write temporary file with error %@", error);

        // try to make file - should fail because we don't have permission
        NSURL* url = [NSURL fileURLWithPath:@"/System/test.txt"];
        [self.manager createFileAtURL:url withContentsOfURL:source withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileWriteNoPermissionError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];

        // try again, should fail again, but this time because we can't make the intermediate directory
        url = [NSURL fileURLWithPath:@"/System/Test Directory/test.txt"];
        [self.manager createFileAtURL:url withContentsOfURL:source withIntermediateDirectories:NO openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            STAssertNotNil(error, @"expected an error here");
            STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            STAssertEquals([error code], (NSInteger) NSFileNoSuchFileError, @"unexpected error code %ld", [error code]);
            
            [self pause];
        }];
        
        [self runUntilPaused];
        
    }
}

- (void)testRenameFileAtURL
{
    if ([self setupTest])
    {
        NSURL* temp = [self makeTestContents];
        if (temp)
        {
            NSFileManager* fm = [NSFileManager defaultManager];
            NSURL* subdirectory = [temp URLByAppendingPathComponent:@"subfolder"];
            NSURL* testFile = [subdirectory URLByAppendingPathComponent:@"another.txt"];
            NSString* renamedDirectoryName = @"renamedFolder";
            NSURL* renamedDirectory = [temp URLByAppendingPathComponent:renamedDirectoryName];
            NSString* renamedFileName = @"renamed.txt";
            NSURL* renamedFile = [subdirectory URLByAppendingPathComponent:renamedFileName];

            STAssertTrue([fm fileExistsAtPath:[testFile path]], @"file should exist");
            STAssertTrue(![fm fileExistsAtPath:[renamedFile path]], @"file shouldn't exist");

            // rename file
            [self.manager renameItemAtURL:testFile toFilename:renamedFileName completionHandler:^(NSError *error) {
                STAssertNil(error, @"got unexpected error %@", error);
                [self pause];
            }];
            [self runUntilPaused];

            STAssertTrue(![fm fileExistsAtPath:[testFile path]], @"file shouldn't exist");
            STAssertTrue([fm fileExistsAtPath:[renamedFile path]], @"file should exist");

            // rename it again - should obviously fail
            [self.manager renameItemAtURL:testFile toFilename:renamedFileName completionHandler:^(NSError *error) {
                STAssertNotNil(error, @"expected error");
                STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
                STAssertEquals([error code], (NSInteger) NSFileWriteFileExistsError, @"unexpected error code %ld", [error code]);
                [self pause];
            }];
            [self runUntilPaused];

            // rename directory
            [self.manager renameItemAtURL:subdirectory toFilename:renamedDirectoryName completionHandler:^(NSError *error) {
                STAssertNil(error, @"got unexpected error %@", error);
                [self pause];
            }];
            [self runUntilPaused];

            STAssertTrue(![fm fileExistsAtPath:[subdirectory path]], @"folder shouldn't exist");
            STAssertTrue([fm fileExistsAtPath:[renamedDirectory path]], @"folder should exist");
        }
    }
    

}
- (void)testRemoveFileAtURL
{
    if ([self setupTest])
    {
        NSURL* temp = [self makeTestContents];
        if (temp)
        {
            NSFileManager* fm = [NSFileManager defaultManager];
            NSURL* subdirectory = [temp URLByAppendingPathComponent:@"subfolder"];
            NSURL* testFile = [subdirectory URLByAppendingPathComponent:@"another.txt"];

            STAssertTrue([fm fileExistsAtPath:[testFile path]], @"file should exist");

            // remove a file
            [self.manager removeItemAtURL:testFile completionHandler:^(NSError *error) {
                STAssertNil(error, @"got unexpected error %@", error);
                [self pause];
            }];
            [self runUntilPaused];
            STAssertFalse([fm fileExistsAtPath:[testFile path]], @"removal should have worked");

            // remove it again - should obviously fail
            [self.manager removeItemAtURL:testFile completionHandler:^(NSError *error) {
                STAssertNotNil(error, @"expected error");
                STAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
                STAssertEquals([error code], (NSInteger) NSFileNoSuchFileError, @"unexpected error code %ld", [error code]);
                [self pause];
            }];
            [self runUntilPaused];

            // remove subdirectory - now empty, so should work
            [self.manager removeItemAtURL:subdirectory completionHandler:^(NSError *error) {
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
    if ([self setupTest])
    {
        NSURL* temp = [self makeTestContents];
        NSURL* subdirectory = [temp URLByAppendingPathComponent:@"subfolder"];

        // remove subdirectory that has something in it - should fail
        [self.manager removeItemAtURL:subdirectory completionHandler:^(NSError *error) {
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
    if ([self setupTest])
    {
        NSURL* temp = [self temporaryFolder];
        NSURL* testFile = [temp URLByAppendingPathComponent:@"imaginary.txt"];

        [self.manager removeItemAtURL:testFile completionHandler:^(NSError *error) {
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
    if ([self setupTest])
    {
        NSURL* temp = [self makeTestContents];
        NSURL* url = [temp URLByAppendingPathComponent:@"test.txt"];

        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.manager setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

- (void)testSetAttributesFileDoesntExist
{
    if ([self setupTest])
    {
        NSURL* temp = [self temporaryFolder];
        NSURL* url = [temp URLByAppendingPathComponent:@"imaginary.txt"];

        NSDictionary* values = @{ NSFilePosixPermissions : @(0744)};
        [self.manager setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
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
    if ([self setupTest])
    {
        NSURL* temp = [self makeTestContents];
        NSURL* url = [temp URLByAppendingPathComponent:@"test.txt"];

        // we try to set a completely nonsense attribute
        // the expectation is that this will be silently ignored, rather than causing an error
        NSDictionary* values = @{ @"Awesomeness" : @"Totally Rad" };
        [self.manager setAttributes:values ofItemAtURL:url completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);
            [self pause];
        }];

        [self runUntilPaused];
    }
}

@end


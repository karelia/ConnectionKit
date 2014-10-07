//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "BaseCKProtocolTests.h"

@interface FileTests : BaseCKProtocolTests

@end

@implementation FileTests

- (NSString*)protocol
{
    return @"File";
}

- (BOOL)setupFromSettings
{
    // for the file tests, we always want to use a URL to a temporary folder
    self.url = [self temporaryFolder];

    return YES;
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
    XCTAssertTrue(ok, @"couldn't make test file: %@", error);

    if (ok)
    {
        ok = [fm createDirectoryAtURL:testSubfolder withIntermediateDirectories:YES attributes:nil error:&error];
        XCTAssertTrue(ok, @"couldn't make test subdirectory: %@", error);
    }

    if (ok)
    {
        NSURL* otherFile = [testSubfolder URLByAppendingPathComponent:@"another.txt"];
        ok = [@"Some more text" writeToURL:otherFile atomically:YES encoding:NSUTF8StringEncoding error:&error];
        XCTAssertTrue(ok, @"couldn't make other test file: %@", error);
    }

    if (!ok)
    {
        tempFolder = nil;
    }

    return tempFolder;
}

#pragma mark - Extra File-Only Tests

- (void)testCreateDirectoryAtURLNoPermission
{
    if ([self setupTest])
    {
        NSFileManager* fm = [NSFileManager defaultManager];
        NSURL* url = [NSURL fileURLWithPath:@"/System/Test Directory"];

        // try to make subdirectory in /System - this really ought to fail
        [self.manager createDirectoryAtURL:url withIntermediateDirectories:NO openingAttributes:nil completionHandler:^(NSError *error) {
            XCTAssertNotNil(error, @"expected an error here");
            XCTAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            XCTAssertEqual([error code], (NSInteger) NSFileWriteNoPermissionError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];
        XCTAssertFalse([fm fileExistsAtPath:[url path]], @"directory shouldn't exist");
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
            XCTAssertNotNil(error, @"expected an error here");
            XCTAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            XCTAssertEqual([error code], (NSInteger) NSFileWriteNoPermissionError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];

        // try again, should fail again, but this time because we can't make the intermediate directory
        url = [NSURL fileURLWithPath:@"/System/Test Directory/test.txt"];
        [self.manager createFileAtURL:url contents:data withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
            XCTAssertNotNil(error, @"expected an error here");
            XCTAssertTrue([[error domain] isEqualToString:NSCocoaErrorDomain], @"unexpected error domain %@", [error domain]);
            XCTAssertEqual([error code], (NSInteger) NSFileWriteNoPermissionError, @"unexpected error code %ld", [error code]);

            [self pause];
        }];

        [self runUntilPaused];

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
            XCTAssertNil(error, @"got unexpected error %@", error);
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

@end
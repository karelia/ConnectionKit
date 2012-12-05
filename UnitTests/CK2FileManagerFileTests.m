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

    NSMutableArray* contents = [NSMutableArray array];
    NSDirectoryEnumerator* enumerator = [fm enumeratorAtURL:tempFolder includingPropertiesForKeys:nil options:0 errorHandler:nil];
    for (NSURL* url in enumerator)
    {
        [contents addObject:url];
    }
    for (NSURL* url in contents)
    {
        [fm removeItemAtURL:url error:&error];
    }
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

- (BOOL)makeTestContents
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

    return ok;
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
        if ([self makeTestContents])
        {
            NSURL* url = [self temporaryFolder];
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
        if ([self makeTestContents])
        {
            NSMutableArray* expected = [@[ @"CK2FileManagerFileTests", @"test.txt", @"subfolder" ] mutableCopy];
            NSURL* url = [self temporaryFolder];
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

@end


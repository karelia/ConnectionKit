//
//  Tests.m
//  Tests
//
//  Created by Sam Deane on 08/03/2012.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "CKConnectionRegistry.h"

#import <SenTestingKit/SenTestingKit.h>

@interface PathTests : SenTestCase

@end

@implementation PathTests

- (void)testFTPEmptyNoTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://test.ftp.com"];
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:testURL];
    STAssertTrue([path length] == 0, @"path should be empty");
}

- (void)testFTPEmptyTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://test.ftp.com/"];
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:testURL];
    STAssertTrue([path length] == 0, @"path should be empty");
}

- (void)testFTPRelative
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://test.ftp.com/relative/path/file.txt"];
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:testURL];
    STAssertTrue([path isEqualToString:@"relative/path/file.txt"], @"path shouldn't start with slash");
}

- (void)testFTPAlsolute
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://test.ftp.com//absolute/path/file.txt"];
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:testURL];
    STAssertTrue([path isEqualToString:@"/absolute/path/file.txt"], @"path should start with slash");
}

- (void)testHTTPEmptyNoTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"http://test.ftp.com"];
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:testURL];
    STAssertTrue([path length] == 0, @"path should be empty");
}

- (void)testHTTPEmptyTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"http://test.ftp.com/"];
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:testURL];
    STAssertTrue([path isEqualToString:@"/"], @"path should be /");
}

- (void)testHTTPRelative
{
    NSURL* testURL = [NSURL URLWithString:@"http://test.ftp.com/relative/path/file.txt"];
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:testURL];
    STAssertTrue([path isEqualToString:@"/relative/path/file.txt"], @"path should be absolute from root");
}

- (void)testHTTPAlsolute
{
    NSURL* testURL = [NSURL URLWithString:@"http://test.ftp.com//absolute/path/file.txt"];
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:testURL];
    STAssertTrue([path isEqualToString:@"//absolute/path/file.txt"], @"path should start with double slash");
}

@end

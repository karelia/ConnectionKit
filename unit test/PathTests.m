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

- (void)testEmptyNoTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://test.ftp.com"];
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:testURL];
    STAssertTrue([path length] == 0, @"path should be empty");
}

- (void)testEmptyTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://test.ftp.com/"];
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:testURL];
    STAssertTrue([path length] == 0, @"path should be empty");
}

- (void)testRelative
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://test.ftp.com/relative/path/file.txt"];
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:testURL];
    STAssertTrue([path isEqualToString:@"relative/path/file.txt"], @"path shouldn't start with slash");
}

- (void)testAlsolute
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://test.ftp.com//absolute/path/file.txt"];
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:testURL];
    STAssertTrue([path isEqualToString:@"/absolute/path/file.txt"], @"path should start with slash");
}

@end

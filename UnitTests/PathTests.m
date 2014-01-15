//
//  PathTests.m
//  Connection
//
//  Created by Sam Deane on 08/03/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManager.h"

#import <SenTestingKit/SenTestingKit.h>

@interface PathTests : SenTestCase

@end

@implementation PathTests

- (void)testNilURL
{
    NSString *path;
    STAssertNoThrow(path = [CK2FileManager pathOfURL:nil], nil);
    STAssertNil(path, nil);
}

- (void)testFTPEmptyNoTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://user:pass@test.ftp.com"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path length] == 0, @"path should be empty");
}

- (void)testFTPEmptyTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://user:pass@test.ftp.com/"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path length] == 0, @"path should be empty");
}

- (void)testFTPRelative
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://user:pass@test.ftp.com/relative/path/file.txt"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"relative/path/file.txt"], @"path shouldn't start with slash");
}

- (void)testFTPAbsolute
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://user:pass@test.ftp.com//absolute/path/file.txt"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"/absolute/path/file.txt"], @"path should start with slash");
}

- (void)testFTPAbsolutePercentEncoded
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://user:pass@test.ftp.com/%2Fabsolute/path/file.txt"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"/absolute/path/file.txt"], @"path should start with slash");
}

- (void)testFTPAbsolutePercentEncodedExtraSlash
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://user:pass@test.ftp.com/%2F/absolute/path/file.txt"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"//absolute/path/file.txt"], @"path should start with slash");
}

- (void)testFTPRoot
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://user:pass@test.ftp.com//"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"/"], @"path should start with slash");
}

- (void)testFTPRootPercentEncoded
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://user:pass@test.ftp.com/%2F"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"/"], @"path should start with slash");
}

- (void)testFTPRootPercentEncodedExtraSlash
{
    NSURL* testURL = [NSURL URLWithString:@"ftp://user:pass@test.ftp.com/%2F/"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"/"], @"trailing slashes should be trimmed");
}

- (void)testHTTPEmptyNoTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"http://www.test.com:8080"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path length] == 0, @"path should be empty");
}

- (void)testHTTPEmptyTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"http://www.test.com:8080/"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"/"], @"path should be /");
}

- (void)testHTTPRelative
{
    NSURL* testURL = [NSURL URLWithString:@"http://www.test.com:8080/relative/path/file.txt"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"/relative/path/file.txt"], @"path should be absolute from root");
}

- (void)testHTTPAbsolute
{
    NSURL* testURL = [NSURL URLWithString:@"http://www.test.com:8080//absolute/path/file.txt"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"//absolute/path/file.txt"], @"path should start with double slash");
}

- (void)testSFTPEmptyNoTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"sftp://user@test.sftp.com"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path length] == 0, @"path should be empty");
}

- (void)testSFTPEmptyTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"sftp://user@test.sftp.com/"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"/"], @"path should be /");
}

- (void)testSFTPRelative
{
    NSURL* testURL = [NSURL URLWithString:@"sftp://user@test.sftp.com/relative/path/file.txt"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"/relative/path/file.txt"], @"path should be absolute from root");
}

- (void)testSFTPAbsolute
{
    NSURL* testURL = [NSURL URLWithString:@"sftp://user@test.sftp.com//absolute/path/file.txt"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"//absolute/path/file.txt"], @"path should start with double slash");
}

- (void)testSFTPUser
{
    NSURL* testURL = [NSURL URLWithString:@"sftp://user@test.sftp.com/~/absolute/path/file.txt"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"absolute/path/file.txt"], @"path should strip the /~");
}

- (void)testSCPEmptyNoTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"scp://user@test.scp.com"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path length] == 0, @"path should be empty");
}

- (void)testSCPEmptyTrailingSlash
{
    NSURL* testURL = [NSURL URLWithString:@"scp://user@test.scp.com/"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"/"], @"path should be /");
}

- (void)testSCPRelative
{
    NSURL* testURL = [NSURL URLWithString:@"scp://user@test.scp.com/relative/path/file.txt"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"/relative/path/file.txt"], @"path should be absolute from root");
}

- (void)testSCPAbsolute
{
    NSURL* testURL = [NSURL URLWithString:@"scp://user@test.scp.com//absolute/path/file.txt"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"//absolute/path/file.txt"], @"path should start with double slash");
}

- (void)testSCPUser
{
    NSURL* testURL = [NSURL URLWithString:@"scp://user@test.scp.com/~/absolute/path/file.txt"];
    NSString* path = [CK2FileManager pathOfURL:testURL];
    STAssertTrue([path isEqualToString:@"absolute/path/file.txt"], @"path should strip the /~");
}

@end

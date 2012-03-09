//
//  URLTests.m
//  Connection
//
//  Created by Mike Abdullah on 09/03/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CKConnectionRegistry.h"

#import <SenTestingKit/SenTestingKit.h>

@interface URLTests : SenTestCase

@end

@implementation URLTests

- (void)testFTPRelative
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    
    STAssertTrue([[url absoluteString] isEqualToString:@"ftp://user:pass@test.ftp.com/relative/path/file.txt"], @"path should start with slash");
}

- (void)testFTPAbsolute
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    
    STAssertEqualObjects([url absoluteString], @"ftp://user:pass@test.ftp.com//absolute/path/file.txt", @"path should start with double slash");
}

- (void)testFTPRoot
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"/"
                                                                relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    STAssertTrue([[url absoluteString] isEqualToString:@"ftp://user:pass@test.ftp.com//"], @"path should be double slash");
}

- (void)testHTTPRelative
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080"]];
    
    STAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/relative/path/file.txt", @"path should be normal");
}

- (void)testHTTPAbsolute
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080"]];
    
    STAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/absolute/path/file.txt", @"path should be normal");
}

- (void)testSFTPRelative
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com"]];
    
    STAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSFTPRelativeTrailingSlash
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com/"]];
    
    STAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSFTPAbsolute
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com"]];
    
    STAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/absolute/path/file.txt", @"path should be normal");
}

- (void)testSFTPAbsoluteTrailingSlash
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com/"]];
    
    STAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/absolute/path/file.txt", @"path should be normal");
}

- (void)testSCPRelative
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"scp://user@test.scp.com"]];
    
    STAssertEqualObjects([url absoluteString], @"scp://user@test.scp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSCPRelativeTrailingSlash
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"scp://user@test.scp.com/"]];
    
    STAssertEqualObjects([url absoluteString], @"scp://user@test.scp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSCPAbsolute
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"scp://user@test.scp.com"]];
    
    STAssertEqualObjects([url absoluteString], @"scp://user@test.scp.com/absolute/path/file.txt", @"path should be normal");
}

- (void)testSCPAbsoluteTrailingSlash
{
    NSURL *url = [[CKConnectionRegistry sharedConnectionRegistry] URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"scp://user@test.scp.com/"]];
    
    STAssertEqualObjects([url absoluteString], @"scp://user@test.scp.com/absolute/path/file.txt", @"path should be normal");
}

@end

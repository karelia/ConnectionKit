//
//  URLTests.m
//  Connection
//
//  Created by Mike Abdullah on 09/03/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManager.h"

#import <SenTestingKit/SenTestingKit.h>

@interface URLTests : SenTestCase

@end

@implementation URLTests

- (void)testFTPRelative
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    
    STAssertTrue([[url absoluteString] isEqualToString:@"ftp://user:pass@test.ftp.com/relative/path/file.txt"], @"path should start with slash");
}

- (void)testFTPAbsolute
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    
    STAssertEqualObjects([url absoluteString], @"ftp://user:pass@test.ftp.com/%2Fabsolute/path/file.txt", nil);
}

- (void)testFTPAbsoluteNonRootURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/path/"]];
    
    STAssertEqualObjects([url absoluteString], @"ftp://user:pass@test.ftp.com/%2Fabsolute/path/file.txt", nil);
}

- (void)testFTPRelativeNonRootFolderURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/path/"]];
    
    STAssertEqualObjects(url.absoluteString, @"ftp://user:pass@test.ftp.com/example/path/relative/path/file.txt", nil);
}

- (void)testFTPRelativeNonRootFileURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/file"]];
    
    STAssertEqualObjects(url.absoluteString, @"ftp://user:pass@test.ftp.com/example/relative/path/file.txt", nil);
}

- (void)testFTPRoot
{
    NSURL *url = [CK2FileManager URLWithPath:@"/"
                                                                relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    STAssertTrue([[url absoluteString] isEqualToString:@"ftp://user:pass@test.ftp.com/%2F"], nil);
}

- (void)testFTPRootNonRootURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"/"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/path/"]];
    STAssertTrue([[url absoluteString] isEqualToString:@"ftp://user:pass@test.ftp.com/%2F"], nil);
}

- (void)testHTTPRelative
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080"]];
    
    STAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/relative/path/file.txt", @"path should be normal");
}

- (void)testHTTPAbsolute
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080"]];
    
    STAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/absolute/path/file.txt", @"path should be normal");
}

- (void)testSFTPRelative
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com"]];
    
    STAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSFTPRelativeTrailingSlash
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com/"]];
    
    STAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSFTPAbsolute
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com"]];
    
    STAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/absolute/path/file.txt", @"path should be normal");
}

- (void)testSFTPAbsoluteTrailingSlash
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com/"]];
    
    STAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/absolute/path/file.txt", @"path should be normal");
}

- (void)testSCPRelative
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"scp://user@test.scp.com"]];
    
    STAssertEqualObjects([url absoluteString], @"scp://user@test.scp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSCPRelativeTrailingSlash
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"scp://user@test.scp.com/"]];
    
    STAssertEqualObjects([url absoluteString], @"scp://user@test.scp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSCPAbsolute
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"scp://user@test.scp.com"]];
    
    STAssertEqualObjects([url absoluteString], @"scp://user@test.scp.com/absolute/path/file.txt", @"path should be normal");
}

- (void)testSCPAbsoluteTrailingSlash
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"scp://user@test.scp.com/"]];
    
    STAssertEqualObjects([url absoluteString], @"scp://user@test.scp.com/absolute/path/file.txt", @"path should be normal");
}

@end

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

#pragma mark FTP

- (void)testFTPRelative
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    STAssertTrue([[url absoluteString] isEqualToString:@"ftp://user:pass@test.ftp.com/relative/path/file.txt"], @"path should start with slash");
    
    url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                          isDirectory:NO
                              hostURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    STAssertTrue([url.relativeString isEqualToString:@"ftp://user:pass@test.ftp.com/relative/path/file.txt"], @"path should start with slash");
}

- (void)testFTPAbsolute
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    STAssertEqualObjects([url absoluteString], @"ftp://user:pass@test.ftp.com//absolute/path/file.txt", nil);
    
    url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                          isDirectory:NO
                              hostURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    STAssertEqualObjects(url.relativeString, @"ftp://user:pass@test.ftp.com//absolute/path/file.txt", nil);
}

- (void)testFTPAbsoluteNonRootURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/path/"]];
    STAssertEqualObjects([url absoluteString], @"ftp://user:pass@test.ftp.com//absolute/path/file.txt", nil);
    
    url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                          isDirectory:NO
                              hostURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/path/"]];
    STAssertEqualObjects(url.relativeString, @"ftp://user:pass@test.ftp.com//absolute/path/file.txt", nil);
}

- (void)testFTPRelativeNonRootFolderURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/path/"]];
    STAssertEqualObjects(url.absoluteString, @"ftp://user:pass@test.ftp.com/example/path/relative/path/file.txt", nil);
    
    url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                          isDirectory:NO
                              hostURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/path/"]];
    STAssertEqualObjects(url.relativeString, @"ftp://user:pass@test.ftp.com/relative/path/file.txt", nil);
}

- (void)testFTPRelativeNonRootFileURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/file"]];
    STAssertEqualObjects(url.absoluteString, @"ftp://user:pass@test.ftp.com/example/relative/path/file.txt", nil);
    
    url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                          isDirectory:NO
                              hostURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/file"]];
    STAssertEqualObjects(url.relativeString, @"ftp://user:pass@test.ftp.com/relative/path/file.txt", nil);
}

- (void)testFTPRoot
{
    NSURL *url = [CK2FileManager URLWithPath:@"/"
                                                                relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    STAssertTrue([[url absoluteString] isEqualToString:@"ftp://user:pass@test.ftp.com//"], nil);
}

- (void)testFTPRootNonRootURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"/"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/path/"]];
    STAssertTrue([[url absoluteString] isEqualToString:@"ftp://user:pass@test.ftp.com//"], nil);
}

#pragma mark WebDAV

- (void)testHTTPRelative
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080"]];
    STAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/relative/path/file.txt", @"path should be normal");
    
    url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                          isDirectory:NO
                              hostURL:[NSURL URLWithString:@"http://www.test.com:8080"]];
    STAssertEqualObjects(url.relativeString, @"http://www.test.com:8080/relative/path/file.txt", @"path should be normal");
}

- (void)testHTTPAbsolute
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080"]];
    STAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/absolute/path/file.txt", @"path should be normal");
    
    url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                          isDirectory:NO
                        hostURL:[NSURL URLWithString:@"http://www.test.com:8080"]];
    STAssertEqualObjects(url.relativeString, @"http://www.test.com:8080/absolute/path/file.txt", @"path should be normal");
}

- (void)testHTTPRelativeNonRootFolderURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080/example/path/"]];
    STAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/example/path/relative/path/file.txt", nil);
    
    url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                          isDirectory:NO
                              hostURL:[NSURL URLWithString:@"http://www.test.com:8080/example/path/"]];
    STAssertEqualObjects(url.relativeString, @"http://www.test.com:8080/relative/path/file.txt", nil);
}

- (void)testHTTPRelativeNonRootFileURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080/example/file"]];
    STAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/example/relative/path/file.txt", nil);
    
    url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                          isDirectory:NO
                              hostURL:[NSURL URLWithString:@"http://www.test.com:8080/example/file"]];
    STAssertEqualObjects(url.relativeString, @"http://www.test.com:8080/relative/path/file.txt", nil);
}

#pragma mark SSH

- (void)testSFTPRelative
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com"]];
    STAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/~/relative/path/file.txt", @"path should start with ~");
    
    url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                          isDirectory:NO
                              hostURL:[NSURL URLWithString:@"sftp://user@test.sftp.com"]];
    STAssertEqualObjects(url.relativeString, @"sftp://user@test.sftp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSFTPRelativeTrailingSlash
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com/"]];
    STAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/~/relative/path/file.txt", @"path should start with ~");
    
    url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                          isDirectory:NO
                              hostURL:[NSURL URLWithString:@"sftp://user@test.sftp.com/"]];
    STAssertEqualObjects(url.relativeString, @"sftp://user@test.sftp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSFTPRelativeNonRootFolderURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                 isDirectory:NO
                                     hostURL:[NSURL URLWithString:@"sftp://user:pass@test.ftp.com/example/path/"]];
    STAssertEqualObjects(url.relativeString, @"sftp://user:pass@test.ftp.com/~/relative/path/file.txt", nil);
}

- (void)testSFTPRelativeNonRootFileURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                 isDirectory:NO
                                     hostURL:[NSURL URLWithString:@"sftp://user:pass@test.ftp.com/example/file"]];
    STAssertEqualObjects(url.relativeString, @"sftp://user:pass@test.ftp.com/~/relative/path/file.txt", nil);
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

#pragma mark file

- (void)testMakingLocalDirectoryURL;
{
    // My standard trick of making a directory by appending path component of @"" turns out to
    // have a caveat: http://www.mikeabdullah.net/guaranteeing-directory-urls.html
    // This isn't too good for our clients as an inconsistency
    NSURL *url = [CK2FileManager URLWithPath:@"/Users/Shared"
                                 isDirectory:YES
                                     hostURL:[NSURL URLWithString:@"file:///foo/bar"]];
    
    STAssertEqualObjects(url.absoluteString, @"file:///Users/Shared/", @"URL should not have double trailing slash");
}

@end

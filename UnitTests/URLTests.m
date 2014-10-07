//
//  URLTests.m
//  Connection
//
//  Created by Mike Abdullah on 09/03/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManager.h"

#import <XCTest/XCTest.h>

@interface URLTests : XCTestCase

@end

@implementation URLTests

- (void)testURLs {
    NSURL *suiteURL = [[NSBundle bundleForClass:self.class] URLForResource:@"URLs" withExtension:@"testdata"];
    NSArray *suite = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:suiteURL] options:0 error:NULL];
    XCTAssertTrue(suite.count >= 1);
    
    for (NSDictionary *values in suite) {
        NSString *path = values[@"path"];
        BOOL directory = [values[@"isDirectory"] boolValue];
        NSURL *base = [NSURL URLWithString:values[@"hostURL"]];
        
        NSURL *url = [CK2FileManager URLWithPath:path isDirectory:directory hostURL:base];
        XCTAssertEqualObjects(url.absoluteString, values[@"Output"]);
        XCTAssertNil(url.baseURL, @"+URLWithPath:isDirectory:hostURL: should always return an absolute URL");
    }
}

#pragma mark FTP

- (void)testFTPRelative
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    XCTAssertTrue([[url absoluteString] isEqualToString:@"ftp://user:pass@test.ftp.com/relative/path/file.txt"], @"path should start with slash");
}

- (void)testFTPRelativeDirectory
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/directory"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    XCTAssertTrue([[url absoluteString] isEqualToString:@"ftp://user:pass@test.ftp.com/relative/path/directory"], @"path should start with slash");
}

- (void)testFTPAbsolute
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    XCTAssertEqualObjects([url absoluteString], @"ftp://user:pass@test.ftp.com//absolute/path/file.txt");
}

- (void)testFTPAbsoluteNonRootURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/path/"]];
    XCTAssertEqualObjects([url absoluteString], @"ftp://user:pass@test.ftp.com//absolute/path/file.txt");
}

- (void)testFTPRelativeNonRootFolderURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/path/"]];
    XCTAssertEqualObjects(url.absoluteString, @"ftp://user:pass@test.ftp.com/example/path/relative/path/file.txt");
}

- (void)testFTPRelativeNonRootFileURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/file"]];
    XCTAssertEqualObjects(url.absoluteString, @"ftp://user:pass@test.ftp.com/example/relative/path/file.txt");
}

- (void)testFTPRoot
{
    NSURL *url = [CK2FileManager URLWithPath:@"/"
                                                                relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com"]];
    XCTAssertTrue([[url absoluteString] isEqualToString:@"ftp://user:pass@test.ftp.com//"]);
}

- (void)testFTPRootNonRootURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"/"
                               relativeToURL:[NSURL URLWithString:@"ftp://user:pass@test.ftp.com/example/path/"]];
    XCTAssertTrue([[url absoluteString] isEqualToString:@"ftp://user:pass@test.ftp.com//"]);
}

#pragma mark WebDAV

- (void)testHTTPRelative
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080"]];
    XCTAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/relative/path/file.txt", @"path should be normal");
}

- (void)testHTTPRelativeDirectory
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/directory"
                                                                relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080"]];
    XCTAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/relative/path/directory", @"path should be normal");
}

- (void)testHTTPAbsolute
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080"]];
    XCTAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/absolute/path/file.txt", @"path should be normal");
}

- (void)testHTTPRelativeNonRootFolderURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080/example/path/"]];
    XCTAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/example/path/relative/path/file.txt");
}

- (void)testHTTPRelativeNonRootFileURL
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                               relativeToURL:[NSURL URLWithString:@"http://www.test.com:8080/example/file"]];
    XCTAssertEqualObjects([url absoluteString], @"http://www.test.com:8080/example/relative/path/file.txt");
}

#pragma mark SSH

- (void)testSFTPRelative
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com"]];
    XCTAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSFTPRelativeTrailingSlash
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com/"]];
    XCTAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSFTPRelativeDirectory
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/directory"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com"]];
    XCTAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/~/relative/path/directory", @"path should start with ~");
}

- (void)testSFTPAbsolute
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com"]];
    
    XCTAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/absolute/path/file.txt", @"path should be normal");
}

- (void)testSFTPAbsoluteTrailingSlash
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"sftp://user@test.sftp.com/"]];
    
    XCTAssertEqualObjects([url absoluteString], @"sftp://user@test.sftp.com/absolute/path/file.txt", @"path should be normal");
}

- (void)testSCPRelative
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"scp://user@test.scp.com"]];
    
    XCTAssertEqualObjects([url absoluteString], @"scp://user@test.scp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSCPRelativeTrailingSlash
{
    NSURL *url = [CK2FileManager URLWithPath:@"relative/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"scp://user@test.scp.com/"]];
    
    XCTAssertEqualObjects([url absoluteString], @"scp://user@test.scp.com/~/relative/path/file.txt", @"path should start with ~");
}

- (void)testSCPAbsolute
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"scp://user@test.scp.com"]];
    
    XCTAssertEqualObjects([url absoluteString], @"scp://user@test.scp.com/absolute/path/file.txt", @"path should be normal");
}

- (void)testSCPAbsoluteTrailingSlash
{
    NSURL *url = [CK2FileManager URLWithPath:@"/absolute/path/file.txt"
                                                                relativeToURL:[NSURL URLWithString:@"scp://user@test.scp.com/"]];
    
    XCTAssertEqualObjects([url absoluteString], @"scp://user@test.scp.com/absolute/path/file.txt", @"path should be normal");
}

@end

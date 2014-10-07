//
//  URLAppendingTests.m
//  Connection
//
//  Created by Mike on 31/01/2013.
//
//

#import <XCTest/XCTest.h>

@interface URLAppendingTests : XCTestCase

@end


@implementation URLAppendingTests

- (void)testFTPAppendToRoot;
{
    XCTAssertEqualObjects([[NSURL URLWithString:@"ftp://example.com/%2F"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"ftp://example.com/%2F/test1.txt"]);
    
    XCTAssertEqualObjects([[NSURL URLWithString:@"ftp://example.com//"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"ftp://example.com//test1.txt"]);
}

- (void)testFTPAppendToAbsoluteDirectory;
{
    XCTAssertEqualObjects([[NSURL URLWithString:@"ftp://example.com/%2Ftest/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"ftp://example.com/%2Ftest/test1.txt"]);
    
    XCTAssertEqualObjects([[NSURL URLWithString:@"ftp://example.com//test/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"ftp://example.com//test/test1.txt"]);
}

- (void)testFTPAppendToHome;
{
    XCTAssertEqualObjects([[NSURL URLWithString:@"ftp://example.com/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"ftp://example.com/test1.txt"]);
}

- (void)testFTPAppendToHomeSubdirectory;
{
    XCTAssertEqualObjects([[NSURL URLWithString:@"ftp://example.com/test/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"ftp://example.com/test/test1.txt"]);
}

- (void)testSFTPAppendToRoot;
{
    XCTAssertEqualObjects([[NSURL URLWithString:@"sftp://example.com/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"sftp://example.com/test1.txt"]);
}

- (void)testSFTPAppendToAbsoluteDirectory;
{
    XCTAssertEqualObjects([[NSURL URLWithString:@"sftp://example.com/test/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"sftp://example.com/test/test1.txt"]);
}

- (void)testSFTPAppendToHome;
{
    XCTAssertEqualObjects([[NSURL URLWithString:@"sftp://example.com/~/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"sftp://example.com/~/test1.txt"]);
}

- (void)testSFTPAppendToHomeSubdirectory;
{
    XCTAssertEqualObjects([[NSURL URLWithString:@"sftp://example.com/~/test/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"sftp://example.com/~/test/test1.txt"]);
}

- (void)testFTPRootIsDirectory;
{
    BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"ftp://example.com/%2F"]);
    XCTAssertFalse(isDirectory);
}

- (void)testFTPRootWithTrailingSlashIsDirectory;
{
    BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"ftp://example.com/%2F/"]);
    XCTAssertTrue(isDirectory);
}

- (void)testFTPHomeIsDirectory;
{
    BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"ftp://example.com/"]);
    XCTAssertTrue(isDirectory);
}

- (void)testFTPHomeWithoutTrailingSlashIsDirectory;
{
    BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"ftp://example.com"]);
    XCTAssertFalse(isDirectory);
}

- (void)testFTPAbsoluteFileIsDirectory;
{
    BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"ftp://example.com/%2F/test.txt"]);
    XCTAssertFalse(isDirectory);
}

- (void)testFTPRelativeFileIsDirectory;
{
    BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"ftp://example.com/test.txt"]);
    XCTAssertFalse(isDirectory);
}

@end


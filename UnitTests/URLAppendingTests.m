//
//  URLAppendingTests.m
//  Connection
//
//  Created by Mike on 31/01/2013.
//
//

#import <SenTestingKit/SenTestingKit.h>

@interface URLAppendingTests : SenTestCase

@end


@implementation URLAppendingTests

- (void)testFTPAppendToRoot;
{
    STAssertEqualObjects([[NSURL URLWithString:@"ftp://example.com/%2F"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"ftp://example.com/%2F/test1.txt"],
                         nil);
    
    STAssertEqualObjects([[NSURL URLWithString:@"ftp://example.com//"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"ftp://example.com//test1.txt"],
                         nil);
}

- (void)testFTPAppendToAbsoluteDirectory;
{
    STAssertEqualObjects([[NSURL URLWithString:@"ftp://example.com/%2Ftest/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"ftp://example.com/%2Ftest/test1.txt"],
                         nil);
    
    STAssertEqualObjects([[NSURL URLWithString:@"ftp://example.com//test/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"ftp://example.com//test/test1.txt"],
                         nil);
}

- (void)testFTPAppendToHome;
{
    STAssertEqualObjects([[NSURL URLWithString:@"ftp://example.com/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"ftp://example.com/test1.txt"],
                         nil);
}

- (void)testFTPAppendToHomeSubdirectory;
{
    STAssertEqualObjects([[NSURL URLWithString:@"ftp://example.com/test/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"ftp://example.com/test/test1.txt"],
                         nil);
}

- (void)testSFTPAppendToRoot;
{
    STAssertEqualObjects([[NSURL URLWithString:@"sftp://example.com/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"sftp://example.com/test1.txt"],
                         nil);
}

- (void)testSFTPAppendToAbsoluteDirectory;
{
    STAssertEqualObjects([[NSURL URLWithString:@"sftp://example.com/test/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"sftp://example.com/test/test1.txt"],
                         nil);
}

- (void)testSFTPAppendToHome;
{
    STAssertEqualObjects([[NSURL URLWithString:@"sftp://example.com/~/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"sftp://example.com/~/test1.txt"],
                         nil);
}

- (void)testSFTPAppendToHomeSubdirectory;
{
    STAssertEqualObjects([[NSURL URLWithString:@"sftp://example.com/~/test/"] URLByAppendingPathComponent:@"test1.txt"],
                         [NSURL URLWithString:@"sftp://example.com/~/test/test1.txt"],
                         nil);
}

- (void)testFTPRootIsDirectory;
{
    BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"ftp://example.com/%2F"]);
    STAssertFalse(isDirectory, nil);
}

- (void)testFTPRootWithTrailingSlashIsDirectory;
{
    BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"ftp://example.com/%2F/"]);
    STAssertTrue(isDirectory, nil);
}

- (void)testFTPHomeIsDirectory;
{
    BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"ftp://example.com/"]);
    STAssertTrue(isDirectory, nil);
}

- (void)testFTPHomeWithoutTrailingSlashIsDirectory;
{
    BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"ftp://example.com"]);
    STAssertFalse(isDirectory, nil);
}

- (void)testFTPAbsoluteFileIsDirectory;
{
    BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"ftp://example.com/%2F/test.txt"]);
    STAssertFalse(isDirectory, nil);
}

- (void)testFTPRelativeFileIsDirectory;
{
    BOOL isDirectory = CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"ftp://example.com/test.txt"]);
    STAssertFalse(isDirectory, nil);
}

@end


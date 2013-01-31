//
//  URLAppendingTests.m
//  Connection
//
//  Created by Mike on 31/01/2013.
//
//

#import <SenTestingKit/SenTestingKit.h>

#import "CK2SFTPProtocol.h"
#import "CK2FTPProtocol.h"

@interface URLAppendingTests : SenTestCase

@end


@implementation URLAppendingTests

- (void)testFTPAppendToRoot;
{
    STAssertEqualObjects([CK2FTPProtocol URLByAppendingPathComponent:@"test1.txt"
                                                               toURL:[NSURL URLWithString:@"ftp://example.com/%2F"]
                                                         isDirectory:NO],
                         [NSURL URLWithString:@"ftp://example.com/%2Ftest1.txt"],
                         nil);
}

- (void)testFTPAppendToAbsoluteDirectory;
{
    STAssertEqualObjects([CK2FTPProtocol URLByAppendingPathComponent:@"test1.txt"
                                                               toURL:[NSURL URLWithString:@"ftp://example.com/%2Ftest/"]
                                                         isDirectory:NO],
                         [NSURL URLWithString:@"ftp://example.com/%2Ftest/test1.txt"],
                         nil);
}

- (void)testFTPAppendToHome;
{
    STAssertEqualObjects([CK2FTPProtocol URLByAppendingPathComponent:@"test1.txt"
                                                               toURL:[NSURL URLWithString:@"ftp://example.com/"]
                                                         isDirectory:NO],
                         [NSURL URLWithString:@"ftp://example.com/test1.txt"],
                         nil);
}

- (void)testFTPAppendToHomeSubdirectory;
{
    STAssertEqualObjects([CK2FTPProtocol URLByAppendingPathComponent:@"test1.txt"
                                                               toURL:[NSURL URLWithString:@"ftp://example.com/test/"]
                                                         isDirectory:NO],
                         [NSURL URLWithString:@"ftp://example.com/test/test1.txt"],
                         nil);
}

- (void)testSFTPAppendToRoot;
{
    STAssertEqualObjects([CK2SFTPProtocol URLByAppendingPathComponent:@"test1.txt"
                                                                toURL:[NSURL URLWithString:@"sftp://example.com/"]
                                                          isDirectory:NO],
                         [NSURL URLWithString:@"sftp://example.com/test1.txt"],
                         nil);
}

- (void)testSFTPAppendToAbsoluteDirectory;
{
    STAssertEqualObjects([CK2SFTPProtocol URLByAppendingPathComponent:@"test1.txt"
                                                                toURL:[NSURL URLWithString:@"sftp://example.com/test/"]
                                                          isDirectory:NO],
                         [NSURL URLWithString:@"sftp://example.com/test/test1.txt"],
                         nil);
}

- (void)testSFTPAppendToHome;
{
    STAssertEqualObjects([CK2SFTPProtocol URLByAppendingPathComponent:@"test1.txt"
                                                                toURL:[NSURL URLWithString:@"sftp://example.com/~/"]
                                                          isDirectory:NO],
                         [NSURL URLWithString:@"sftp://example.com/~/test1.txt"],
                         nil);
}

- (void)testSFTPAppendToHomeSubdirectory;
{
    STAssertEqualObjects([CK2SFTPProtocol URLByAppendingPathComponent:@"test1.txt"
                                                                toURL:[NSURL URLWithString:@"sftp://example.com/~/test/"]
                                                          isDirectory:NO],
                         [NSURL URLWithString:@"sftp://example.com/~/test/test1.txt"],
                         nil);
}

@end

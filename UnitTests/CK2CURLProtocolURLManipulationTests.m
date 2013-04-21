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


#pragma mark -


@interface CK2CURLBasedProtocol (UnitTesting)
+ (NSURLRequest *)newRequestWithRequest:(NSURLRequest *)request isDirectory:(BOOL)directory;
@end


@interface URLDirectoryTests : SenTestCase
@end


@implementation URLDirectoryTests

/*  We test with all absolute FTP URL forms to make sure they don't get mangled
 */

- (void)testFileURL;
{
    NSURL *url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com//test"]]
                                                 isDirectory:NO].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com//test", nil);
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2Ftest"]]
                                          isDirectory:NO].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2Ftest", nil);
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2F/test"]]
                                          isDirectory:NO].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2F/test", nil);
}

- (void)testMakingFileIntoFolder;
{
    NSURL *url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com//test"]]
                                                 isDirectory:YES].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com//test/", nil);
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2Ftest"]]
                                          isDirectory:YES].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2Ftest/", nil);
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2F/test"]]
                                          isDirectory:YES].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2F/test/", nil);
    
    // This has been giving some problems where Cocoa normally recognises the %2F as a folder, I think
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2F"]]
                                          isDirectory:YES].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2F/", nil);
}

- (void)testFolderURL;
{
    NSURL *url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com//test/"]]
                                                 isDirectory:YES].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com//test/", nil);
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2Ftest/"]]
                                          isDirectory:YES].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2Ftest/", nil);
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2F/test/"]]
                                          isDirectory:YES].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2F/test/", nil);
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2F/"]]
                                          isDirectory:YES].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2F/", nil);
}

- (void)testMakingFolderIntoFile;
{
    NSURL *url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com//test/"]]
                                                 isDirectory:NO].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com//test", nil);
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2Ftest/"]]
                                          isDirectory:NO].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com//test", nil);
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2F/test/"]]
                                          isDirectory:NO].URL;
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2F/test", nil);
}

@end


#pragma mark -


@interface URLCanonicalizationTests : SenTestCase
@end


@implementation URLCanonicalizationTests

- (void)testIncludingUser;
{    
    // Test first with no user set. e.g. anonymous login
    NSURL *url = [CK2CURLBasedProtocol URLByReplacingUserInfoInURL:[NSURL URLWithString:@"ftp://example.com/image.png"] withUser:nil];
    STAssertEqualObjects(url.absoluteString, @"ftp://example.com/image.png", nil);
    
    // Adding user into the URL
    url = [CK2CURLBasedProtocol URLByReplacingUserInfoInURL:[NSURL URLWithString:@"ftp://example.com/image.png"] withUser:@"user"];
    STAssertEqualObjects(url.absoluteString, @"ftp://user@example.com/image.png", nil);
    
    // Replacing existing user
    url = [CK2CURLBasedProtocol URLByReplacingUserInfoInURL:[NSURL URLWithString:@"ftp://test@example.com/image.png"] withUser:@"user"];
    STAssertEqualObjects(url.absoluteString, @"ftp://user@example.com/image.png", nil);
    
    // Replacing existing user + password
    url = [CK2CURLBasedProtocol URLByReplacingUserInfoInURL:[NSURL URLWithString:@"ftp://test:sekret@example.com/image.png"] withUser:@"user"];
    STAssertEqualObjects(url.absoluteString, @"ftp://user@example.com/image.png", nil);
    
    // Escaping of unusual characters
    url = [CK2CURLBasedProtocol URLByReplacingUserInfoInURL:[NSURL URLWithString:@"ftp://example.com/image.png"] withUser:@"user/:1@example.com"];
    STAssertEqualObjects(url.absoluteString, @"ftp://user%2F%3A1%40example.com@example.com/image.png", nil);
}

@end

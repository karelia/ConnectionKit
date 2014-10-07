//
//  URLAppendingTests.m
//  Connection
//
//  Created by Mike on 31/01/2013.
//
//

#import <XCTest/XCTest.h>

#import "CK2FTPProtocol.h"

@interface CK2CURLBasedProtocol (UnitTesting)
+ (NSURLRequest *)newRequestWithRequest:(NSURLRequest *)request isDirectory:(BOOL)directory;
@end


@interface URLDirectoryTests : XCTestCase
@end


@implementation URLDirectoryTests

/*  We test with all absolute FTP URL forms to make sure they don't get mangled
 */

- (void)testFileURL;
{
    NSURL *url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com//test"]]
                                                 isDirectory:NO].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com//test");
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2Ftest"]]
                                          isDirectory:NO].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2Ftest");
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2F/test"]]
                                          isDirectory:NO].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2F/test");
}

- (void)testMakingFileIntoFolder;
{
    NSURL *url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com//test"]]
                                                 isDirectory:YES].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com//test/");
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2Ftest"]]
                                          isDirectory:YES].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2Ftest/");
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2F/test"]]
                                          isDirectory:YES].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2F/test/");
    
    // This has been giving some problems where Cocoa normally recognises the %2F as a folder, I think
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2F"]]
                                          isDirectory:YES].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2F/");
}

- (void)testFolderURL;
{
    NSURL *url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com//test/"]]
                                                 isDirectory:YES].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com//test/");
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2Ftest/"]]
                                          isDirectory:YES].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2Ftest/");
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2F/test/"]]
                                          isDirectory:YES].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2F/test/");
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2F/"]]
                                          isDirectory:YES].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2F/");
}

- (void)testMakingFolderIntoFile;
{
    NSURL *url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com//test/"]]
                                                 isDirectory:NO].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com//test");
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2Ftest/"]]
                                          isDirectory:NO].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com//test");
    
    url = [CK2FTPProtocol newRequestWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/%2F/test/"]]
                                          isDirectory:NO].URL;
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com/%2F/test");
}

@end


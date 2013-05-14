//
//  URLAppendingTests.m
//  Connection
//
//  Created by Mike on 31/01/2013.
//
//

#import <SenTestingKit/SenTestingKit.h>

#import "CK2FTPProtocol.h"

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


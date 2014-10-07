//
//  URLAppendingTests.m
//  Connection
//
//  Created by Mike on 31/01/2013.
//
//

#import <XCTest/XCTest.h>

#import "CK2CURLBasedProtocol.h"

@interface URLCanonicalizationTests : XCTestCase
@end


@implementation URLCanonicalizationTests

- (void)testIncludingUser;
{    
    // Test first with no user set. e.g. anonymous login
    NSURL *url = [CK2CURLBasedProtocol URLByReplacingUserInfoInURL:[NSURL URLWithString:@"ftp://example.com/image.png"] withUser:nil];
    XCTAssertEqualObjects(url.absoluteString, @"ftp://example.com/image.png");
    
    // Adding user into the URL
    url = [CK2CURLBasedProtocol URLByReplacingUserInfoInURL:[NSURL URLWithString:@"ftp://example.com/image.png"] withUser:@"user"];
    XCTAssertEqualObjects(url.absoluteString, @"ftp://user@example.com/image.png");
    
    // Replacing existing user
    url = [CK2CURLBasedProtocol URLByReplacingUserInfoInURL:[NSURL URLWithString:@"ftp://test@example.com/image.png"] withUser:@"user"];
    XCTAssertEqualObjects(url.absoluteString, @"ftp://user@example.com/image.png");
    
    // Replacing existing user + password
    url = [CK2CURLBasedProtocol URLByReplacingUserInfoInURL:[NSURL URLWithString:@"ftp://test:sekret@example.com/image.png"] withUser:@"user"];
    XCTAssertEqualObjects(url.absoluteString, @"ftp://user@example.com/image.png");
    
    // Escaping of unusual characters
    url = [CK2CURLBasedProtocol URLByReplacingUserInfoInURL:[NSURL URLWithString:@"ftp://example.com/image.png"] withUser:@"user/:1@example.com"];
    XCTAssertEqualObjects(url.absoluteString, @"ftp://user%2F%3A1%40example.com@example.com/image.png");
}

@end

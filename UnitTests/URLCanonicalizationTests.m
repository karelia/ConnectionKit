//
//  URLAppendingTests.m
//  Connection
//
//  Created by Mike on 31/01/2013.
//
//

#import <SenTestingKit/SenTestingKit.h>

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

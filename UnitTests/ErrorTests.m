//
//  CK2FileManagerErrorTests.m
//  Connection
//
//  Created by Sam Deane on 10/04/2013.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManager.h"

#import <XCTest/XCTest.h>

@interface CK2FileManagerErrorTests : XCTestCase

@end

@implementation CK2FileManagerErrorTests

#pragma mark FTP

- (void)testUnsupportedScheme
{
    CK2FileManager* fm = [[CK2FileManager alloc] init];

    NSURL* url = [NSURL URLWithString:@"bogus://example.com"];

    [fm contentsOfDirectoryAtURL:url includingPropertiesForKeys:@[] options:NSDirectoryEnumerationSkipsHiddenFiles completionHandler:^(NSArray *contents, NSError *error) {
        XCTAssertNotNil(error, @"expecting an error");
    }];

    [fm removeItemAtURL:url completionHandler:^(NSError *error) {
        XCTAssertNotNil(error, @"expecting an error");
    }];

    [fm enumerateContentsOfURL:url includingPropertiesForKeys:@[] options:NSDirectoryEnumerationSkipsHiddenFiles usingBlock:^(NSURL *url) {
    } completionHandler:^(NSError *error) {
        XCTAssertNotNil(error, @"expecting an error");
    }];

    [fm createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:@{} completionHandler:^(NSError *error) {
        XCTAssertNotNil(error, @"expecting an error");
    }];

    [fm createFileAtURL:url contents:[NSData data] withIntermediateDirectories:YES openingAttributes:@{} progressBlock:^(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToSend) {
    } completionHandler:^(NSError *error) {
        XCTAssertNotNil(error, @"expecting an error");
    }];

    [fm createFileAtURL:url withContentsOfURL:url withIntermediateDirectories:YES openingAttributes:@{} progressBlock:^(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToSend) {
    } completionHandler:^(NSError *error) {
        XCTAssertNotNil(error, @"expecting an error");
    }];
    
    [fm release];
}

@end
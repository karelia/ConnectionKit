//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "BaseCKTests.h"
#import "KMSServer.h"

#import "CKUploader.h"

#import <XCTest/XCTest.h>
#import <curl/curl.h>


@interface CKUploaderTests : BaseCKTests<CKUploaderDelegate>

@property (strong, nonatomic) NSError* error;
@property (assign, nonatomic) BOOL finished;
@property (assign, nonatomic) BOOL uploading;
@property (assign, nonatomic) BOOL failAuthentication;

@end

@implementation CKUploaderTests

- (void)dealloc
{
    [_error release];

    [super dealloc];
}

- (CKUploader*)setupUploader
{
    CKUploader* result = nil;
    if ([self setupTest])
    {
        NSURL* url = [self URLForPath:@"/"];
        NSURLRequest* request = [NSURLRequest requestWithURL:url];
        CKUploadingOptions options = 0;
        result = [CKUploader uploaderWithRequest:request options:options delegate:self];
    }

    return result;
}

- (NSString *)protocol; { return @"WebDAV"; }

#pragma mark - Upload Delegate Methods

- (void)uploaderDidBecomeInvalid:(CKUploader *)uploader
{
    self.finished = YES;
    [self pause];
}

- (void)uploader:(CKUploader *)uploader transferRecord:(CKTransferRecord *)record didCompleteWithError:(NSError *)error;
{
    self.error = error;
}

- (void)uploader:(CKUploader *)uploader didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(CK2AuthChallengeDisposition, NSURLCredential *))completionHandler
{
    if (challenge.previousFailureCount > 0)
    {
        NSLog(@"cancelling authentication");
        completionHandler(CK2AuthChallengeCancelAuthenticationChallenge, nil);
    }

    else
    {
        NSString* user = self.failAuthentication ? @"wrong" : @"user";
        NSString* pass = self.failAuthentication ? @"wrong" : @"pass";
        NSURLCredential* credential = [NSURLCredential credentialWithUser:user password:pass persistence:NSURLCredentialPersistenceNone];
        completionHandler(CK2AuthChallengeUseCredential, credential);
    }
}

- (void)uploader:(CKUploader *)uploader didBeginUploadToPath:(NSString *)path
{
    self.uploading = YES;
    NSLog(@"uploading");
}


- (void)uploader:(CKUploader *)uploader appendString:(NSString *)string toTranscript:(CK2TranscriptType)transcript
{
    NSLog(@"%d: %@", (int)transcript, string);
}

#pragma mark - Utilities

- (void)checkResultForRecord:(CKTransferRecord*)record uploading:(BOOL)uploading
{
    if (self.failAuthentication)
    {
        XCTAssertTrue([self.error.domain isEqualToString:NSURLErrorDomain], @"unexpected error %@", self.error);
        XCTAssertTrue(self.error.code == kCFURLErrorUserCancelledAuthentication, @"unexpected error %@", self.error);
        XCTAssertTrue(self.finished, @"should be finished");
        if (record)
        {
            XCTAssertTrue([record.error.domain isEqualToString:NSURLErrorDomain], @"unexpected error %@", self.error);
            XCTAssertTrue(record.error.code == kCFURLErrorUserCancelledAuthentication, @"unexpected error %@", self.error);
        }
    }
    else
    {
        XCTAssertTrue(self.finished, @"should be finished");
        XCTAssertTrue(self.error == nil, @"unexpected error %@", self.error);
        XCTAssertNil(record.error, @"unexpected error %@", record.error);
    }
    XCTAssertTrue(self.uploading == uploading, @"uploading method %@ have been called", uploading ? @"should" : @"shouldn't");

}

#pragma mark - Tests

- (void)testUploadFile
{
    CKUploader* uploader = [self setupUploader];
    if (uploader)
    {
        NSURL* folder = [self temporaryFolder];
        NSURL* url = [folder URLByAppendingPathComponent:@"test.txt"];
        NSString* testData = @"Some test content";
        NSError* error = nil;
        BOOL ok = [testData writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error];
        XCTAssertTrue(ok, @"failed to write test file with error %@", error);

        CKTransferRecord *record = [uploader uploadToURL:[CK2FileManager URLWithPath:@"test/test.txt" relativeToURL:uploader.baseRequest.URL]
                                                fromFile:url];
        XCTAssertNotNil(record, @"got a transfer record");
        XCTAssertTrue(record.size == [[testData dataUsingEncoding:NSUTF8StringEncoding] length], @"unexpected size %ld", record.size);
        [uploader finishOperationsAndInvalidate];

        [self runUntilPaused];
        [self checkResultForRecord:record uploading:YES];
    }
}

- (void)testUploadFileNoAuthentication
{
    self.failAuthentication = YES;
    [self testUploadFile];
}

- (void)testUploadData
{
    CKUploader* uploader = [self setupUploader];
    if (uploader)
    {
        NSData* testData = [@"Some test content" dataUsingEncoding:NSUTF8StringEncoding];
        CKTransferRecord *record = [uploader uploadToURL:[CK2FileManager URLWithPath:@"test/test.txt" relativeToURL:uploader.baseRequest.URL]
                                                fromData:testData];
        XCTAssertNotNil(record, @"got a transfer record");
        XCTAssertTrue(record.size == [testData length], @"unexpected size %ld", record.size);
        [uploader finishOperationsAndInvalidate];

        [self runUntilPaused];
        [self checkResultForRecord:record uploading:YES];
    }
}

- (void)testUploadDataNoAuthentication
{
    self.failAuthentication = YES;
    [self testUploadData];
}

- (void)testRemoveFileAtPath
{
    CKUploader* uploader = [self setupUploader];
    if (uploader)
    {
        NSURL *url = [CK2FileManager URLWithPath:@"test/test.txt" relativeToURL:uploader.baseRequest.URL];
        [uploader removeItemAtURL:url completionHandler:NULL];
        [uploader finishOperationsAndInvalidate];

        [self runUntilPaused];
        [self checkResultForRecord:nil uploading:NO];
    }

}

- (void)testRemoveFileAtPathNoAuthentication
{
    self.failAuthentication = YES;
    [self testRemoveFileAtPath];
}

- (void)testCancel
{
    CKUploader* uploader = [self setupUploader];
    if (uploader)
    {
        NSData* testData = [@"Some test content" dataUsingEncoding:NSUTF8StringEncoding];
        CKTransferRecord *record = [uploader uploadToURL:[CK2FileManager URLWithPath:@"test/test.txt" relativeToURL:uploader.baseRequest.URL]
                                                fromData:testData];
        XCTAssertNotNil(record, @"got a transfer record");
        XCTAssertTrue(record.size == [testData length], @"unexpected size %ld", record.size);
        [uploader finishOperationsAndInvalidate];
        XCTAssertFalse(self.finished, @"should not be finished");
        [uploader invalidateAndCancel];
        [self runUntilPaused];
    }
}

@end

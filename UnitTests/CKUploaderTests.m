//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerBaseTests.h"
#import "KMSServer.h"

#import "CKUploader.h"

#import <SenTestingKit/SenTestingKit.h>
#import <curl/curl.h>


@interface CKUploaderTests : CK2FileManagerBaseTests<CKUploaderDelegate>

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

- (BOOL)setup
{
    BOOL result = ([self setupSessionWithResponses:@"webdav"]);

    return result;
}

- (CKUploader*)setupUploader
{
    CKUploader* result = nil;
    if ([self setup])
    {
        NSURL* url = [self URLForPath:@"/"];
        NSURLRequest* request = [NSURLRequest requestWithURL:url];
        NSNumber* permissions = nil;
        CKUploadingOptions options = 0;
        result = [CKUploader uploaderWithRequest:request filePosixPermissions:permissions options:options];
        result.delegate = self;
    }

    return result;
}

#pragma mark - Upload Delegate Methods

- (void)uploaderDidFinishUploading:(CKUploader *)uploader
{
    self.finished = YES;
    [self pause];
}

- (void)uploader:(CKUploader *)uploader didFailWithError:(NSError *)error
{
    self.error = error;
    [self pause];
}


- (void)uploader:(CKUploader *)uploader didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge.previousFailureCount > 0)
    {
        NSLog(@"cancelling authentication");
        [challenge.sender cancelAuthenticationChallenge:challenge];
    }

    else
    {
        NSString* user = self.failAuthentication ? @"wrong" : @"user";
        NSString* pass = self.failAuthentication ? @"wrong" : @"pass";
        NSURLCredential* credential = [NSURLCredential credentialWithUser:user password:pass persistence:NSURLCredentialPersistenceNone];
        [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
    }
}

- (void)uploader:(CKUploader *)uploader didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [self pause];
}


- (void)uploader:(CKUploader *)uploader didBeginUploadToPath:(NSString *)path
{
    self.uploading = YES;
    NSLog(@"uploading");
}


- (void)uploader:(CKUploader *)uploader appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript
{
    NSLog(@"%d: %@", transcript, string);
}

#pragma mark - Utilities

- (void)checkResultForRecord:(CKTransferRecord*)record uploading:(BOOL)uploading
{
    if (self.failAuthentication)
    {
        STAssertTrue([self.error.domain isEqualToString:NSURLErrorDomain], @"unexpected error %@", self.error);
        STAssertTrue(self.error.code == kCFURLErrorUserCancelledAuthentication, @"unexpected error %@", self.error);
        STAssertFalse(self.finished, @"shouldn't be finished");
        if (record)
        {
            STAssertTrue([record.error.domain isEqualToString:NSURLErrorDomain], @"unexpected error %@", self.error);
            STAssertTrue(record.error.code == kCFURLErrorUserCancelledAuthentication, @"unexpected error %@", self.error);
        }
    }
    else
    {
        STAssertTrue(self.finished, @"should be finished");
        STAssertTrue(self.error == nil, @"unexpected error %@", self.error);
        STAssertFalse([record hasError], @"unexpected error %@", record.error);
    }
    STAssertTrue(self.uploading == uploading, @"uploading method %@ have been called", uploading ? @"should" : @"shouldn't");

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
        STAssertTrue(ok, @"failed to write test file with error %@", error);

        CKTransferRecord *record = [uploader uploadFileAtURL:url toPath:@"test/test.txt"];
        STAssertNotNil(record, @"got a transfer record");
        STAssertTrue(record.size == [[testData dataUsingEncoding:NSUTF8StringEncoding] length], @"unexpected size %ld", record.size);
        [uploader finishUploading];

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
        CKTransferRecord *record = [uploader uploadData:testData toPath:@"test/test.txt"];
        STAssertNotNil(record, @"got a transfer record");
        STAssertTrue(record.size == [testData length], @"unexpected size %ld", record.size);
        [uploader finishUploading];

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
        [uploader removeFileAtPath:@"test/test.txt"];
        [uploader finishUploading];

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
        CKTransferRecord *record = [uploader uploadData:testData toPath:@"test/test.txt"];
        STAssertNotNil(record, @"got a transfer record");
        STAssertTrue(record.size == [testData length], @"unexpected size %ld", record.size);
        [uploader finishUploading];
        STAssertFalse(self.finished, @"should not be finished");
        [uploader cancel];
    }
}

- (void)testPosixPermissionsForPath
{
    CKUploader* uploader = [self setupUploader];
    if (uploader)
    {
        unsigned long filePerms = [uploader posixPermissionsForPath:@"test/test.txt" isDirectory:NO];
        unsigned long dirPerms = [uploader posixPermissionsForPath:@"test/" isDirectory:YES];

        STAssertTrue(filePerms == 0644, @"unexpected default file perms %lo", filePerms);
        STAssertTrue(dirPerms == 0755, @"unexpected default dir perms %lo", dirPerms);
    }
}

- (void)testPosixPermissionsForDirectoryFromFilePermissions
{
    unsigned long dirPerms = [CKUploader posixPermissionsForDirectoryFromFilePermissions:0644];
    STAssertTrue(dirPerms == 0755, @"unexpected default dir perms %lo", dirPerms);
}

@end

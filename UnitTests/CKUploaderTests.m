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

@end

@implementation CKUploaderTests

- (void)dealloc
{
    [_error release];

    [super dealloc];
}

- (BOOL)setup
{
    BOOL result = ([self setupSessionWithRealURL:[NSURL URLWithString:@"http://dav.test.com"] fakeResponses:@"webdav"]);

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
    [self pause];
}

- (void)uploader:(CKUploader *)uploader didFailWithError:(NSError *)error
{
    self.error = error;
    [self pause];
}


- (void)uploader:(CKUploader *)uploader didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSURLCredential* credential = [NSURLCredential credentialWithUser:@"user" password:@"pass" persistence:NSURLCredentialPersistenceNone];
    [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
}

- (void)uploader:(CKUploader *)uploader didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [self pause];
}


- (void)uploader:(CKUploader *)uploader didBeginUploadToPath:(NSString *)path
{
    NSLog(@"uploading");
}


- (void)uploader:(CKUploader *)uploader appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript
{
    NSLog(@"%d: %@", transcript, string);
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

        STAssertTrue(self.error == nil, @"unexpected error %@", error);
        STAssertFalse([record hasError], @"unexpected error %@", record.error);
    }
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

        STAssertTrue(self.error == nil, @"unexpected error %@", self.error);
        STAssertFalse([record hasError], @"unexpected error %@", record.error);
    }
}

- (void)testRemoteFileAtPath
{
    CKUploader* uploader = [self setupUploader];
    if (uploader)
    {
        [uploader removeFileAtPath:@"test/test.txt"];
        [uploader finishUploading];

        [self runUntilPaused];

        STAssertTrue(self.error == nil, @"unexpected error %@", self.error);
    }

}

- (void)testFinishUploading
{

}

- (void)testCancel
{

}

@end

#if 0 // STUFF TO TEST

- (CKTransferRecord *)uploadFileAtURL:(NSURL *)url toPath:(NSString *)path;
- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path;
- (void)removeFileAtPath:(NSString *)path;

@property (nonatomic, retain, readonly) CKTransferRecord *rootTransferRecord;
@property (nonatomic, retain, readonly) CKTransferRecord *baseTransferRecord;

- (void)finishUploading;    // will disconnect once all files are uploaded
- (void)cancel;             // bails out as quickly as possible

// The permissions given to uploaded files
- (unsigned long)posixPermissionsForPath:(NSString *)path isDirectory:(BOOL)directory;
+ (unsigned long)posixPermissionsForDirectoryFromFilePermissions:(unsigned long)filePermissions;

@end
#endif

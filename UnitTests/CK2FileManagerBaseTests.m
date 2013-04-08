//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerBaseTests.h"
#import "CK2Authentication.h"

#import "CK2FileManagerWithTestSupport.h"
#import <DAVKit/DAVKit.h>

static const BOOL kMakeRemoveTestFilesOnMockServer = YES;

@interface TestFileDelegate : CK2FileManager<CK2FileManagerDelegate>

@property (strong, nonatomic) CK2FileManagerBaseTests* tests;

@end

/**
 This delegate is used instead of the test itself for operations which are either creating or
 removing the test files and folders on the server.

 This helps to prevent those operations from interfering with the state of the actual tests themselves.
 */

@implementation TestFileDelegate

//#define LogHousekeeping NSLog // macro to use for logging "housekeeping" output - ie stuff related to making/removing test files, rather than the tests themselves
#define LogHousekeeping(...)

+ (TestFileDelegate*)delegateWithTest:(CK2FileManagerBaseTests*)tests
{
    TestFileDelegate* result = [[TestFileDelegate alloc] init];
    result.tests = tests;

    return [result autorelease];
}

- (void)fileManager:(CK2FileManager *)manager didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge.previousFailureCount > 0)
    {
        [challenge.sender cancelAuthenticationChallenge:challenge];
    }
    else
    {

        NSURLCredential* credential;
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:CK2AuthenticationMethodHostFingerprint])
        {
            credential = [NSURLCredential ck2_credentialForKnownHostWithPersistence:NSURLCredentialPersistenceNone];
        }
        else
        {
            credential = [NSURLCredential credentialWithUser:self.tests.user password:self.tests.password persistence:NSURLCredentialPersistenceNone];
        }
        [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
    }

}

- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CKTranscriptType)transcriptType
{
    switch (transcriptType)
    {
        case CKTranscriptReceived:
        case CKTranscriptSent:
            LogHousekeeping(@"housekeeping %d: %@", transcriptType, info);
            break;

        default:
            break;
    }
}

@end


@implementation CK2FileManagerBaseTests

- (void)dealloc
{
    [_session release];
    [_transcript release];
    [_type release];
    
    [super dealloc];
}


- (NSURL*)temporaryFolder
{
    NSString* type = self.type ?: @"CK2FileTest";
    NSURL* result = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@Tests", type]];
    NSError* error = nil;
    BOOL ok = [[NSFileManager defaultManager] createDirectoryAtURL:result withIntermediateDirectories:YES attributes:nil error:&error];
    STAssertTrue(ok, @"failed to make temporary folder with error %@", error);

    return result;
}

- (void)removeTemporaryFolder
{
    NSError* error = nil;
    NSURL* tempFolder = [self temporaryFolder];
    NSFileManager* fm = [NSFileManager defaultManager];
    [fm removeItemAtURL:tempFolder error:&error];
}

- (BOOL)makeTemporaryFolder
{
    NSError* error = nil;
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* tempFolder = [self temporaryFolder];
    BOOL ok = [fm createDirectoryAtURL:tempFolder withIntermediateDirectories:YES attributes:nil error:&error];
    STAssertTrue(ok, @"couldn't make temporary directory: %@", error);

    return ok;
}

- (BOOL)setupSession
{
    CK2FileManagerWithTestSupport* fm = [[CK2FileManagerWithTestSupport alloc] init];
    fm.dontShareConnections = YES;
    fm.delegate = self;
    self.session = fm;
    self.transcript = [[[NSMutableString alloc] init] autorelease];
    [fm release];

    return self.session != nil;
}

- (BOOL)setupSessionWithResponses:(NSString*)responses;
{
    NSLog(@"==SETUP=============================================================");
    if ([responses isEqualToString:@"webdav"])
    {
        self.type = @"CKWebDAVTest";
    }
    else if ([responses isEqualToString:@"ftp"])
    {
        self.type = @"CKFTPTest";
    }
    else if ([responses isEqualToString:@"sftp"])
    {
        self.type = @"CKSFTPTest";
    }
    else
    {
        self.type = nil;
    }

    NSString* name = [[[self.name substringToIndex:[self.name length] - 1] componentsSeparatedByString:@" "] objectAtIndex:1];
    self.extendedName = [NSString stringWithFormat:@"%@Using%@", name, [responses uppercaseString]];

    NSString* setting = nil;
    if (self.type)
    {
        NSString* key = [NSString stringWithFormat:@"%@URL", self.type];
        setting = [[NSUserDefaults standardUserDefaults] objectForKey:key];
        STAssertNotNil(setting, @"You need to set a test server address for %@ tests. Use the defaults command on the command line: defaults write otest %@ \"server-url-here\". Use \"MockServer\" instead of a url to use a mock server instead. Use \"Off\" instead of a url to disable %@ tests", responses, key, key, responses);
    }

    BOOL ok;
    if (!setting || [setting isEqualToString:@"Off"])
    {
        NSLog(@"Tests turned off for %@", responses);
        ok = NO;
    }
    else if ([setting isEqualToString:@"MockServer"])
    {
        NSLog(@"Tests using MockServer for %@", responses);
        self.useMockServer = YES;
        ok = [super setupServerWithResponseFileNamed:responses];
    }
    else
    {
        NSURL* url = [NSURL URLWithString:setting];
        NSLog(@"Tests using server %@ for %@", url, responses);
        self.user = url.user;
        self.password = url.password;
        self.url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@", url.scheme, url.host, url.path]];
        ok = YES;
    }

    if (ok)
    {
        self.originalUser = self.user;
        self.originalPassword = self.password;

        [self setupSession];
        ok = self.session != nil;
    }

    if (ok)
    {
        NSLog(@"Tests setup for %@, user: %@, password:%@ url:%@", responses, self.user, self.password, self.url);
    }
    else
    {
        NSLog(@"Tests not setup for %@", responses);
    }

    NSLog(@"====================================================================");

    return ok;
}

- (void)useResponseSet:(NSString*)name
{
    if (self.useMockServer)
    {
        [super useResponseSet:name];
    }
}

#pragma mark - Delegate
- (void)fileManager:(CK2FileManager *)manager didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSString *authMethod = [[challenge protectionSpace] authenticationMethod];
    if (challenge.previousFailureCount > 0)
    {
        NSLog(@"cancelling authentication");
        [challenge.sender cancelAuthenticationChallenge:challenge];
    }
    else
    {

        if ([authMethod isEqualToString:NSURLAuthenticationMethodDefault] ||
            [authMethod isEqualToString:NSURLAuthenticationMethodHTTPDigest] ||
            [authMethod isEqualToString:NSURLAuthenticationMethodHTMLForm] ||
            [authMethod isEqualToString:NSURLAuthenticationMethodNTLM] ||
            [authMethod isEqualToString:NSURLAuthenticationMethodNegotiate])
        {
            NSLog(@"authenticating as %@ %@", self.user, self.password);
            NSURLCredential* credential = [NSURLCredential credentialWithUser:self.user password:self.password persistence:NSURLCredentialPersistenceNone];
            [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
        }
        else if ([authMethod isEqualToString:CK2AuthenticationMethodHostFingerprint])
        {
            NSLog(@"checking fingerprint");
            NSURLCredential* credential = [NSURLCredential ck2_credentialForKnownHostWithPersistence:NSURLCredentialPersistenceNone];
            [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
        }
        else
        {
            NSLog(@"performing default authentication");
            [[challenge sender] performDefaultHandlingForAuthenticationChallenge:challenge];
        }
    }

}

- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CKTranscriptType)transcriptType
{
    NSString* prefix;
    switch (transcriptType)
    {
        case CKTranscriptSent:
            prefix = @"-->";
            break;

        case CKTranscriptReceived:
            prefix = @"<--";
            break;

        case CKTranscriptData:
            prefix = @"(d)";
            break;

        case CKTranscriptInfo:
            prefix = @"(i)";
            break;

        default:
            prefix = @"(?)";
    }

    @synchronized(self.transcript)
    {
        [self.transcript appendFormat:@"%@ %@\n", prefix, info];
    }
}

- (NSURL*)URLForPath:(NSString*)path
{
    NSURL* url = [CK2FileManager URLWithPath:path relativeToURL:self.url];
    return [url absoluteURL];   // account for relative URLs
}


- (void)runUntilPaused
{
    if (self.useMockServer)
    {
        [super runUntilPaused];
    }
    else
    {
        while (self.state != KMSPauseRequested)
        {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
            }
        }
        self.state = KMSPaused;
    }
}

- (void)pause
{
    if (self.useMockServer)
    {
        [super pause];
    }
    else
    {
        self.state = KMSPauseRequested;
    }
}

- (void)setUp
{
    [self removeTemporaryFolder];
    [self makeTemporaryFolder];
}

- (void)tearDown
{
    [super tearDown];
    NSLog(@"\n\nSession transcript:\n%@\n\n", self.transcript);
    [self removeTemporaryFolder];
}

#pragma mark - Test File Support

- (NSURL*)URLForTestFolder
{
    return [self URLForPath:[@"CK2FileManagerTests" stringByAppendingPathComponent:self.extendedName]];
}

- (NSURL*)URLForTestFile1
{
    return [[self URLForTestFolder] URLByAppendingPathComponent:@"file1.txt"];
}

- (NSURL*)URLForTestFile2
{
    return [[self URLForTestFolder] URLByAppendingPathComponent:@"file2.txt"];
}

- (void)makeTestDirectoryWithFiles:(BOOL)withFiles
{
    // we do report errors from here, since something going wrong is likely to affect the result of the test that called us

    if (kMakeRemoveTestFilesOnMockServer || !self.useMockServer)
    {
        // if we don't want the test files, remove everything first
        if (!withFiles)
        {
            [self removeTestDirectory];
        }

        NSLog(@"<<<< Making Test Directory");

        CK2FileManagerWithTestSupport* session = [[CK2FileManagerWithTestSupport alloc] init];
        session.dontShareConnections = YES;
        session.delegate = [TestFileDelegate delegateWithTest:self];

        // make the folder if necessary
        NSURL* url = [self URLForTestFolder];
        [session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertTrue([self checkNoErrorOrFileExistsError:error], @"expected no error or file exists error, got %@", error);

            // if we want the files, make them too
            if (withFiles)
            {
                NSData* contents = [@"This is a test file" dataUsingEncoding:NSUTF8StringEncoding];
                [session createFileAtURL:[self URLForTestFile1] contents:contents withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
                    STAssertTrue([self checkNoErrorOrFileExistsError:error], @"expected no error or file exists error, got %@", error);
                    [session createFileAtURL:[self URLForTestFile2] contents:contents withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
                        STAssertTrue([self checkNoErrorOrFileExistsError:error], @"expected no error or file exists error, got %@", error);
                        [self pause];
                        NSLog(@"<<<< Made Test Files");
                    }];
                }];
            }
            else
            {
                [self pause];
            }
            NSLog(@"<<<< Made Test Directory");
        }];

        [self runUntilPaused];

        [session release];
    }
}

- (void)removeTestDirectory
{
    if (kMakeRemoveTestFilesOnMockServer || !self.useMockServer)
    {
        NSLog(@"<<<< Removing Test Files");
        CK2FileManagerWithTestSupport* session = [[CK2FileManagerWithTestSupport alloc] init];
        session.dontShareConnections = YES;
        session.delegate = [TestFileDelegate delegateWithTest:self];

        // we don't care about errors here, we just want to do our best to clean up after any tests
        [session removeItemAtURL:[self URLForTestFile2] completionHandler:^(NSError *error) {
            if (error) LogHousekeeping(@"housekeeping error : %@", error);
            [session removeItemAtURL:[self URLForTestFile1] completionHandler:^(NSError *error) {
                if (error) LogHousekeeping(@"housekeeping error : %@", error);
                [session removeItemAtURL:[self URLForTestFolder] completionHandler:^(NSError *error) {
                    if (error) LogHousekeeping(@"housekeeping error : %@", error);
                    [self pause];

                    NSLog(@"<<<< Removed Test Files");
                }];
            }];
        }];
        
        [self runUntilPaused];
        [session release];
    }
}

#pragma mark - Error Checking Helpers

- (void)logError:(NSError*)error mustHaveError:(BOOL)mustHaveError domainOK:(BOOL)domainOK codeOK:(BOOL)codeOK
{
    if (!error && mustHaveError)
    {
        NSLog(@"expecting error, got none");
    }
    else if (!domainOK && error)
    {
        NSLog(@"unexpected error domain %@", error.domain);
    }
    else if (!codeOK && error)
    {
        NSLog(@"unexpected error code %ld", error.code);
    }
}

- (BOOL)checkIsAuthenticationError:(NSError*)error
{
    BOOL domainOK = [error.domain isEqualToString:NSURLErrorDomain];
    BOOL codeOK = error.code == NSURLErrorUserAuthenticationRequired || error.code == NSURLErrorUserCancelledAuthentication;
    BOOL result = domainOK && codeOK;

    return result;
}

- (BOOL)checkNoErrorOrFileExistsError:(NSError*)error
{
    BOOL domainOK = [error.domain isEqualToString:NSCocoaErrorDomain];
    BOOL codeOK = error.code == NSFileWriteUnknownError;
    [self logError:error mustHaveError:NO domainOK:domainOK codeOK:codeOK];

    return error == nil || (domainOK && codeOK);
}

- (BOOL)checkIsFileCantWriteError:(NSError*)error
{
    BOOL domainOK = [error.domain isEqualToString:NSCocoaErrorDomain];
    BOOL codeOK = error.code == NSFileWriteUnknownError;
    [self logError:error mustHaveError:YES domainOK:domainOK codeOK:codeOK];

    return (error != nil) && domainOK && codeOK;
}

- (BOOL)checkNoErrorOrIsFileCantWriteError:(NSError*)error
{
    BOOL domainOK = [error.domain isEqualToString:NSCocoaErrorDomain];
    BOOL codeOK = error.code == NSFileWriteUnknownError;
    [self logError:error mustHaveError:NO domainOK:domainOK codeOK:codeOK];

    return (error == nil) || (domainOK && codeOK);
}

- (BOOL)checkIsFileNotFoundError:(NSError*)error
{
    BOOL domainOK = [error.domain isEqualToString:NSURLErrorDomain];
    BOOL codeOK = error.code == NSURLErrorNoPermissionsToReadFile;
    [self logError:error mustHaveError:YES domainOK:domainOK codeOK:codeOK];

    return (error != nil) && domainOK && codeOK;
}

- (BOOL)checkNoErrorOrIsFileNotFoundError:(NSError*)error
{
    BOOL domainOK = [error.domain isEqualToString:NSURLErrorDomain];
    BOOL codeOK = error.code == NSURLErrorNoPermissionsToReadFile;
    [self logError:error mustHaveError:NO domainOK:domainOK codeOK:codeOK];

    return (error == nil) || (domainOK && codeOK);
}

@end
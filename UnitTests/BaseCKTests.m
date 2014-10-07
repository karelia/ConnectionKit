//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "BaseCKTests.h"
#import "CK2Authentication.h"

#import "CK2FileManagerWithTestSupport.h"
#import "KMSServer.h"

static const BOOL kMakeRemoveTestFilesOnMockServer = YES;

@interface TestFileDelegate : CK2FileManager<CK2FileManagerDelegate>

@property (strong, nonatomic) BaseCKTests* tests;

@end

/**
 This delegate is used instead of the test itself for operations which are either creating or
 removing the test files and folders on the server.

 This helps to prevent those operations from interfering with the state of the actual tests themselves.
 */

@implementation TestFileDelegate

//#define LogHousekeeping NSLog // macro to use for logging "housekeeping" output - ie stuff related to making/removing test files, rather than the tests themselves
#define LogHousekeeping(...)

+ (TestFileDelegate*)delegateWithTest:(BaseCKTests*)tests
{
    TestFileDelegate* result = [[TestFileDelegate alloc] init];
    result.tests = tests;

    return [result autorelease];
}

- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(CK2AuthChallengeDisposition, NSURLCredential *))completionHandler;
{
    if (challenge.previousFailureCount > 0)
    {
        completionHandler(CK2AuthChallengeCancelAuthenticationChallenge, nil);
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
        completionHandler(CK2AuthChallengeUseCredential, credential);
    }

}

- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CK2TranscriptType)transcriptType
{
    switch (transcriptType)
    {
        case CK2TranscriptHeaderIn:
        case CK2TranscriptHeaderOut:
            LogHousekeeping(@"housekeeping %d: %@", transcriptType, info);
            break;

        default:
            break;
    }
}

@end


@implementation BaseCKTests

- (void)dealloc
{
    [_manager release];
    [_originalPassword release];
    [_originalUser release];
    [_transcript release];
    
    [super dealloc];
}


- (NSURL*)temporaryFolder
{
    NSURL* result = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@Tests", self.protocol]];
    NSError* error = nil;
    BOOL ok = [[NSFileManager defaultManager] createDirectoryAtURL:result withIntermediateDirectories:YES attributes:nil error:&error];
    XCTAssertTrue(ok, @"failed to make temporary folder with error %@", error);

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
    XCTAssertTrue(ok, @"couldn't make temporary directory: %@", error);

    return ok;
}

- (BOOL)setupManager
{
    CK2FileManagerWithTestSupport* fm = [[CK2FileManagerWithTestSupport alloc] init];
    fm.dontShareConnections = YES;
    fm.delegate = self;
    self.manager = fm;
    self.transcript = [[[NSMutableString alloc] init] autorelease];
    [fm release];

    return self.manager != nil;
}

- (BOOL)isSetup
{
    return self.manager != nil;
}

- (NSString*)protocol
{
    return @"Unknown";
}

- (BOOL)protocolUsesAuthentication
{
    return NO;
}

- (BOOL)usingProtocol:(NSString*)type
{
    return [[self.protocol lowercaseString] isEqualToString:type];
}

- (BOOL)usingMockServerWithProtocol:(NSString*)type
{
    return self.useMockServer && [self usingProtocol:type];
}

- (void)useBadLogin
{
    self.user = @"bad";
    [self useResponseSet:@"bad login"];
}


- (NSData*)mockServerDirectoryListingData
{
    return nil;
}


- (BOOL)setupFromSettings
{
    NSString* setting = nil;
    NSString* protocol = self.protocol;
    
    if (protocol)
    {
        NSString* key = [NSString stringWithFormat:@"CK%@TestURL", protocol];
        setting = [[NSUserDefaults standardUserDefaults] objectForKey:key];
        XCTAssertNotNil(setting, @"You need to set a test server address for %@ tests. Use the defaults command on the command line: defaults write otest %@ \"server-url-here\". Use \"MockServer\" instead of a url to use a mock server instead. Use \"Off\" instead of a url to disable %@ tests", protocol, key, key, protocol);
    }

    BOOL ok;
    if (!setting || [setting isEqualToString:@"Off"])
    {
        NSLog(@"Tests turned off for %@", protocol);
        ok = NO;
    }
    else if ([setting isEqualToString:@"MockServer"])
    {
        NSLog(@"Tests using MockServer for %@", protocol);
        self.useMockServer = YES;
        ok = [super setupServerWithResponseFileNamed:[self.protocol lowercaseString]];
        [KMSServer setLoggingLevel:KMSLoggingOff];
    }
    else
    {
        NSURL* url = [NSURL URLWithString:setting];
        self.user = url.user;
        self.password = url.password;
        self.url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@/", url.scheme, url.host, url.path]];
        ok = YES;
    }

    return ok;
}

- (NSString*)testName
{
    NSString* name = [[[self.name substringToIndex:[self.name length] - 1] componentsSeparatedByString:@" "] objectAtIndex:1];
    return name;
}

- (BOOL)setupTest
{
    BOOL ok = [self setupFromSettings];
    if (ok)
    {
        self.originalUser = self.user;
        self.originalPassword = self.password;

        [self setupManager];
        ok = self.manager != nil;
    }

    if (ok)
    {
        NSLog(@"Tests setup for %@, user:%@, password:%@ url:%@", self.protocol, self.user, self.password, self.url);
    }
    else
    {
        NSLog(@"Tests not setup for %@", self.protocol);
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

- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(CK2AuthChallengeDisposition, NSURLCredential *))completionHandler
{
    NSString *authMethod = [[challenge protectionSpace] authenticationMethod];
    if (challenge.previousFailureCount > 0)
    {
        NSLog(@"cancelling authentication");
        completionHandler(CK2AuthChallengeCancelAuthenticationChallenge, nil);
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
            completionHandler(CK2AuthChallengeUseCredential, credential);
        }
        else if ([authMethod isEqualToString:CK2AuthenticationMethodHostFingerprint])
        {
            NSLog(@"checking fingerprint");
            NSURLCredential* credential = [NSURLCredential ck2_credentialForKnownHostWithPersistence:NSURLCredentialPersistenceNone];
            completionHandler(CK2AuthChallengeUseCredential, credential);
        }
        else
        {
            NSLog(@"performing default authentication");
            completionHandler(CK2AuthChallengePerformDefaultHandling, nil);
        }
    }

}

- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CK2TranscriptType)transcriptType
{
    NSString* prefix;
    switch (transcriptType)
    {
        case CK2TranscriptHeaderOut:
            prefix = @"-->";
            break;

        case CK2TranscriptHeaderIn:
            prefix = @"<--";
            break;

        /*case CKTranscriptData:
            prefix = @"(d)";
            break;
         */
        case CK2TranscriptText:
            prefix = @"(i)";
            break;

        default:
            prefix = @"(?)";
    }

    @synchronized(self.transcript)
    {
        [self.transcript appendFormat:@"%@ %@", prefix, info];
        UniChar lastChar = [info characterAtIndex:[info length] - 1];
        if ((lastChar != '\n') && (lastChar != '\r'))
            [self.transcript appendString:@"\n"];
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
    if ([self.transcript length] > 0)
    {
        NSLog(@"\n\nSession transcript:\n%@\n\n", self.transcript);
    }
    [self removeTemporaryFolder];
}

#pragma mark - Test File Support

- (NSURL*)URLForTestFolder
{
    return [self URLForPath:[[@"CK2FileManagerTests" stringByAppendingPathComponent:self.protocol] stringByAppendingPathComponent:[self testName]]];
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

        LogHousekeeping(@"<<<< Making Test Directory");

        CK2FileManagerWithTestSupport* session = [[CK2FileManagerWithTestSupport alloc] init];
        session.dontShareConnections = YES;
        session.delegate = [TestFileDelegate delegateWithTest:self];

        // make the folder if necessary
        NSURL* url = [self URLForTestFolder];
        [session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            XCTAssertTrue([self checkIsCreationError:error nilAllowed:YES], @"expected no error or file exists error, got %@", error);

            // if we want the files, make them too
            if (withFiles)
            {
                NSData* contents = [@"This is a test file" dataUsingEncoding:NSUTF8StringEncoding];
                [session createFileAtURL:[self URLForTestFile1] contents:contents withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
                    XCTAssertTrue([self checkIsCreationError:error nilAllowed:YES], @"expected no error or file exists error, got %@", error);
                    [session createFileAtURL:[self URLForTestFile2] contents:contents withIntermediateDirectories:YES openingAttributes:nil progressBlock:nil completionHandler:^(NSError *error) {
                        XCTAssertTrue([self checkIsCreationError:error nilAllowed:YES], @"expected no error or file exists error, got %@", error);
                        [self pause];
                        LogHousekeeping(@"<<<< Made Test Files");
                    }];
                }];
            }
            else
            {
                [self pause];
            }
            LogHousekeeping(@"<<<< Made Test Directory");
        }];

        [self runUntilPaused];

        [session release];
    }
}

- (void)removeTestDirectory
{
    if (kMakeRemoveTestFilesOnMockServer || !self.useMockServer)
    {
        LogHousekeeping(@"<<<< Removing Test Files");
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

                    LogHousekeeping(@"<<<< Removed Test Files");
                }];
            }];
        }];
        
        [self runUntilPaused];
        [session release];
    }
}

#pragma mark - Checking Helpers

- (void)checkURL:(NSURL*)url isNamed:(NSString*)name
{
    XCTAssertTrue([[url lastPathComponent] isEqualToString:name], @"URL %@ name was wrong, expected %@", url, name);
}

- (void)checkURLs:(NSMutableArray*)urls containItemNamed:(NSString*)name
{
    BOOL found = NO;
    NSUInteger count = [urls count];
    for (NSUInteger n = 0; n < count; ++n)
    {
        NSURL* url = urls[n];
        if ([[url lastPathComponent] isEqualToString:name])
        {
            [urls removeObjectAtIndex:n];
            found = YES;
            break;
        }
    }

    XCTAssertTrue(found, @"unexpected item with name %@", name);
}

- (BOOL)checkIsAuthenticationError:(NSError*)error log:(BOOL)log
{
    BOOL domainOK = [error.domain isEqualToString:NSURLErrorDomain];
    BOOL codeOK = error.code == NSURLErrorUserAuthenticationRequired || error.code == NSURLErrorUserCancelledAuthentication;
    BOOL result = domainOK && codeOK;
    if (log && !result)
    {
        NSLog(@"expecting authentication error, got %@", error);
    }

    return result;
}

- (BOOL)checkIsAuthenticationError:(NSError*)error
{
    return [self checkIsAuthenticationError:error log:YES];
}

- (BOOL)checkIsFileCantWriteError:(NSError*)error log:(BOOL)log
{
    BOOL domainOK = [error.domain isEqualToString:NSCocoaErrorDomain];
    BOOL codeOK = error.code == NSFileWriteUnknownError;
    BOOL result = domainOK && codeOK;
    if (log && !result)
    {
        NSLog(@"expecting cant write error, got %@", error);
    }

    return result;
}

- (BOOL)checkIsFileCantReadError:(NSError*)error log:(BOOL)log
{
    BOOL domainOK = [error.domain isEqualToString:NSCocoaErrorDomain];
    BOOL codeOK = error.code == NSFileReadUnknownError;
    BOOL result = domainOK && codeOK;
    if (log && !result)
    {
        NSLog(@"expecting file not found error, got %@", error);
    }

    return result;
}


- (BOOL)checkIsFileNotFoundError:(NSError*)error log:(BOOL)log
{
    BOOL domainOK = [error.domain isEqualToString:NSCocoaErrorDomain];
    BOOL codeOK = error.code == NSFileNoSuchFileError;
    BOOL result = domainOK && codeOK;
    if (log && !result)
    {
        NSLog(@"expecting file not found error, got %@", error);
    }

    return result;
}

- (BOOL)checkIsFileExistsError:(NSError*)error log:(BOOL)log
{
    BOOL domainOK = [error.domain isEqualToString:NSCocoaErrorDomain];
    BOOL codeOK = error.code == NSFileWriteFileExistsError;
    BOOL result = domainOK && codeOK;
    if (log && !result)
    {
        NSLog(@"expecting file exists error, got %@", error);
    }

    return result;
}


- (BOOL)checkIsRemovalError:(NSError*)error nilAllowed:(BOOL)nilAllowed
{
    BOOL result = nilAllowed && error == nil;
    if (!result)
    {
        result = [self checkIsFileNotFoundError:error log:NO]; // file wasn't there?
    }
    
    if (!result)
    {
        result = [self checkIsFileCantWriteError:error log:NO]; // file was there but locked - or protocol is bad at reporting file not found
    }

    if (!result)
    {
        result = [self checkIsFileCantReadError:error log:NO]; // file wasn't there, but protocol isn't good a reporting it?
    }

    if (!result)
    {
        NSLog(@"expecting file not found or can't read or write errors, got %@", error);
    }

    return result;
}

- (BOOL)checkIsCreationError:(NSError*)error nilAllowed:(BOOL)nilAllowed
{
    BOOL result = nilAllowed && error == nil;
    if (!result)
    {
        result = [self checkIsFileExistsError:error log:NO];
    }
    
    if (!result)
    {
        result = [self checkIsFileCantWriteError:error log:NO];
    }

    if (!result)
    {
        NSLog(@"expecting file exists or can't write errors, got %@", error);
    }
    
    return result;
}

- (BOOL)checkIsUpdateError:(NSError*)error nilAllowed:(BOOL)nilAllowed
{
    BOOL result = nilAllowed && error == nil;
    if (!result)
    {
        result = [self checkIsFileNotFoundError:error log:NO];
    }
    if (!result)
    {
        result = [self checkIsFileCantWriteError:error log:NO];
    }

    if (!result)
    {
        NSLog(@"expecting file not found or file can't write error, got %@", error);
    }
    
    return result;
}

- (BOOL)checkIsMissingError:(NSError*)error nilAllowed:(BOOL)nilAllowed
{
    BOOL result = nilAllowed && error == nil;
    if (!result)
    {
        result = [self checkIsFileNotFoundError:error log:NO];
    }

    if (!result)
    {
        result = [self checkIsFileCantReadError:error log:NO];
    }

    if (!result)
    {
        NSLog(@"expecting file not found or file can't read errors, got %@", error);
    }

    return result;
}


@end
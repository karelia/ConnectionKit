//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerBaseTests.h"

#import "CK2FileManager.h"
#import <DAVKit/DAVKit.h>

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
    NSURL* result = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@Tests", self.type]];
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
    self.session = [[CK2FileManager alloc] init];
    self.session.delegate = self;
    self.transcript = [[[NSMutableString alloc] init] autorelease];
    return self.session != nil;
}

- (BOOL)setupSessionWithResponses:(NSString*)responses;
{
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
        ok = NO;
    }
    else if ([setting isEqualToString:@"MockServer"])
    {
        self.useMockServer = YES;
        ok = [super setupServerWithResponseFileNamed:responses];
    }
    else
    {
        NSURL* url = [NSURL URLWithString:setting];
        self.user = url.user;
        self.password = url.password;
        self.url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@", url.scheme, url.host, url.path]];
        ok = YES;
    }

    if (ok)
    {
        [self setupSession];
        ok = self.session != nil;
    }

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
    if (challenge.previousFailureCount > 0)
    {
        NSLog(@"cancelling authentication");
        [challenge.sender cancelAuthenticationChallenge:challenge];
    }
    else
    {
        NSString *authMethod = [[challenge protectionSpace] authenticationMethod];
        
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
        else
        {
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

@end
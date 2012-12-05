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

    [super dealloc];
}

- (BOOL)setupSession
{
    self.session = [[CK2FileManager alloc] init];
    self.session.delegate = self;
    return self.session != nil;
}

- (BOOL)setupSessionWithRealURL:(NSURL*)realURL fakeResponses:(NSString*)responsesFile;
{
#if TEST_WITH_REAL_SERVER
    self.user = @"demo";
    self.password = @"demo";
    self.url = realURL;
#else
    self.useMockServer = YES;
    NSString* scheme = [realURL.scheme isEqualToString:@"https"] ? @"http" : realURL.scheme;
    [super setupServerWithScheme:scheme responses:responsesFile];
#endif

    [self setupSession];
    return self.session != nil;
}

- (void)useResponseSet:(NSString*)name
{
#if !TEST_WITH_REAL_SERVER
    [super useResponseSet:name];
#endif
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
        NSLog(@"authenticating as %@ %@", self.user, self.password);
        NSURLCredential* credential = [NSURLCredential credentialWithUser:self.user password:self.password persistence:NSURLCredentialPersistenceNone];
        [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
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
    return url;
}


- (void)runUntilPaused
{
    if (self.useMockServer)
    {
        [super runUntilPaused];
    }
    else
    {
        self.running = YES;
        while (self.running)
        {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
            }
        }
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
        self.running = NO;
    }
}


@end
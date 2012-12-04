//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerBaseTests.h"
#import "KMSServer.h"
#import "KMSRegExResponder.h"
#import "KMSResponseCollection.h"

#import "CK2FileManager.h"
#import <DAVKit/DAVKit.h>

@implementation CK2FileManagerBaseTests

- (void)dealloc
{
    [_password release];
    [_responses release];
    [_session release];
    [_server release];
    [_transcript release];
    [_url release];
    [_user release];

    [super dealloc];
}

- (BOOL)setupSession
{
    self.session = [[CK2FileManager alloc] init];
    self.session.delegate = self;
    self.transcript = [[[NSMutableString alloc] init] autorelease];
    return self.session != nil;
}

- (void)tearDown
{
    NSLog(@"\n\nSession transcript:\n%@\n\n", self.transcript);
}

- (BOOL)setupSessionWithRealURL:(NSURL*)realURL fakeResponses:(NSString*)responsesFile;
{
#if TEST_WITH_REAL_SERVER
    self.user = @"demo";
    self.password = @"demo";
    self.url = realURL;
    [self setupSession];
#else
    self.user = @"user";
    self.password = @"pass";

    NSURL* url = [[NSBundle bundleForClass:[self class]] URLForResource:responsesFile withExtension:@"json"];
    self.responses = [KMSResponseCollection collectionWithURL:url];
    KMSRegExResponder* responder = [self.responses responderWithName:@"default"];
    if (responder)
    {
        self.server = [KMSServer serverWithPort:0 responder:responder];
        STAssertNotNil(self.server, @"got server");

        if (self.server)
        {
            [self.server start];
            BOOL started = self.server.running;
            STAssertTrue(started, @"server started ok");

            NSString* scheme = [realURL.scheme isEqualToString:@"https"] ? @"http" : realURL.scheme;
            self.url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://127.0.0.1:%ld", scheme, self.server.port]];

            [self setupSession];
        }
    }
#endif

    return self.session != nil;
}

- (void)useResponseSet:(NSString*)name
{
#if !TEST_WITH_REAL_SERVER
    KMSResponder* responder = [self.responses responderWithName:name];
    if (responder)
    {
        self.server.responder = responder;
    }
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
    //    NSURL* url = [self.url URLByAppendingPathComponent:path];
    return url;
}


- (void)runUntilStopped
{
#if TEST_WITH_REAL_SERVER
    self.running = YES;
    while (self.running)
    {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
        }
    }
#else
    [self.server runUntilStopped];
#endif
}

- (void)stop
{
#if TEST_WITH_REAL_SERVER
    self.running = NO;
#else
    [self.server stop];
#endif
}

- (void)pause
{
#if TEST_WITH_REAL_SERVER
    self.running = NO;
#else
    [self.server pause];
#endif
}


@end
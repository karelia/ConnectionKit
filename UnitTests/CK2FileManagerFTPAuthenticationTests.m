//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerBaseTests.h"

#import "CK2FileManager.h"

@interface CK2FileManagerFTPAuthenticationTests : CK2FileManagerBaseTests

@end

@implementation CK2FileManagerFTPAuthenticationTests

- (void)fileManager:(CK2FileManager *)manager didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSString* value;

    // doesn't actually matter what we send back for the user/password, since the response is faked
    // but we change it just to make the log clearer
    if (challenge.previousFailureCount > 0)
    {
        value = @"good";
        [self useResponseSet:@"default"];
    }
    else
    {
        value = @"bad";
    }

    NSURLCredential* credential = [NSURLCredential credentialWithUser:value password:value persistence:NSURLCredentialPersistenceNone];
    [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
}

#pragma mark - Tests

- (void)testBadLoginThenGoodLogin
{
    // the server starts by rejecting the password
    // after the first challenge though, we switch to the "normal" responses so that it accepts it
    if ([self setupSessionWithRealURL:[NSURL URLWithString:@"ftp://ftp.test.com"] fakeResponses:@"ftp"])
    {
        [self useResponseSet:@"bad login"];
        NSURL* url = [self URLForPath:@"/directory/intermediate/newdirectory"];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            STAssertNil(error, @"got unexpected error %@", error);

            [self stop];
        }];
    }

    [self runUntilStopped];
}

@end
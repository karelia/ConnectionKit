//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerBaseTests.h"

#import "CK2FileManager.h"

#import <CURLHandle/CURLHandle.h>

@interface CK2FileManagerFTPAuthenticationTests : CK2FileManagerBaseTests

@end

@implementation CK2FileManagerFTPAuthenticationTests

- (void)fileManager:(CK2FileManager *)manager didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge.previousFailureCount == 0)
    {
        self.user = @"bad";
    }
    else
    {
        self.user = self.originalUser;
        [self useResponseSet:@"default"];
    }

    [super fileManager:manager didReceiveAuthenticationChallenge:challenge];
}

#pragma mark - Tests

- (void)testBadLoginThenGoodLogin
{
    // the server starts by rejecting the password
    // after the first challenge though, we switch to the "normal" responses so that it accepts it
    if ([self setupSessionWithResponses:@"ftp"])
    {
        [self removeTestDirectory];
        [self useResponseSet:@"bad login"];

        NSURL* url = [self URLForTestFolder];
        [self.session createDirectoryAtURL:url withIntermediateDirectories:YES openingAttributes:nil completionHandler:^(NSError *error) {
            BOOL isExpectedError = [self checkNoErrorOrFileExistsError:error];
            STAssertTrue(isExpectedError, @"got unexpected error %@", error);

            [self pause];
        }];
    }

    [self runUntilPaused];
}

@end
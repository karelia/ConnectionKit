//
//  CKAuthenticationChallengeSender.m
//  Marvel
//
//  Created by Mike on 20/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKAuthenticationChallengeSender.h"


@implementation CKAuthenticationChallengeSender

- (id)initWithAuthenticationChallenge:(NSURLAuthenticationChallenge *)originalChallenge
{
    [super init];
    _authenticationChallenge = originalChallenge;
    return self;
}

- (NSURLAuthenticationChallenge *)authenticationChallenge { return _authenticationChallenge; }

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    
}

@end

//
//  CKConnectionAuthentication.h
//  Connection
//
//  Created by Mike on 24/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSURLAuthenticationChallenge (ConnectionKit)

- (id)initWithAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
                   proposedCredential:(NSURLCredential *)credential;

- (id)initWithHTTPAuthenticationRef:(CFHTTPAuthenticationRef)authenticationRef
                 proposedCredential:(NSURLCredential *)credential
               previousFailureCount:(NSInteger)failureCount
                             sender:(id <NSURLAuthenticationChallengeSender>)sender
                              error:(NSError **)error;

@end


@interface NSURLCredentialStorage (ConnectionKit)
- (BOOL)getDotMacAccountName:(NSString **)account password:(NSString **)password;
@end
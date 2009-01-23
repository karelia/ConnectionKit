//
//  NSURLAuthentication+ConnectionKit.h
//  Marvel
//
//  Created by Mike on 20/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Connection/Connection.h>


@interface NSURLAuthenticationChallenge (ConnectionKit)

- (id)initWithAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
                   proposedCredential:(NSURLCredential *)credential;

- (id)initWithHTTPAuthenticationRef:(CFHTTPAuthenticationRef)authenticationRef
                 proposedCredential:(NSURLCredential *)credential
               previousFailureCount:(NSInteger)failureCount
                             sender:(id <NSURLAuthenticationChallengeSender>)sender
                              error:(NSError **)error;

@end

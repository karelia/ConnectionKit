//
//  NSURLAuthentication+ConnectionKit.m
//  Marvel
//
//  Created by Mike on 20/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "NSURLAuthentication+ConnectionKit.h"


@interface NSError (NSURLAuthentication)
+ (NSError *)errorWithCFStreamError:(CFStreamError)streamError;
- (id)initWithCFStreamError:(CFStreamError)streamError;
@end


@implementation NSURLAuthenticationChallenge (ConnectionKit)

- (id)initWithAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
                   proposedCredential:(NSURLCredential *)credential
{
    return [self initWithProtectionSpace:[challenge protectionSpace]
                      proposedCredential:credential
                    previousFailureCount:[challenge previousFailureCount]
                         failureResponse:[challenge failureResponse]
                                   error:[challenge error]
                                  sender:[challenge sender]];
}

/*  Returns nil if the ref is not suitable
 */
- (id)initWithHTTPAuthenticationRef:(CFHTTPAuthenticationRef)authenticationRef
                 proposedCredential:(NSURLCredential *)credential
               previousFailureCount:(NSInteger)failureCount
                             sender:(id <NSURLAuthenticationChallengeSender>)sender
                              error:(NSError **)outError
{
    NSParameterAssert(authenticationRef);
    
    
    // NSURLAuthenticationChallenge only handles user and password
    CFStreamError error;
    if (!CFHTTPAuthenticationIsValid(authenticationRef, &error))
    {
        if (outError) *outError = [NSError errorWithCFStreamError:error];
        [self release];
        return nil;
    }
    
    if (!CFHTTPAuthenticationRequiresUserNameAndPassword(authenticationRef))
    {
        [self release];
        return nil;
    }
    
    
    // Fail if we can't retrieve decent protection space info
    NSArray *authenticationDomains = (NSArray *)CFHTTPAuthenticationCopyDomains(authenticationRef);
    NSURL *URL = [authenticationDomains lastObject];
    [authenticationDomains release];
    if (!URL || ![URL host])
    {
        [self release];
        return nil;
    }
    
    
    // Fail for an unsupported authentication method
    CFStringRef CFAuthenticationMethod = CFHTTPAuthenticationCopyMethod(authenticationRef);
    NSString *authenticationMethod;
    if ([(NSString *)CFAuthenticationMethod isEqualToString:(NSString *)kCFHTTPAuthenticationSchemeBasic])
    {
        authenticationMethod = NSURLAuthenticationMethodHTTPBasic;
    }
    else if ([(NSString *)CFAuthenticationMethod isEqualToString:(NSString *)kCFHTTPAuthenticationSchemeDigest])
    {
        authenticationMethod = NSURLAuthenticationMethodHTTPDigest;
    }
    else
    {
        // TODO: Return an "authentication method unsupported" error
        [self release];
        return nil;
    }
    CFRelease(CFAuthenticationMethod);
    
    
    // Initialise
    CFStringRef realm = CFHTTPAuthenticationCopyRealm(authenticationRef);
    
    NSURLProtectionSpace *protectionSpace = [[NSURLProtectionSpace alloc] initWithHost:[URL host]
                                                                                  port:([URL port] ? [[URL port] intValue] : 80)
                                                                              protocol:[URL scheme]
                                                                                 realm:(NSString *)realm
                                                                  authenticationMethod:authenticationMethod];
    CFRelease(realm);
    
    self = [self initWithProtectionSpace:protectionSpace
                      proposedCredential:credential
                    previousFailureCount:failureCount
                         failureResponse:nil // TODO: Generate a NSHTTPURLResponse object
                                   error:nil
                                  sender:sender];
    
    
    // Tidy up
    [protectionSpace release];
    return self;
}

@end


@implementation NSError (NSURLAuthentication)

+ (NSError *)errorWithCFStreamError:(CFStreamError)streamError
{
    return [[[self alloc] initWithCFStreamError:streamError] autorelease];
}

- (id)initWithCFStreamError:(CFStreamError)streamError
{
    NSString *domain;
    if (streamError.domain == kCFStreamErrorDomainMacOSStatus)
    {
        domain = NSOSStatusErrorDomain;
    }
    else if (streamError.domain == kCFStreamErrorDomainPOSIX)
    {
        domain = NSPOSIXErrorDomain;
    }
    else
    {
        domain = @"CFStreamErrorDomainCustom";
    }
        
    return [self initWithDomain:domain code:streamError.error userInfo:nil];
}

@end



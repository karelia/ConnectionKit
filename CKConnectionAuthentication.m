//
//  CKConnectionAuthentication.m
//  Connection
//
//  Created by Mike on 24/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKConnectionAuthentication.h"
#import "CKConnectionAuthentication+Internal.h"


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


@implementation CKURLProtectionSpace

- (id)initWithHost:(NSString *)host port:(int)port protocol:(NSString *)protocol realm:(NSString *)realm authenticationMethod:(NSString *)authenticationMethod;
{
    if (self = [super initWithHost:host port:port protocol:protocol realm:realm authenticationMethod:authenticationMethod])
    {
        _protocol = [protocol copy];
    }
    
    return self;
}

- (void)dealloc
{
    [_protocol release];
    [super dealloc];
}

- (NSString *)protocol { return _protocol; }

/*	NSURLProtectionSpace is immutable. Returning self retained ensures the protocol can't change beneath us.
 */
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }

@end


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

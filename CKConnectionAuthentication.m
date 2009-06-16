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


#pragma mark -


@implementation NSURLCredentialStorage (ConnectionKit)

- (BOOL)getDotMacAccountName:(NSString **)account password:(NSString **)password
{
	BOOL result = NO;
	
	NSString *accountName = [[NSUserDefaults standardUserDefaults] objectForKey:@"iToolsMember"];
	if (accountName)
	{
		SecKeychainItemRef item = nil;
		OSStatus theStatus = noErr;
		char *buffer;
		UInt32 passwordLen;
		
		char *utf8 = (char *)[accountName UTF8String];
		theStatus = SecKeychainFindGenericPassword(NULL,
												   6,
												   "iTools",
												   strlen(utf8),
												   utf8,
												   &passwordLen,
												   (void *)&buffer,
												   &item);
		
		if (noErr == theStatus)
		{
			if (passwordLen > 0)
			{
				if (password) *password = [[[NSString alloc] initWithBytes:buffer length:passwordLen encoding:[NSString defaultCStringEncoding]] autorelease];
			}
			else
			{
				if (password) *password = @""; // if we have noErr but also no length, password is empty
			}
			
			// release buffer allocated by SecKeychainFindGenericPassword
			theStatus = SecKeychainItemFreeContent(NULL, buffer);
			NSAssert(!theStatus, @"Could not free keychain content");
            
			*account = accountName;
			result = YES;
		}
	}
	
	return result;
}

@end


#pragma mark -


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


#pragma mark -


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

//
//  CK2SFTPProtocol.m
//  Connection
//
//  Created by Mike on 15/10/2012.
//
//

#import "CK2SFTPProtocol.h"

#import "CK2SFTPSession.h"

#import <CurlHandle/NSURLRequest+CURLHandle.h>


@implementation CK2SFTPProtocol

+ (BOOL)canHandleURL:(NSURL *)url;
{
    NSString *scheme = [url scheme];
    return ([@"scp" caseInsensitiveCompare:scheme] == NSOrderedSame || [@"sftp" caseInsensitiveCompare:scheme] == NSOrderedSame);
}

+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
{
    // SCP and SFTP represent the home directory using ~/ at the start of the path <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    if (![path isAbsolutePath] && [[baseURL path] length] <= 1)
    {
        path = [@"/~" stringByAppendingPathComponent:path];
    }
    
    return [super URLWithPath:path relativeToURL:baseURL];
}

+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;
{
    NSString *result = [super pathOfURLRelativeToHomeDirectory:URL];
    
    // SCP and SFTP represent the home directory using ~/ at the start of the path
    if ([result hasPrefix:@"/~/"])
    {
        result = [result substringFromIndex:3];
    }
    else if ([result isEqualToString:@"/~"])
    {
        result = @".";
    }
    
    return result;
}

#pragma mark Operations

- (id)initForCreatingDirectoryWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client;
{
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    [mutableRequest curl_setNewDirectoryPermissions:[attributes objectForKey:NSFilePosixPermissions]];
    
    self = [self initWithCustomCommands:[NSArray arrayWithObject:[@"mkdir " stringByAppendingString:[[request URL] lastPathComponent]]]
                                request:mutableRequest
          createIntermediateDirectories:createIntermediates
                                 client:client
                      completionHandler:nil];
    
    [mutableRequest release];
    return self;
}

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock;
{
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    [mutableRequest curl_setCreateIntermediateDirectories:createIntermediates];
    [mutableRequest curl_setNewFilePermissions:[attributes objectForKey:NSFilePosixPermissions]];
    
    
    self = [self initWithRequest:mutableRequest client:client progressBlock:progressBlock completionHandler:^(NSError *error) {
        
        if (error)
        {
            [client protocol:self didFailWithError:error];
        }
        else
        {
            [client protocolDidFinish:self];
        }
    }];
    
    [mutableRequest release];
    
    return self;
}

- (id)initForRemovingFileWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    return [self initWithCustomCommands:[NSArray arrayWithObject:[@"rm " stringByAppendingString:[[request URL] lastPathComponent]]]
                                request:request
          createIntermediateDirectories:NO
                                 client:client
                      completionHandler:nil];
}

- (id)initForSettingAttributes:(NSDictionary *)keyedValues ofItemWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    NSNumber *permissions = [keyedValues objectForKey:NSFilePosixPermissions];
    if (permissions)
    {
        NSArray *commands = [NSArray arrayWithObject:[NSString stringWithFormat:
                                                      @"chmod %lo %@",
                                                      [permissions unsignedLongValue],
                                                      [[request URL] lastPathComponent]]];
        
        return [self initWithCustomCommands:commands
                                    request:request
              createIntermediateDirectories:NO
                                     client:client
                          completionHandler:nil];
    }
    else
    {
        self = [self initWithRequest:nil client:client];
        return self;
    }
}

#pragma mark Lifecycle

- (void)start;
{
    // If there's no request, that means we were asked to do nothing possible over SFTP. Most likely, storing attributes that aren't POSIX permissions
    // So jump straight to completion
    if (![self request])
    {
        [[self client] protocolDidFinish:self];
        return;
    }
    
    [self requestAuthenticationWithProposedCredential:nil   // client will fill it in for us
                                 previousFailureCount:0
                                                error:nil];
}

- (void)requestAuthenticationWithProposedCredential:(NSURLCredential *)credential previousFailureCount:(NSUInteger)failureCount error:(NSError *)error;
{
    NSURL *url = [[self request] URL];
    
    NSURLProtectionSpace *space = [[CK2SSHProtectionSpace alloc] initWithHost:[url host]
                                                                         port:[[url port] integerValue]
                                                                     protocol:@"ssh"
                                                                        realm:nil
                                                         authenticationMethod:NSURLAuthenticationMethodDefault];
    
    NSURLAuthenticationChallenge *challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                                                         proposedCredential:credential
                                                                                       previousFailureCount:failureCount
                                                                                            failureResponse:nil
                                                                                                      error:error
                                                                                                     sender:self];
    
    [space release];
    
    [[self client] protocol:self didReceiveAuthenticationChallenge:challenge];
    [challenge release];
}

#pragma mark NSURLAuthenticationChallengeSender

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // Swap out existing handler for one that retries after an auth failure
    void (^oldHandler)(NSError *) = _completionHandler;
    
    _completionHandler = ^(NSError *error) {
        
        if ([error code] == NSURLErrorUserAuthenticationRequired && [[error domain] isEqualToString:NSURLErrorDomain])
        {
            // Swap back to the original handler...
            void (^thisBlock)(NSError *) = _completionHandler;
            _completionHandler = [oldHandler copy];
            
            // ...then retry auth
            [self requestAuthenticationWithProposedCredential:credential
                                         previousFailureCount:([challenge previousFailureCount] + 1)
                                                        error:error];
            
            [thisBlock release];
        }
        else
        {
            oldHandler(error);
        }
    };
    
    _completionHandler = [_completionHandler copy];
    [oldHandler release];
    
    [self startWithCredential:credential];
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [self useCredential:nil forAuthenticationChallenge:challenge];  // libcurl will use annonymous login
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [[self client] protocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                                      code:NSURLErrorUserCancelledAuthentication
                                                                  userInfo:nil]];
}

@end

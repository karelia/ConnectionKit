//
//  CK2FTPProtocol.m
//  Connection
//
//  Created by Mike on 12/10/2012.
//
//

#import "CK2FTPProtocol.h"

#import "CK2FileManager.h"

#import <CurlHandle/NSURLRequest+CURLHandle.h>


@implementation CK2FTPProtocol

#pragma mark URLs

+ (BOOL)canHandleURL:(NSURL *)url;
{
    return [url ck2_isFTPURL];
}

+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
{
    // FTP is special. Absolute paths need to specified with an extra prepended slash <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    if ([path isAbsolutePath])
    {
        // Get to host's URL, including single trailing slash
        // -absoluteURL has to be called so that the real path can be properly appended
        baseURL = [[NSURL URLWithString:@"/" relativeToURL:baseURL] absoluteURL];
        return [baseURL URLByAppendingPathComponent:path];
    }
    else
    {
        return [super URLWithPath:path relativeToURL:baseURL];
    }
}

+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;
{
    // FTP is special. The first slash of the path is to be ignored <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    CFStringRef strictPath = CFURLCopyStrictPath((CFURLRef)[URL absoluteURL], NULL);
    NSString *result = [(NSString *)strictPath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (strictPath) CFRelease(strictPath);
    return result;
}

#pragma mark Operations

- (id)initForCreatingDirectoryWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client;
{
    return [self initWithCustomCommands:[NSArray arrayWithObject:[@"MKD " stringByAppendingString:[[request URL] lastPathComponent]]]
             request:request
          createIntermediateDirectories:createIntermediates
                                 client:client
                      completionHandler:nil];
}

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock;
{
    if ([request curl_createIntermediateDirectories] != createIntermediates)
    {
        NSMutableURLRequest *mutableRequest = [[request mutableCopy] autorelease];
        [mutableRequest curl_setCreateIntermediateDirectories:createIntermediates];
        request = mutableRequest;
    }
    
    
    // Use our own progress block to watch for the file end being reached before passing onto the original requester
    __block BOOL atEnd = NO;
    
    self = [self initWithRequest:request client:client progressBlock:^(NSUInteger bytesWritten) {
        
        if (bytesWritten == 0) atEnd = YES;
        if (bytesWritten && progressBlock) progressBlock(bytesWritten);
        
    } completionHandler:^(NSError *error) {
        
        // Long FTP uploads have a tendency to have the control connection cutoff for idling. As a hack, assume that if we reached the end of the body stream, a timeout is likely because of that
        if (error && atEnd && [error code] == NSURLErrorTimedOut && [[error domain] isEqualToString:NSURLErrorDomain])
        {
            error = nil;
        }
        
        if (error)
        {
            [client protocol:self didFailWithError:error];
        }
        else
        {
            [client protocolDidFinish:self];
        }
    }];
    
    return self;
}

- (id)initForRemovingFileWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    return [self initWithCustomCommands:[NSArray arrayWithObject:[@"DELE " stringByAppendingString:[[request URL] lastPathComponent]]]
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
                                                      @"SITE CHMOD %lo %@",
                                                      [permissions unsignedLongValue],
                                                      [[request URL] lastPathComponent]]];
        
        return [self initWithCustomCommands:commands
                 request:request
              createIntermediateDirectories:NO
                                     client:client
                          completionHandler:^(NSError *error) {
                              
                              if (error)
                              {
                                  // CHMOD failures for unsupported or unrecognized command should go ignored
                                  if ([error code] == CURLE_QUOTE_ERROR && [[error domain] isEqualToString:CURLcodeErrorDomain])
                                  {
                                      NSUInteger responseCode = [[[error userInfo] objectForKey:@(CURLINFO_RESPONSE_CODE)] unsignedIntegerValue];
                                      if (responseCode == 500 || responseCode == 502 || responseCode == 504)
                                      {
                                          [client protocolDidFinish:self];
                                          return;
                                      }
                                      else if (responseCode == 550)
                                      {
                                          // Nicer Cocoa-style error. Can't definitely tell the difference between the file not existing, and permission denied, sadly
                                          error = [NSError errorWithDomain:NSCocoaErrorDomain
                                                                      code:NSFileWriteUnknownError
                                                                  userInfo:@{ NSUnderlyingErrorKey : error }];
                                      }
                                  }
                              
                                  
                                  [client protocol:self didFailWithError:error];
                              }
                              else
                              {
                                  [client protocolDidFinish:self];
                              }
                          }];
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
    // If there's no request, that means we were asked to do nothing possible over FTP. Most likely, storing attributes that aren't POSIX permissions
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
    NSString *protocol = ([@"ftps" caseInsensitiveCompare:[url scheme]] == NSOrderedSame ? @"ftps" : NSURLProtectionSpaceFTP);
    
    NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:[url host]
                                                                        port:[[url port] integerValue]
                                                                    protocol:protocol
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

#pragma mark Home Directory

- (void)findHomeDirectoryWithCompletionHandler:(void (^)(NSString *path, NSError *error))handler;
{
    // Deliberately want a request that should avoid doing any work
    NSMutableURLRequest *request = [[self request] mutableCopy];
    [request setURL:[NSURL URLWithString:@"/" relativeToURL:[request URL]]];
    [request setHTTPMethod:@"HEAD"];
    
    [self sendRequest:request dataHandler:nil completionHandler:^(CURLHandle *handle, NSError *error) {
        if (error)
        {
            handler(nil, error);
        }
        else
        {
            handler([handle initialFTPPath], error);
        }
    }];
    
    [request release];
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

#pragma mark CURLHandleDelegate

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type;
{
    // Don't want to include password in transcripts usually!
    if (type == CURLINFO_HEADER_OUT &&
        [string hasPrefix:@"PASS"] &&
        ![[NSUserDefaults standardUserDefaults] boolForKey:@"AllowPasswordToBeLogged"])
    {
        string = @"PASS ####";
    }
    
    [super handle:handle didReceiveDebugInformation:string ofType:type];
}

@end

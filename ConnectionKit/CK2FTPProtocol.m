//
//  CK2FTPProtocol.m
//  Connection
//
//  Created by Mike on 12/10/2012.
//
//

#import "CK2FTPProtocol.h"

#import <CurlHandle/NSURLRequest+CURLHandle.h>


@implementation CK2FTPProtocol

#pragma mark URLs

+ (BOOL)canHandleURL:(NSURL *)url;
{
    NSString *scheme = [url scheme];
    
    return ([@"ftp" caseInsensitiveCompare:scheme] == NSOrderedSame ||
            [@"ftpes" caseInsensitiveCompare:scheme] == NSOrderedSame ||
            [@"ftps" caseInsensitiveCompare:scheme] == NSOrderedSame);
}

+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
{
    // Escape any unusual characters in the URL
    path = [path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    // FTP is special. Absolute paths need to specified with an extra prepended slash <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    // According to libcurl's docs that should be enough. But with our current build of it, it seems they've gotten stricter
    // The FTP spec could be interpreted that the only way to refer to the root directly is with the sequence @"%2F", which decodes as a slash
    // That makes it very clear to the library etc. this particular slash is meant to be transmitted to the server, rather than treated as a path component separator
    // Happily it also simplifies our code, as coaxing a double slash into NSURL is a mite tricky
    if ([path isAbsolutePath])
    {
        NSURL *result = [[NSURL URLWithString:@"/" relativeToURL:baseURL] absoluteURL];
        result = [result URLByAppendingPathComponent:path];
        return result;
    }
    
    NSURL *result = [NSURL URLWithString:path relativeToURL:baseURL];
    return result;
}

+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;
{
    // FTP is special. The first slash of the path is to be ignored <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    // As above, the library seems to be stricter on how the slash is to be encoded these days. I'm not sure whether we should be similarly strict when decoding. Leaving it be for now
    CFStringRef strictPath = CFURLCopyStrictPath((CFURLRef)[URL absoluteURL], NULL);
    NSString *result = [(NSString *)strictPath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (strictPath) CFRelease(strictPath);
    return result;
}

#pragma mark URL Requests

- (id)initWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    // libcurl doesn't understand ftpes: URLs natively, so convert them back into ftp: with the appropriate connection settings
    NSURL *url = request.URL;
    if ([url.scheme caseInsensitiveCompare:@"ftpes"] == NSOrderedSame)
    {
        url = [NSURL URLWithString:[url.absoluteString stringByReplacingCharactersInRange:NSMakeRange(0, 5) // bit hacky
                                                                               withString:@"ftp"]];
        
        NSMutableURLRequest *mutableRequest = [[request mutableCopy] autorelease];
        mutableRequest.URL = url;
        [mutableRequest curl_setDesiredSSLLevel:CURLUSESSL_ALL];
        request = mutableRequest;
    }
    
    return [super initWithRequest:request client:client];
}

#pragma mark Operations

- (id)initWithCustomCommands:(NSArray *)commands request:(NSURLRequest *)childRequest createIntermediateDirectories:(BOOL)createIntermediates client:(id<CK2ProtocolClient>)client completionHandler:(void (^)(NSError *))handler;
{
    NSMutableURLRequest *request = [childRequest mutableCopy];
    request.URL = [childRequest.URL URLByDeletingLastPathComponent];
    
    self = [super initWithCustomCommands:commands
                                 request:request
           createIntermediateDirectories:createIntermediates
                                  client:client
                       completionHandler:handler];
    
    [request release];
    return self;
}

- (id)initForCreatingDirectoryWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client;
{
    return [self initWithCustomCommands:[NSArray arrayWithObject:[@"MKD " stringByAppendingString:[[request URL] lastPathComponent]]]
             request:request
          createIntermediateDirectories:createIntermediates
                                 client:client
                      completionHandler:^(NSError *error) {

                          if (error)
                          {
                              error = [self translateStandardErrors:error];
                          }

                          [self reportToProtocolWithError:error];
                      }

            ];
}

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client progressBlock:(CK2ProgressBlock)progressBlock;
{
    if ([request curl_createIntermediateDirectories] != createIntermediates)
    {
        NSMutableURLRequest *mutableRequest = [[request mutableCopy] autorelease];
        [mutableRequest curl_setCreateIntermediateDirectories:createIntermediates];
        request = mutableRequest;
    }

    // Use our own progress block to watch for the file end being reached before passing onto the original requester
    __block BOOL atEnd = NO;
    
    self = [self initWithRequest:request client:client progressBlock:^(NSUInteger bytesWritten, NSUInteger previousAttemptsCount) {
        
        if (bytesWritten == 0) atEnd = YES;
        if (bytesWritten && progressBlock) progressBlock(bytesWritten, 0);
        
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

- (id)initForRenamingItemWithRequest:(NSURLRequest *)request newName:(NSString *)newName client:(id<CK2ProtocolClient>)client
{
    NSString* sourcePath = [[request URL] lastPathComponent];

    return [self initWithCustomCommands:[NSArray arrayWithObjects:
                                         [@"RNFR " stringByAppendingString:sourcePath],
                                         [@"RNTO " stringByAppendingString:newName],
                                         nil
                                         ]
                                request:request
          createIntermediateDirectories:NO
                                 client:client
                      completionHandler:^(NSError *error) {
                          error = [self translateStandardErrors:error];
                          [self reportToProtocolWithError:error];
                      }];
}

- (id)initForRemovingFileWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    // DELE is only intended to delete files, but in our testing, some FTP servers happily support deleting a directory using it
    return [self initWithCustomCommands:[NSArray arrayWithObject:[@"DELE " stringByAppendingString:[[request URL] lastPathComponent]]]
             request:request
          createIntermediateDirectories:NO
                                 client:client
                      completionHandler:^(NSError *error) {
                          if (error)
                          {
                              error = [self translateStandardErrors:error];
                          }

                          [self reportToProtocolWithError:error];
                      }];
}

- (id)initForSettingAttributes:(NSDictionary *)keyedValues ofItemWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    NSNumber *permissions = [keyedValues objectForKey:NSFilePosixPermissions];
    if (permissions)
    {
        NSString* path = [[request URL] lastPathComponent];
        NSArray *commands = [NSArray arrayWithObject:[NSString stringWithFormat:
                                                      @"SITE CHMOD %lo %@",
                                                      [permissions unsignedLongValue],
                                                      path]];
        
        return [self initWithCustomCommands:commands
                 request:request
              createIntermediateDirectories:NO
                                     client:client
                          completionHandler:^(NSError *error) {
                              
                              if (error)
                              {
                                  NSString* domain = error.domain;
                                  NSInteger code = error.code;

                                  // CHMOD failures for unsupported or unrecognized command should go ignored
                                  if (code== CURLE_QUOTE_ERROR && [domain isEqualToString:CURLcodeErrorDomain])
                                  {
                                      NSUInteger responseCode = [error curlResponseCode];
                                      if (responseCode == 500 || responseCode == 502 || responseCode == 504)
                                      {
                                          error = nil;
                                      }
                                  }

                                  if (error)
                                  {
                                      error = [self translateStandardErrors:error];
                                  }
                              }

                              [self reportToProtocolWithError:error];
                          }];
    }
    else
    {
        self = [self initWithRequest:nil client:client];
        return self;
    }
}

#pragma mark Errors

- (NSError*)translateStandardErrors:(NSError*)error
{
    NSString* domain = error.domain;
    NSInteger code = error.code;
    
    if (code == CURLE_QUOTE_ERROR && [domain isEqualToString:CURLcodeErrorDomain])
    {
        NSUInteger responseCode = [error curlResponseCode];
        if (responseCode == 550)
        {
            error = [self standardCouldntWriteErrorWithUnderlyingError:error];
        }
    }
    else if (code == CURLE_REMOTE_ACCESS_DENIED && [domain isEqualToString:CURLcodeErrorDomain])
    {
        // Could be a permissions problem, or could be that a CWD command failed because the directory doesn't exist
        error = [self standardCouldntReadErrorWithUnderlyingError:error];
    }
    else if ((code == NSURLErrorNoPermissionsToReadFile) && ([domain isEqualToString:NSURLErrorDomain]))
    {
        // CURLHandle helpfully returns a URL error here, but we want to return a cocoa error instead
        error = [self standardCouldntWriteErrorWithUnderlyingError:error];
    }
    else
    {
        NSLog(@"untranslated error for %@ %@", NSStringFromSelector(_cmd), error);
    }

    return error;
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

    NSURL *url = [[self request] URL];
    NSString *protocol = ([@"ftps" caseInsensitiveCompare:[url scheme]] == NSOrderedSame ? @"ftps" : NSURLProtectionSpaceFTP);
    
    NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:[url host]
                                                                        port:[[url port] integerValue]
                                                                    protocol:protocol
                                                                       realm:nil
                                                        authenticationMethod:NSURLAuthenticationMethodDefault];
    
    NSURLAuthenticationChallenge *challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                                                         proposedCredential:nil // client will fill it in for us
                                                                                       previousFailureCount:0
                                                                                            failureResponse:nil
                                                                                                      error:nil
                                                                                                     sender:self];
    
    [space release];
    
    [[self client] protocol:self didReceiveAuthenticationChallenge:challenge];
    [challenge release];
}

#pragma mark Home Directory

/*- (void)findHomeDirectoryWithCompletionHandler:(void (^)(NSString *path, NSError *error))handler;
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
}*/

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

#pragma mark Backend

// Alas, we must go back to the "easy" synchronous API for now. Multi API has a tendency to get confused by perfectly good response codes and think they're an error
+ (BOOL)usesMultiHandle; { return NO; }

@end

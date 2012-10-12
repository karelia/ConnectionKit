//
//  CK2FileTransferSession.m
//  Connection
//
//  Created by Mike on 08/10/2012.
//
//

#import "CK2FileTransferSession.h"

#import "CKConnectionRegistry.h"
#import "CK2FileTransferProtocol.h"

#import <CURLHandle/CURLHandle.h>


@interface CK2FileTransferSession () <CK2FileTransferProtocolClient>
@end


@implementation CK2FileTransferSession

#pragma mark Lifecycle

- (void)dealloc
{
    [_request release];
    [_credential release];
    [_opsAwaitingAuth release];
    
    [super dealloc];
}

- (void)doAuthForURL:(NSURL *)url completionHandler:(void (^)(void))block;
{
    // First demand auth
    if (!_opsAwaitingAuth)
    {
        _opsAwaitingAuth = [[NSOperationQueue alloc] init];
        [_opsAwaitingAuth setSuspended:YES];
        
        NSString *protocol = ([@"ftps" caseInsensitiveCompare:[url scheme]] == NSOrderedSame ? @"ftps" : NSURLProtectionSpaceFTP);
        
        NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:[url host]
                                                                            port:[[url port] integerValue]
                                                                        protocol:protocol
                                                                           realm:nil
                                                            authenticationMethod:NSURLAuthenticationMethodDefault];
        
        NSURLCredential *credential = [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:space];
        
        NSURLAuthenticationChallenge *challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                                                             proposedCredential:credential
                                                                                           previousFailureCount:0
                                                                                                failureResponse:nil
                                                                                                          error:nil
                                                                                                         sender:self];
        
        [space release];
        
        [[self delegate] fileTransferSession:self didReceiveAuthenticationChallenge:challenge];
        [challenge release];
    }
    
    
    // Will run pretty much immediately once we're authenticated
    [_opsAwaitingAuth addOperationWithBlock:block];
}

#pragma mark NSURLAuthenticationChallengeSender

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    _credential = [credential copy];
    [_opsAwaitingAuth setSuspended:NO];
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [_opsAwaitingAuth setSuspended:NO];
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [NSException raise:NSInvalidArgumentException format:@"Don't support cancelling FTP session auth yet"];
}

#pragma mark Home Directory

- (void)findHomeDirectoryWithCompletionHandler:(void (^)(NSString *path, NSError *error))handler;
{
    // Deliberately want a request that should avoid doing any work
    NSMutableURLRequest *request = [_request mutableCopy];
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

#pragma mark Discovering Directory Contents

- (void)contentsOfDirectoryAtURL:(NSURL *)url
      includingPropertiesForKeys:(NSArray *)keys
                         options:(NSDirectoryEnumerationOptions)mask
               completionHandler:(void (^)(NSArray *, NSError *))block;
{
    NSMutableArray *contents = [[NSMutableArray alloc] init];
    __block BOOL resolved = NO;
    
    [self enumerateContentsOfURL:url includingPropertiesForKeys:keys options:(mask|NSDirectoryEnumerationSkipsSubdirectoryDescendants) usingBlock:^(NSURL *aURL) {
        
        if (resolved)
        {
            [contents addObject:aURL];
        }
        else
        {
            resolved = YES;
        }
        
    } completionHandler:^(NSError *error) {
        
        block(contents, error);
        [contents release];
    }];
}

- (void)enumerateContentsOfURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask usingBlock:(void (^)(NSURL *))block completionHandler:(void (^)(NSError *))completionBlock;
{
    NSParameterAssert(url);
    
    [CK2FileTransferProtocol protocolForURL:url completionHandler:^(Class protocol) {
        
        if (protocol)
        {
            [protocol startEnumeratingContentsOfURL:url
                         includingPropertiesForKeys:keys
                                            options:mask
                                             client:self
                                              token:completionBlock
                                         usingBlock:block];
        }
        else if ([url isFileURL])
        {
            // Fall back to standard file manager                
            NSFileManager *manager = [[NSFileManager alloc] init];
            
            // Enumerate contents
            NSDirectoryEnumerator *enumerator = [manager enumeratorAtURL:url includingPropertiesForKeys:keys options:mask errorHandler:^BOOL(NSURL *url, NSError *error) {
                
                NSLog(@"enumeration error: %@", error);
                return YES;
            }];
            
            BOOL reportedDirectory = NO;
            
            NSURL *aURL;
            while (aURL = [enumerator nextObject])
            {
                // Report the main directory first
                if (!reportedDirectory)
                {
                    block(url);
                    reportedDirectory = YES;
                }
                
                block(aURL);
            }
            
            [manager release];
            completionBlock(nil);
        }
        else
        {
            // I thought NSFileManager would give us back a nice NSURLErrorUnsupportedURL error or similar if fed a non-file URL, but in practice it just reports that the file doesn't exist, which isn't ideal. So do our own handling instead
            NSDictionary *info = @{NSURLErrorKey : url, NSURLErrorFailingURLErrorKey : url, NSURLErrorFailingURLStringErrorKey : [url absoluteString]};
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnsupportedURL userInfo:info];
            completionBlock(error);
        }
    }];
}

#pragma mark Creating and Deleting Items

- (void)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(url);
    
    [CK2FileTransferProtocol protocolForURL:url completionHandler:^(Class protocol) {
        
        if (protocol)
        {
            [protocol startCreatingDirectoryAtURL:url withIntermediateDirectories:createIntermediates client:self token:handler];
        }
        else
        {            
            NSFileManager *manager = [[NSFileManager alloc] init];
            
            NSError *error;
            if ([manager createDirectoryAtURL:url withIntermediateDirectories:createIntermediates attributes:nil error:&error])
            {
                error = nil;
            }
            else if (!error)
            {
                error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
            }
            
            handler(error);
            [manager release];
        }
    }];
}

- (void)createFileAtURL:(NSURL *)url contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
{
    if (![url isFileURL])
    {
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
        [request setHTTPBody:data];
        
        [self createFileWithRequest:request withIntermediateDirectories:createIntermediates progressBlock:progressBlock];
        [request release];
    }
    else
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            // TODO: Use a stream or similar to write incrementally and report progress
            NSError *error;
            if ([data writeToURL:url options:0 error:&error])
            {
                error = nil;
            }
            else if (!error)
            {
                error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
            }
            
            progressBlock((error ? 0 : [data length]), error);
        });
    }
}

- (void)createFileAtURL:(NSURL *)destinationURL withContentsOfURL:(NSURL *)sourceURL withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
{
    if (![destinationURL isFileURL])
    {
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:destinationURL];
        
        // Read the data using an input stream if possible
        NSInputStream *stream = [[NSInputStream alloc] initWithURL:sourceURL];
        if (stream)
        {
            [request setHTTPBodyStream:stream];
            [stream release];
        }
        else
        {
            NSError *error;
            NSData *data = [[NSData alloc] initWithContentsOfURL:sourceURL options:0 error:&error];
            
            if (data)
            {
                [request setHTTPBody:data];
                [data release];
            }
            else
            {
                [request release];
                if (!error) error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
                progressBlock(0, error);
                return;
            }
        }
        
        [self createFileWithRequest:request withIntermediateDirectories:createIntermediates progressBlock:progressBlock];
        [request release];
    }
    else
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            NSError *error;
            NSData *data = [[NSData alloc] initWithContentsOfURL:sourceURL options:0 error:&error];
            
            if (data)
            {
                if ([data writeToURL:destinationURL options:0 error:&error])
                {
                    error = nil;
                }
                else if (!error)
                {
                    error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
                }
            }
            else if (!error)
            {
                error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
            }
            
            progressBlock((error ? 0 : [data length]), error);
        });
    }
}

- (void)createFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
{
    NSParameterAssert(request);
    
    [CK2FileTransferProtocol protocolForURL:[request URL] completionHandler:^(Class protocol) {
        
        if (protocol)
        {
            void (^block)(NSError *) = ^(NSError *error){
                progressBlock(0, error);
            };
            
            [protocol startCreatingFileWithRequest:request withIntermediateDirectories:createIntermediates client:self token:block progressBlock:^(NSUInteger bytesWritten){
                progressBlock(bytesWritten, nil);
            }];
        }
        else
        {
            
        }
    }];
}

- (void)removeFileAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(url);
    
    [CK2FileTransferProtocol protocolForURL:url completionHandler:^(Class protocol) {
        
        if (protocol)
        {
            [protocol startRemovingFileAtURL:url client:self token:handler];
        }
        else
        {
            NSFileManager *manager = [[NSFileManager alloc] init];
            
            NSError *error;
            if ([manager removeItemAtURL:url error:&error])
            {
                error = nil;
            }
            else if (!error)
            {
                error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
            }
            
            handler(error);
            [manager release];
        }
    }];
}

#pragma mark Getting and Setting Attributes

- (void)setResourceValues:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(keyedValues);
    NSParameterAssert(url);
    
    [CK2FileTransferProtocol protocolForURL:url completionHandler:^(Class protocol) {
        
        if (protocol)
        {
            [protocol startRemovingFileAtURL:url client:self token:handler];
        }
        else
        {
            NSError *error;
            if ([url setResourceValues:keyedValues error:&error])
            {
                error = nil;
            }
            else if (!error)
            {
                error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
            }
            
            handler(error);
        }
    }];
}

#pragma mark Delegate

@synthesize delegate = _delegate;

#pragma mark CK2FileTransferProtocolClient

// As a gloriously cunning ruse, the tokens passed to protocols are actually completion blocks!

- (void)fileTransferProtocolDidFinishWithToken:(id)token;
{
    void (^block)(NSError *) = token;
    block(nil);
}

- (void)fileTransferProtocolToken:(id)token didFailWithError:(NSError *)error;
{
    if (!error) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil];
    
    void (^block)(NSError *) = token;
    block(error);
}

- (void)fileTransferProtocolToken:(id)token didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // TODO: Cache credentials per protection space
    // TODO: bounce challenge over a suitable thread?
    [[self delegate] fileTransferSession:self didReceiveAuthenticationChallenge:challenge];
}

- (void)fileTransferProtocolToken:(id)token appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript;
{
    // TODO: bounce message over a suitable thread?
    [[self delegate] fileTransferSession:self appendString:info toTranscript:transcript];
}

#pragma mark FTP URL helpers

+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
{
    // FTP is special. Absolute paths need to specified with an extra prepended slash <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    NSString *scheme = [baseURL scheme];
    
    if (([@"ftp" caseInsensitiveCompare:scheme] == NSOrderedSame || [@"ftps" caseInsensitiveCompare:scheme] == NSOrderedSame) &&
        [path isAbsolutePath])
    {
        // Get to host's URL, including single trailing slash
        // -absoluteURL has to be called so that the real path can be properly appended
        baseURL = [[NSURL URLWithString:@"/" relativeToURL:baseURL] absoluteURL];
        return [baseURL URLByAppendingPathComponent:path];
    }
    else
    {
        return [NSURL URLWithString:[path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]
                      relativeToURL:baseURL];
    }
}

+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;
{
    // FTP is special. The first slash of the path is to be ignored <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    NSString *scheme = [URL scheme];
    if ([@"ftp" caseInsensitiveCompare:scheme] == NSOrderedSame || [@"ftps" caseInsensitiveCompare:scheme] == NSOrderedSame)
    {
        CFStringRef strictPath = CFURLCopyStrictPath((CFURLRef)[URL absoluteURL], NULL);
        NSString *result = [(NSString *)strictPath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (strictPath) CFRelease(strictPath);
        return result;
    }
    else
    {
        return [URL path];
    }
}

@end


#pragma mark -


@implementation NSURL (ConnectionKit)

- (BOOL)ck2_isFTPURL;
{
    NSString *scheme = [self scheme];
    return ([@"ftp" caseInsensitiveCompare:scheme] == NSOrderedSame || [@"ftps" caseInsensitiveCompare:scheme] == NSOrderedSame);
}

@end

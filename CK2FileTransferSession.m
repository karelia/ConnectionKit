//
//  CK2FileTransferSession.m
//  Connection
//
//  Created by Mike on 08/10/2012.
//
//

#import "CK2FileTransferSession.h"

#import "CKConnectionRegistry.h"
#import "CKRemoteURL.h"

#import <CURLHandle/CURLHandle.h>
#import <CurlHandle/NSURLRequest+CURLHandle.h>

#import <sys/dirent.h>


@interface CK2Transfer : NSObject <CURLHandleDelegate>
{
  @private
    CK2FileTransferSession  *_session;
    
    void    (^_completionHandler)(CURLHandle *handle, NSError *error);
    void    (^_dataBlock)(NSData *data);
    void    (^_progressBlock)(NSUInteger bytesWritten);
}

- (id)initWithRequest:(NSURLRequest *)request
              session:(CK2FileTransferSession *)session
          dataHandler:(void (^)(NSData *data))dataBlock
    completionHandler:(void (^)(CURLHandle *handle, NSError *error))handler;

- (id)initWithRequest:(NSURLRequest *)request
              session:(CK2FileTransferSession *)session
        progressBlock:(void (^)(NSUInteger bytesWritten))progressBlock
    completionHandler:(void (^)(CURLHandle *handle, NSError *error))handler;

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

#pragma mark Requests

- (NSMutableURLRequest *)newMutableRequestWithURL:(NSURL *)url isDirectory:(BOOL)directory;
{
    // CURL is very particular about whether URLs passed to it have directory terminator or not
    if (directory != CFURLHasDirectoryPath((CFURLRef)url))
    {
        NSString *lastComponent = [url lastPathComponent];
        url = [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:lastComponent isDirectory:directory];
    }
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setCachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData];
    return request;
}

#pragma mark Operations

- (void)executeCustomCommands:(NSArray *)commands
             inDirectoryAtURL:(NSURL *)directory
createIntermediateDirectories:(BOOL)createIntermediates
            completionHandler:(void (^)(NSError *error))handler;
{
    // Navigate to the directory
    // @"HEAD" => CURLOPT_NOBODY, which stops libcurl from trying to list the directory's contents
    // If the connection is already at that directory then curl wisely does nothing
    NSMutableURLRequest *request = [self newMutableRequestWithURL:directory isDirectory:YES];
    [request setHTTPMethod:@"HEAD"];
    [request curl_setCreateIntermediateDirectories:createIntermediates];
    
    // Custom commands once we're in the correct directory
    // CURLOPT_PREQUOTE does much the same thing, but sometimes runs the command twice in my testing
    [request curl_setPostTransferCommands:commands];
    
    [self sendRequest:request dataHandler:nil completionHandler:^(CURLHandle *handle, NSError *error) {
        handler(error);
    }];
    
    [request release];
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

- (void)sendRequest:(NSURLRequest *)request dataHandler:(void (^)(NSData *data))dataBlock completionHandler:(void (^)(CURLHandle *handle, NSError *error))handler;
{
    [self doAuthForURL:[request URL] completionHandler:^{
        CK2Transfer *transfer = [[CK2Transfer alloc] initWithRequest:request session:self dataHandler:dataBlock completionHandler:^(CURLHandle *handle, NSError *error) {
            
            handler(handle, error);
        }];
        [transfer release];
    }];
}

- (void)sendRequest:(NSURLRequest *)request progressBlock:(void (^)(NSUInteger bytesWritten))progressBlock completionHandler:(void (^)(CURLHandle *handle, NSError *error))handler;
{
    [self doAuthForURL:[request URL] completionHandler:^{
        CK2Transfer *transfer = [[CK2Transfer alloc] initWithRequest:request session:self progressBlock:progressBlock completionHandler:^(CURLHandle *handle, NSError *error) {
            
            handler(handle, error);
        }];
        [transfer release];
    }];
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
    
    if ([url ck2_isFTPURL])
    {
        NSMutableURLRequest *request = [self newMutableRequestWithURL:url isDirectory:YES];
        url = [request URL];    // ensures it's a directory URL
        
        NSMutableData *totalData = [[NSMutableData alloc] init];
        
        [self sendRequest:request dataHandler:^(NSData *data) {
            [totalData appendData:data];
        } completionHandler:^(CURLHandle *handle, NSError *error) {
            
            if (error)
            {
                completionBlock(error);
            }
            else
            {
                // Report directory itself
                NSURL *resolved = url;
                NSString *path = [[self class] pathOfURLRelativeToHomeDirectory:url];
                if (![path isAbsolutePath])
                {
                    NSString *home = [handle initialFTPPath];
                    if ([home isAbsolutePath])
                    {
                        resolved = [[self class] URLWithPath:home relativeToURL:url];
                        resolved = [resolved URLByAppendingPathComponent:path];
                    }
                }
                
                block(resolved);
                
                
                // Process the data to make a directory listing
                while (1)
                {
                    CFDictionaryRef parsedDict = NULL;
                    CFIndex bytesConsumed = CFFTPCreateParsedResourceListing(NULL,
                                                                             [totalData bytes], [totalData length],
                                                                             &parsedDict);
                    
                    if (bytesConsumed > 0)
                    {
                        // Make sure CFFTPCreateParsedResourceListing was able to properly
                        // parse the incoming data
                        if (parsedDict)
                        {
                            NSString *name = CFDictionaryGetValue(parsedDict, kCFFTPResourceName);
                            if (!((mask & NSDirectoryEnumerationSkipsHiddenFiles) && [name hasPrefix:@"."]))
                            {
                                NSNumber *type = CFDictionaryGetValue(parsedDict, kCFFTPResourceType);
                                BOOL isDirectory = [type intValue] == DT_DIR;
                                NSURL *nsURL = [resolved URLByAppendingPathComponent:name isDirectory:isDirectory];
                                
                                // Switch over to custom URL class that actually accepts temp values. rdar://problem/11069131
                                CKRemoteURL *aURL = [[CKRemoteURL alloc] initWithString:[nsURL relativeString] relativeToURL:[nsURL baseURL]];
                                
                                // Fill in requested keys as best we can
                                NSArray *keysToFill = (keys ? keys : [NSArray arrayWithObjects:
                                                                      NSURLContentModificationDateKey,
                                                                      NSURLIsDirectoryKey,
                                                                      NSURLIsRegularFileKey,
                                                                      NSURLIsSymbolicLinkKey,
                                                                      NSURLNameKey,
                                                                      NSURLFileResourceTypeKey, // 10.7 properties go last because might be nil at runtime
                                                                      NSURLFileSecurityKey,
                                                                      nil]);
                                
                                for (NSString *aKey in keysToFill)
                                {
                                    if ([aKey isEqualToString:NSURLContentModificationDateKey])
                                    {
                                        [aURL setTemporaryResourceValue:CFDictionaryGetValue(parsedDict, kCFFTPResourceModDate) forKey:aKey];
                                    }
                                    else if ([aKey isEqualToString:NSURLEffectiveIconKey])
                                    {
                                        // Not supported yet but could be
                                    }
                                    else if ([aKey isEqualToString:NSURLFileResourceTypeKey])
                                    {
                                        NSString *typeValue;
                                        switch ([type integerValue])
                                        {
                                            case DT_CHR:
                                                typeValue = NSURLFileResourceTypeCharacterSpecial;
                                                break;
                                            case DT_DIR:
                                                typeValue = NSURLFileResourceTypeDirectory;
                                                break;
                                            case DT_BLK:
                                                typeValue = NSURLFileResourceTypeBlockSpecial;
                                                break;
                                            case DT_REG:
                                                typeValue = NSURLFileResourceTypeRegular;
                                                break;
                                            case DT_LNK:
                                                typeValue = NSURLFileResourceTypeSymbolicLink;
                                                break;
                                            case DT_SOCK:
                                                typeValue = NSURLFileResourceTypeSocket;
                                                break;
                                            default:
                                                typeValue = NSURLFileResourceTypeUnknown;
                                        }
                                        
                                        [aURL setTemporaryResourceValue:typeValue forKey:aKey];
                                    }
                                    else if ([aKey isEqualToString:NSURLFileSecurityKey])
                                    {
                                        // Not supported yet but could be
                                    }
                                    else if ([aKey isEqualToString:NSURLHasHiddenExtensionKey])
                                    {
                                        // Could fake it?
                                    }
                                    else if ([aKey isEqualToString:NSURLIsDirectoryKey])
                                    {
                                        [aURL setTemporaryResourceValue:@(isDirectory) forKey:aKey];
                                    }
                                    else if ([aKey isEqualToString:NSURLIsHiddenKey])
                                    {
                                        [aURL setTemporaryResourceValue:@([name hasPrefix:@"."]) forKey:aKey];
                                    }
                                    else if ([aKey isEqualToString:NSURLIsPackageKey])
                                    {
                                        // Could guess based on extension
                                    }
                                    else if ([aKey isEqualToString:NSURLIsRegularFileKey])
                                    {
                                        [aURL setTemporaryResourceValue:@([type intValue] == DT_REG) forKey:aKey];
                                    }
                                    else if ([aKey isEqualToString:NSURLIsSymbolicLinkKey])
                                    {
                                        [aURL setTemporaryResourceValue:@([type intValue] == DT_LNK) forKey:aKey];
                                    }
                                    else if ([aKey isEqualToString:NSURLLocalizedNameKey])
                                    {
                                        // Strip off extensions? Return last path component?
                                    }
                                    else if ([aKey isEqualToString:NSURLLocalizedTypeDescriptionKey])
                                    {
                                        // Could guess from extension
                                    }
                                    else if ([aKey isEqualToString:NSURLNameKey])
                                    {
                                        [aURL setTemporaryResourceValue:name forKey:aKey];
                                    }
                                    else if ([aKey isEqualToString:NSURLParentDirectoryURLKey])
                                    {
                                        // Can derive by deleting last path component. Always true though?
                                    }
                                    else if ([aKey isEqualToString:NSURLPathKey])
                                    {
                                        // Could do via our +pathOfURLRelativeToHomeDirectory: routine
                                    }
                                    else if ([aKey isEqualToString:NSURLTypeIdentifierKey])
                                    {
                                        // Could guess from extension
                                    }
                                }
                                
                                block(aURL);
                                [aURL release];
                            }
                            
                            CFRelease(parsedDict);
                        }
                        
                        [totalData replaceBytesInRange:NSMakeRange(0, bytesConsumed) withBytes:NULL length:0];
                    }
                    else if (bytesConsumed < 0)
                    {
                        // error!
                        NSDictionary *userInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
                                                  [request URL], NSURLErrorFailingURLErrorKey,
                                                  [[request URL] absoluteString], NSURLErrorFailingURLStringErrorKey,
                                                  nil];
                        
                        NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotParseResponse userInfo:userInfo];
                        [userInfo release];
                        
                        completionBlock(error);
                        break;
                    }
                    else
                    {
                        completionBlock(nil);
                        break;
                    }
                }
            }
        }];
        
        [request release];
    }
    else if ([url isFileURL])
    {
        // Fall back to standard file manager
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
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
        });
    }
    else
    {
        // I thought NSFileManager would give us back a nice NSURLErrorUnsupportedURL error or similar if fed a non-file URL, but in practice it just reports that the file doesn't exist, which isn't ideal. So do our own handling instead
        NSDictionary *info = @{NSURLErrorKey : url, NSURLErrorFailingURLErrorKey : url, NSURLErrorFailingURLStringErrorKey : [url absoluteString]};
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnsupportedURL userInfo:info];
        completionBlock(error);
    }
}

#pragma mark Creating and Deleting Items

- (void)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates completionHandler:(void (^)(NSError *error))handler;
{
    if ([url ck2_isFTPURL])
    {
        return [self executeCustomCommands:[NSArray arrayWithObject:[@"MKD " stringByAppendingString:[url lastPathComponent]]]
                          inDirectoryAtURL:[url URLByDeletingLastPathComponent]
             createIntermediateDirectories:createIntermediates
                         completionHandler:handler];
    }
    else
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
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
        });
    }
}

- (void)createFileAtURL:(NSURL *)url contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
{
    if ([url ck2_isFTPURL])
    {
        NSMutableURLRequest *request = [self newMutableRequestWithURL:url isDirectory:NO];
        [request setHTTPBody:data];
        [request curl_setCreateIntermediateDirectories:createIntermediates];
        
        [self createFileWithRequest:request progressBlock:progressBlock];
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
    if ([destinationURL ck2_isFTPURL])
    {
        NSMutableURLRequest *request = [self newMutableRequestWithURL:destinationURL isDirectory:NO];
        
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
        
        [request curl_setCreateIntermediateDirectories:createIntermediates];
        
        [self createFileWithRequest:request progressBlock:progressBlock];
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

- (void)createFileWithRequest:(NSURLRequest *)request progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
{
    // Use our own progress block to watch for the file end being reached before passing onto the original requester
    __block BOOL atEnd = NO;
    
    [self sendRequest:request progressBlock:^(NSUInteger bytesWritten) {
        
        if (bytesWritten == 0) atEnd = YES;
        if (bytesWritten && progressBlock) progressBlock(bytesWritten, nil);
        
    } completionHandler:^(CURLHandle *handle, NSError *error) {
        
        // Long FTP uploads have a tendency to have the control connection cutoff for idling. As a hack, assume that if we reached the end of the body stream, a timeout is likely because of that
        if (error && atEnd && [error code] == NSURLErrorTimedOut && [[error domain] isEqualToString:NSURLErrorDomain])
        {
            error = nil;
        }
        
        progressBlock(0, error);
    }];
}

- (void)removeFileAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
{
    if ([url ck2_isFTPURL])
    {
        return [self executeCustomCommands:[NSArray arrayWithObject:[@"DELE " stringByAppendingString:[url lastPathComponent]]]
                          inDirectoryAtURL:[url URLByDeletingLastPathComponent]
             createIntermediateDirectories:NO
                         completionHandler:handler];
    }
    else
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
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
        });
    }
}

#pragma mark Getting and Setting Attributes

- (void)setResourceValues:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(keyedValues);
    NSParameterAssert(url);
    
    if ([url ck2_isFTPURL])
    {
        NSNumber *permissions = [keyedValues objectForKey:NSFilePosixPermissions];
        if (permissions)
        {
            NSArray *commands = [NSArray arrayWithObject:[NSString stringWithFormat:
                                                          @"SITE CHMOD %lo %@",
                                                          [permissions unsignedLongValue],
                                                          [url lastPathComponent]]];
            
            [self executeCustomCommands:commands
                       inDirectoryAtURL:[url URLByDeletingLastPathComponent]
          createIntermediateDirectories:NO
                      completionHandler:handler];
            
            return;
        }
        
        handler(nil);
    }
    else
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
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
        });
    }
}

#pragma mark Delegate

@synthesize delegate = _delegate;

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type;
{
    // Don't want to include password in transcripts usually!
    if (type == CURLINFO_HEADER_OUT &&
        [string hasPrefix:@"PASS"] &&
        ![[NSUserDefaults standardUserDefaults] boolForKey:@"AllowPasswordToBeLogged"])
    {
        string = @"PASS ####";
    }
    
    [[self delegate] fileTransferSession:self appendString:string toTranscript:(type == CURLINFO_HEADER_IN ? CKTranscriptReceived : CKTranscriptSent)];
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


@implementation CK2Transfer

- (id)initWithRequest:(NSURLRequest *)request session:(CK2FileTransferSession *)session completionHandler:(void (^)(CURLHandle *, NSError *))handler;
{
    if (self = [self init])
    {
        [self retain];  // until finished
        _session = [session retain];
        _completionHandler = [handler copy];
        
        CURLHandle *handle = [[CURLHandle alloc] initWithRequest:request
                                                      credential:[session valueForKey:@"_credential"]   // dirty secret!
                                                        delegate:self];
        
        [handle release];   // handle retains itself until finished or cancelled
    }
    
    return self;
}

- (id)initWithRequest:(NSURLRequest *)request session:(CK2FileTransferSession *)session dataHandler:(void (^)(NSData *))dataBlock completionHandler:(void (^)(CURLHandle *, NSError *))handler
{
    if (self = [self initWithRequest:request session:session completionHandler:handler])
    {
        _dataBlock = [dataBlock copy];
    }
    return self;
}

- (id)initWithRequest:(NSURLRequest *)request session:(CK2FileTransferSession *)session progressBlock:(void (^)(NSUInteger))progressBlock completionHandler:(void (^)(CURLHandle *, NSError *))handler
{
    if (self = [self initWithRequest:request session:session completionHandler:handler])
    {
        _progressBlock = [progressBlock copy];
    }
    return self;
}

- (void)handle:(CURLHandle *)handle didFailWithError:(NSError *)error;
{
    if (!error) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil];
    _completionHandler(handle, error);
    [self release];
}

- (void)handle:(CURLHandle *)handle didReceiveData:(NSData *)data;
{
    if (_dataBlock) _dataBlock(data);
}

- (void)handle:(CURLHandle *)handle willSendBodyDataOfLength:(NSUInteger)bytesWritten
{
    if (_progressBlock) _progressBlock(bytesWritten);
}

- (void)handleDidFinish:(CURLHandle *)handle;
{
    _completionHandler(handle, nil);
    [self release];
}

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type;
{
    [[_session delegate] fileTransferSession:_session appendString:string toTranscript:(type == CURLINFO_HEADER_IN ? CKTranscriptReceived : CKTranscriptSent)];
}

- (void)dealloc;
{
    [_session release];
    [_completionHandler release];
    [_dataBlock release];
    [_progressBlock release];
    
    [super dealloc];
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

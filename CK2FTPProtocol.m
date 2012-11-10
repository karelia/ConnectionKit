//
//  CK2FTPProtocol.m
//  Connection
//
//  Created by Mike on 12/10/2012.
//
//

#import "CK2FTPProtocol.h"

#import "CK2FileManager.h"
#import "CKRemoteURL.h"

#import <CurlHandle/NSURLRequest+CURLHandle.h>

#import <sys/dirent.h>


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

#pragma mark Requests

+ (NSURLRequest *)newRequestWithRequest:(NSURLRequest *)request isDirectory:(BOOL)directory;
{
    NSURL *url = [request URL];
    
    // CURL is very particular about whether URLs passed to it have directory terminator or not
    if (directory != CFURLHasDirectoryPath((CFURLRef)url))
    {
        if (directory)
        {
            url = [url URLByAppendingPathComponent:@""];
        }
        else
        {
            NSString *lastComponent = [url lastPathComponent];
            url = [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:lastComponent isDirectory:directory];
        }
    }
    
    NSMutableURLRequest *result = [request mutableCopy];
    [result setURL:url];
    return result;
}

- (id)initWithCustomCommands:(NSArray *)commands request:(NSURLRequest *)childRequest createIntermediateDirectories:(BOOL)createIntermediates client:(id <CK2ProtocolClient>)client;
{
    // Navigate to the directory
    // @"HEAD" => CURLOPT_NOBODY, which stops libcurl from trying to list the directory's contents
    // If the connection is already at that directory then curl wisely does nothing
    NSMutableURLRequest *request = [childRequest mutableCopy];
    [request setURL:[[childRequest URL] URLByDeletingLastPathComponent]];
    [request setHTTPMethod:@"HEAD"];
    [request curl_setCreateIntermediateDirectories:createIntermediates];
    
    // Custom commands once we're in the correct directory
    // CURLOPT_PREQUOTE does much the same thing, but sometimes runs the command twice in my testing
    [request curl_setPostTransferCommands:commands];
    
    self = [self initWithRequest:request client:client dataHandler:nil completionHandler:^(NSError *error) {
        
        if (error)
        {
            [client protocol:self didFailWithError:error];
        }
        else
        {
            [client protocolDidFinish:self];
        }
    }];
    
    [request release];
    return self;
}

#pragma mark Operations

- (id)initForEnumeratingDirectoryWithRequest:(NSURLRequest *)request includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask client:(id<CK2ProtocolClient>)client;
{
    request = [[self class] newRequestWithRequest:request isDirectory:YES];
    
    NSMutableData *totalData = [[NSMutableData alloc] init];
    
    self = [self initWithRequest:request client:client dataHandler:^(NSData *data) {
        
        [totalData appendData:data];
        
    } completionHandler:^(NSError *error) {
        
        if (error)
        {
            [client protocol:self didFailWithError:error];
        }
        else
        {
            // Report directory itself
            NSURL *url = [request URL];    // ensures it's a directory URL;
            NSString *path = [CK2FileManager pathOfURLRelativeToHomeDirectory:url];
            if (![path isAbsolutePath])
            {
                NSString *home = [_handle initialFTPPath];
                if ([home isAbsolutePath])
                {
                    url = [CK2FileManager URLWithPath:home relativeToURL:url];
                    url = [url URLByAppendingPathComponent:path];
                }
            }
            
            [client protocol:self didDiscoverItemAtURL:url];
            
            
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
                            NSURL *nsURL = [url URLByAppendingPathComponent:name isDirectory:isDirectory];
                            
                            // Switch over to custom URL class that actually accepts temp values. rdar://problem/11069131
                            CKRemoteURL *aURL = [[CKRemoteURL alloc] initWithString:[nsURL relativeString] relativeToURL:[nsURL baseURL]];
                            
                            // Fill in requested keys as best we can
                            NSArray *keysToFill = (keys ? keys : [NSArray arrayWithObjects:
                                                                  NSURLContentModificationDateKey,
                                                                  NSURLIsDirectoryKey,
                                                                  NSURLIsRegularFileKey,
                                                                  NSURLIsSymbolicLinkKey,
                                                                  NSURLNameKey,
                                                                  NSURLFileSizeKey,
                                                                  CK2URLSymbolicLinkDestinationKey,
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
                                else if ([aKey isEqualToString:NSURLTypeIdentifierKey])
                                {
                                    // Guess from symlink, extension, and directory
                                    if ([type intValue] == DT_LNK)
                                    {
                                        [aURL setTemporaryResourceValue:(NSString *)kUTTypeSymLink forKey:aKey];
                                    }
                                    else
                                    {
                                        NSString *extension = [name pathExtension];
                                        if ([extension length])
                                        {
                                            CFStringRef type = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                                                                     (CFStringRef)extension,
                                                                                                     (isDirectory ? kUTTypeDirectory : kUTTypeData));
                                            
                                            [aURL setTemporaryResourceValue:(NSString *)type forKey:aKey];
                                            CFRelease(type);
                                        }
                                        else
                                        {
                                            [aURL setTemporaryResourceValue:(NSString *)kUTTypeData forKey:aKey];
                                        }
                                    }
                                }
                                else if ([aKey isEqualToString:NSURLFileSizeKey])
                                {
                                    [aURL setTemporaryResourceValue:CFDictionaryGetValue(parsedDict, kCFFTPResourceSize) forKey:aKey];
                                }
                                else if ([aKey isEqualToString:CK2URLSymbolicLinkDestinationKey])
                                {
                                    NSString *path = CFDictionaryGetValue(parsedDict, kCFFTPResourceLink);
                                    if ([path length])
                                    {
                                        // Servers in my experience hand include a trailing slash to indicate if the target is a directory
                                        // Could generate a CK2RemoteURL instead so as to explicitly mark it as a directory, but that seems unecessary for now
                                        // According to the original CKConnectionOpenPanel source, some servers use a backslash instead. I don't know what though – Windows based ones? If so, do they use backslashes for all path components?
                                        [aURL setTemporaryResourceValue:[CK2FileManager URLWithPath:path relativeToURL:url] forKey:aKey];
                                    }
                                }
                            }
                            
                            [client protocol:self didDiscoverItemAtURL:aURL];
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
                    
                    [client protocol:self didFailWithError:error];
                    break;
                }
                else
                {
                    [client protocolDidFinish:self];
                    break;
                }
            }
        }
    }];
    
    [request release];
    return self;
}

- (id)initForCreatingDirectoryWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates client:(id<CK2ProtocolClient>)client;
{
    return [self initWithCustomCommands:[NSArray arrayWithObject:[@"MKD " stringByAppendingString:[[request URL] lastPathComponent]]]
             request:request
          createIntermediateDirectories:createIntermediates
                                 client:client];
}

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates client:(id<CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock;
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
                                 client:client];
}

- (id)initForSettingResourceValues:(NSDictionary *)keyedValues ofItemWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
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
                                     client:client];
    }
    
    [client protocolDidFinish:nil];
    return nil;
}

#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client completionHandler:(void (^)(NSError *))handler;
{
    if (self = [self initWithRequest:request client:client])
    {
        [self retain];  // until finished
        _completionHandler = [handler copy];
    }
    
    return self;
}

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client dataHandler:(void (^)(NSData *))dataBlock completionHandler:(void (^)(NSError *))handler
{
    if (self = [self initWithRequest:request client:client completionHandler:handler])
    {
        _dataBlock = [dataBlock copy];
    }
    return self;
}

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock completionHandler:(void (^)(NSError *))handler
{
    if (self = [self initWithRequest:request client:client completionHandler:handler])
    {
        _progressBlock = [progressBlock copy];
    }
    return self;
}

- (void)start;
{
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

- (void)endWithError:(NSError *)error;
{
    _completionHandler(error);
    [_handle release]; _handle = nil;
    [self release];
}

- (void)stop;
{
    [_handle cancel];
}

- (void)dealloc;
{
    [_handle release];
    [_completionHandler release];
    [_dataBlock release];
    [_progressBlock release];
    
    [super dealloc];
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

#pragma mark CURLHandleDelegate

- (void)handle:(CURLHandle *)handle didFailWithError:(NSError *)error;
{
    if (!error) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil];
    [self endWithError:error];
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
    [self endWithError:nil];
}

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type;
{
    // Don't want to include password in transcripts usually!
    if (type == CURLINFO_HEADER_OUT &&
        [string hasPrefix:@"PASS"] &&
        ![[NSUserDefaults standardUserDefaults] boolForKey:@"AllowPasswordToBeLogged"])
    {
        string = @"PASS ####";
    }
    
    [[self client] protocol:self appendString:string toTranscript:(type == CURLINFO_HEADER_IN ? CKTranscriptReceived : CKTranscriptSent)];
}

#pragma mark NSURLAuthenticationChallengeSender

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    _handle = [[CURLHandle alloc] initWithRequest:[self request]
                                       credential:credential
                                         delegate:self];
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

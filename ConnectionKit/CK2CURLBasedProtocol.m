//
//  CK2CURLBasedProtocol.m
//  Connection
//
//  Created by Mike on 06/12/2012.
//
//

#import "CK2CURLBasedProtocol.h"

#import <CurlHandle/NSURLRequest+CURLHandle.h>
#import <sys/dirent.h>

#import <AppKit/AppKit.h>   // for NSImage


@implementation CK2CURLBasedProtocol

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client completionHandler:(void (^)(NSError *))handler;
{
    if (self = [self initWithRequest:request client:client])
    {
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

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *))handler
{
    if (self = [self initWithRequest:request client:client completionHandler:handler])
    {
        _progressBlock = [progressBlock copy];
    }
    return self;
}

- (id)initWithCustomCommands:(NSArray *)commands request:(NSURLRequest *)sourceRequest createIntermediateDirectories:(BOOL)createIntermediates client:(id <CK2ProtocolClient>)client completionHandler:(void (^)(NSError *error))handler;
{
    // Navigate to the directory
    // @"HEAD" => CURLOPT_NOBODY, which stops libcurl from trying to list the directory's contents
    // If the connection is already at that directory then curl wisely does nothing
    NSMutableURLRequest *request = [sourceRequest mutableCopy];
    [request setHTTPMethod:@"HEAD"];
    [request curl_setCreateIntermediateDirectories:createIntermediates];
    
    // Custom commands once we're in the correct directory
    // CURLOPT_PREQUOTE does much the same thing, but sometimes runs the command twice in my testing
    [request curl_setPostTransferCommands:commands];
    
    self = [self initWithRequest:request client:client dataHandler:nil completionHandler:handler];
    
    [request release];
    return self;
}

#pragma mark Directory Enumeration

- (BOOL)shouldEnumerateFilename:(NSString *)name options:(NSDirectoryEnumerationOptions)mask;
{
    // SFTP and some FTP servers report . and .. which we don't care about
    if ([name isEqualToString:@"."] || [name isEqualToString:@".."])
    {
        return NO;
    }
    
    if ((mask & NSDirectoryEnumerationSkipsHiddenFiles) && [name hasPrefix:@"."]) return NO;
    
    return YES;
}

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
            // Correct relative paths if we can
            NSURL *directoryURL = [self.class URLByReplacingUserInfoInURL:request.URL withUser:_user];
            NSString *directoryPath = [self.class pathOfURLRelativeToHomeDirectory:directoryURL];
            
            
            NSURL *home = [self.class homeDirectoryURLForServerAtURL:directoryURL];
            if (home && ![directoryPath isAbsolutePath])
            {
                if (directoryPath.length && ![directoryPath hasSuffix:@"/"]) directoryPath = [directoryPath stringByAppendingString:@"/"];
                directoryURL = [home URLByAppendingPathComponent:directoryPath];
            }
            
            
            // Report directory itself
            if (mask & CK2DirectoryEnumerationIncludesDirectory)
            {
                [self.client protocol:self didDiscoverItemAtURL:directoryURL];
            }

            
            // Process the data to make a directory listing
            while (1)
            {
                CFDictionaryRef parsedDict = NULL;
                CFIndex bytesConsumed = CFFTPCreateParsedResourceListing(NULL,
                                                                         [totalData bytes], [totalData length],
                                                                         &parsedDict);
                
                if (bytesConsumed > 0)
                {
                    [totalData replaceBytesInRange:NSMakeRange(0, bytesConsumed) withBytes:NULL length:0];
                    
                    // Make sure CFFTPCreateParsedResourceListing was able to properly
                    // parse the incoming data
                    if (parsedDict)
                    {
                        NSString *name = CFDictionaryGetValue(parsedDict, kCFFTPResourceName);
                        
                        if ([self shouldEnumerateFilename:name options:mask])
                        {
                            NSNumber *type = CFDictionaryGetValue(parsedDict, kCFFTPResourceType);
                            BOOL isDirectory = [type intValue] == DT_DIR;
                            
                            NSURL *aURL = [directoryURL URLByAppendingPathComponent:name isDirectory:isDirectory];
                            
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
                                    [CK2FileManager setTemporaryResourceValue:CFDictionaryGetValue(parsedDict, kCFFTPResourceModDate) forKey:aKey inURL:aURL];
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
                                    
                                    [CK2FileManager setTemporaryResourceValue:typeValue forKey:aKey inURL:aURL];
                                }
                                else if ([aKey isEqualToString:NSURLFileSecurityKey])
                                {
                                    CFFileSecurityRef security = CFFileSecurityCreate(NULL);
                                    
                                    NSNumber *mode = CFDictionaryGetValue(parsedDict, kCFFTPResourceMode);
                                    if (CFFileSecuritySetMode(security, mode.unsignedShortValue))
                                    {
                                        [CK2FileManager setTemporaryResourceValue:(NSFileSecurity *)security forKey:aKey inURL:aURL];
                                    }
                                    
                                    CFRelease(security);
                                }
                                else if ([aKey isEqualToString:NSURLIsDirectoryKey])
                                {
                                    [CK2FileManager setTemporaryResourceValue:@(isDirectory) forKey:aKey inURL:aURL];
                                }
                                else if ([aKey isEqualToString:NSURLIsHiddenKey])
                                {
                                    [CK2FileManager setTemporaryResourceValue:@([name hasPrefix:@"."]) forKey:aKey inURL:aURL];
                                }
                                else if ([aKey isEqualToString:NSURLIsRegularFileKey])
                                {
                                    [CK2FileManager setTemporaryResourceValue:@([type intValue] == DT_REG) forKey:aKey inURL:aURL];
                                }
                                else if ([aKey isEqualToString:NSURLIsSymbolicLinkKey])
                                {
                                    [CK2FileManager setTemporaryResourceValue:@([type intValue] == DT_LNK) forKey:aKey inURL:aURL];
                                }
                                else if ([aKey isEqualToString:NSURLLocalizedTypeDescriptionKey])
                                {
                                    // Could guess from extension
                                }
                                else if ([aKey isEqualToString:NSURLNameKey])
                                {
                                    [CK2FileManager setTemporaryResourceValue:name forKey:aKey inURL:aURL];
                                }
                                else if ([aKey isEqualToString:NSURLParentDirectoryURLKey])
                                {
                                    [CK2FileManager setTemporaryResourceValue:directoryPath forKey:NSURLParentDirectoryURLKey inURL:aURL];
                                }
                                else if ([aKey isEqualToString:NSURLTypeIdentifierKey])
                                {
                                    // Guess from symlink, extension, and directory
                                    if ([type intValue] == DT_LNK)
                                    {
                                        [CK2FileManager setTemporaryResourceValue:(NSString *)kUTTypeSymLink forKey:aKey inURL:aURL];
                                    }
                                    else
                                    {
                                        NSString *extension = [name pathExtension];
                                        if ([extension length])
                                        {
                                            CFStringRef type = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                                                                     (CFStringRef)extension,
                                                                                                     (isDirectory ? kUTTypeDirectory : kUTTypeData));
                                            
                                            [CK2FileManager setTemporaryResourceValue:(NSString *)type forKey:aKey inURL:aURL];
                                            CFRelease(type);
                                        }
                                        else
                                        {
                                            [CK2FileManager setTemporaryResourceValue:(NSString *)kUTTypeData forKey:aKey inURL:aURL];
                                        }
                                    }
                                }
                                else if ([aKey isEqualToString:NSURLFileSizeKey])
                                {
                                    [CK2FileManager setTemporaryResourceValue:CFDictionaryGetValue(parsedDict, kCFFTPResourceSize) forKey:aKey inURL:aURL];
                                }
                                else if ([aKey isEqualToString:CK2URLSymbolicLinkDestinationKey])
                                {
                                    NSString *path = CFDictionaryGetValue(parsedDict, kCFFTPResourceLink);
                                    if ([path length])
                                    {
                                        // Servers in my experience hand include a trailing slash to indicate if the target is a directory
                                        // Could generate a CK2RemoteURL instead so as to explicitly mark it as a directory, but that seems unecessary for now
                                        // According to the original CKConnectionOpenPanel source, some servers use a backslash instead. I don't know what though – Windows based ones? If so, do they use backslashes for all path components?
                                        [CK2FileManager setTemporaryResourceValue:[self.class URLWithPath:path relativeToURL:directoryURL] forKey:aKey inURL:aURL];
                                    }
                                }
                            }
                            
                            [self.client protocol:self didDiscoverItemAtURL:aURL];
                        }
                        
                        CFRelease(parsedDict);
                    }
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

    [totalData release];
    [request release];
    return self;
}

+ (NSURL *)URLByReplacingUserInfoInURL:(NSURL *)aURL withUser:(NSString *)nsUser;
{
    // Canonicalize URLs by making sure username is included. Strip out password in the process
    CFStringRef user = (CFStringRef)nsUser;
    if (user)
    {
        // -stringByAddingPercentEscapesUsingEncoding: doesn't cover things like the @ symbol, so drop down CoreFoundation
        user = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                       user,
                                                       NULL,
                                                       CFSTR(":/?#[]@!$&'()*+,;="),   // going by RFC3986
                                                       kCFStringEncodingUTF8);
    }
    
    CFIndex length = CFURLGetBytes((CFURLRef)aURL, NULL, 0);
    NSMutableData *data = [[NSMutableData alloc] initWithLength:length];
    CFURLGetBytes((CFURLRef)aURL, [data mutableBytes], length);
    
    CFRange authSeparatorsRange;
    CFRange authRange = CFURLGetByteRangeForComponent((CFURLRef)aURL, kCFURLComponentUserInfo, &authSeparatorsRange);
    
    if (authRange.location == kCFNotFound)
    {
        NSData *replacement = [[(NSString *)user stringByAppendingString:@"@"] dataUsingEncoding:NSUTF8StringEncoding];
        CFDataReplaceBytes((CFMutableDataRef)data, authSeparatorsRange, [replacement bytes], replacement.length);
    }
    else
    {
        NSData *replacement = [(NSString *)user dataUsingEncoding:NSUTF8StringEncoding];
        CFDataReplaceBytes((CFMutableDataRef)data, authRange, [replacement bytes], replacement.length);
    }
    
    aURL = NSMakeCollectable(CFURLCreateWithBytes(NULL, [data bytes], data.length, kCFStringEncodingUTF8, NULL));
    
    [data release];
    if (user) CFRelease(user);
    
    return [aURL autorelease];
}

#pragma mark Dealloc

- (void)dealloc;
{
    [_handle release];
    [_user release];
    [_completionHandler release];
    [_dataBlock release];
    [_progressBlock release];
    
    [super dealloc];
}

#pragma mark Loading

- (void)start; { return [self startWithCredential:nil]; }

- (void)startWithCredential:(NSURLCredential *)credential;
{
    _user = [credential.user copy];
    
    NSURLRequest* request = [self request];
    CURLMulti* multi = nil;
    if ([request respondsToSelector:@selector(ck2_multi)])  // should only be a testing/debugging feature
    {
        multi = [request performSelector:@selector(ck2_multi)]; // typically this is nil, meaning use the default, but we can override it for test purposes
    }

    if ([[self class] usesMultiHandle])
    {
        _handle = [[CURLHandle alloc] initWithRequest:request
                                           credential:credential
                                             delegate:self
                                                multi:multi];
    }
    else
    {
        // Create the queue & handle for whole app to share
        static CURLHandle *handle;
        static dispatch_queue_t queue;
        
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            
            handle = [[CURLHandle alloc] init];
            queue = dispatch_queue_create("com.karelia.connection.fallback-curlhandle", NULL);
        });

        CURLHandle* handleToUse;
        if (multi) // although we're not using the multi, we use it being set here as a signal to use a new handle for this transaction
        {
            handleToUse = [[[CURLHandle alloc] init] autorelease];
        }
        else
        {
            handleToUse = handle;
        }

        // Let the work commence!
        dispatch_async(queue, ^{
            _handle = [handleToUse retain];
            [_handle sendSynchronousRequest:self.request credential:credential delegate:self];
        });
    }
}

- (void)reportToProtocolWithError:(NSError*)error
{
    if (error)
    {
        [[self client] protocol:self didFailWithError:error];
    }
    else
    {
        [[self client] protocolDidFinish:self];
    }
}

- (void)endWithError:(NSError *)error;
{
    // Update cache
    if (!error)
    {
        [self updateHomeDirectoryStore];
    }

    if (_completionHandler)
    {
        _completionHandler(error);
        [_completionHandler release]; _completionHandler = nil;
    }
    else
    {
        [self reportToProtocolWithError:error];
    }

    [_handle release]; _handle = nil;
}

- (NSError*)translateStandardErrors:(NSError*)error
{
    if (error)
    {
        if ([error code] == CURLE_QUOTE_ERROR && [[error domain] isEqualToString:CURLcodeErrorDomain])
        {
            NSUInteger responseCode = [error curlResponseCode];
            if (responseCode == 550)
            {
                // Nicer Cocoa-style error. Can't definitely tell the difference between the file not existing, and permission denied, sadly
                error = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileWriteUnknownError
                                        userInfo:@{ NSUnderlyingErrorKey : error }];
            }
        }
    }

    return error;
}

- (void)stop;
{
    [_handle cancel];
}

#pragma mark URLs

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
            CFStringRef lastComponent = CFURLCopyLastPathComponent((CFURLRef)url);    // keeps %2F kinda intact as a regular slash
            
            url = [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:(NSString *)lastComponent isDirectory:directory];
            // any slash from %2F will go back in to give a URL containing an extra slash, which should be good enough for libcurl to handle
            
            CFRelease(lastComponent);
        }
    }
    
    NSMutableURLRequest *result = [request mutableCopy];
    [result setURL:url];
    return result;
}

#pragma mark Home Directory Store

+ (BOOL)isHomeDirectoryAtURL:(NSURL *)url;
{
    NSURL *home = [self homeDirectoryURLForServerAtURL:url];
    BOOL result = [[self pathOfURLRelativeToHomeDirectory:url] isEqualToString:[self pathOfURLRelativeToHomeDirectory:home]];
    return result;
}

+ (NSURL *)homeDirectoryURLForServerAtURL:(NSURL *)hostURL;
{
    NSString *host = [[NSURL URLWithString:@"/" relativeToURL:hostURL] absoluteString].lowercaseString;
    
    NSMutableDictionary *store = [self homeURLsByHostURL];
    @synchronized (store)
    {
        return [store objectForKey:host];
    }
}

- (void)updateHomeDirectoryStore;
{
    NSString *homeDirectoryPath = [_handle initialFTPPath];
    
    if ([homeDirectoryPath isAbsolutePath])
    {
        if (homeDirectoryPath.length > 1 && ![homeDirectoryPath hasSuffix:@"/"])    // ensure it's a directory path
        {
            homeDirectoryPath = [homeDirectoryPath stringByAppendingString:@"/"];
        }
        
        NSURL *homeDirectoryURL = [self.class URLWithPath:homeDirectoryPath relativeToURL:self.request.URL].absoluteURL;
        
        homeDirectoryURL = [self.class URLByReplacingUserInfoInURL:homeDirectoryURL withUser:_user];    // include username
        NSString *host = [[NSURL URLWithString:@"/" relativeToURL:homeDirectoryURL] absoluteString].lowercaseString;
        
        NSMutableDictionary *store = [self.class homeURLsByHostURL];
        @synchronized (store)
        {
            [store setObject:homeDirectoryURL forKey:host];
        }
    }
}

+ (NSMutableDictionary *)homeURLsByHostURL;
{
    static NSMutableDictionary *sHomeURLsByHostURL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sHomeURLsByHostURL = [[NSMutableDictionary alloc] initWithCapacity:1];
    });
    
    return sHomeURLsByHostURL;
}

#pragma mark CURLHandleDelegate

- (void)handle:(CURLHandle *)handle didFailWithError:(NSError *)error;
{
    if (!error)
    {
        error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil];
    }
    
    [self endWithError:error];
}

- (void)handle:(CURLHandle *)handle didReceiveData:(NSData *)data;
{
    [self updateHomeDirectoryStore];    // Make sure is updated before parsing of directory listing
    if (_dataBlock) _dataBlock(data);
}

- (void)handle:(CURLHandle *)handle willSendBodyDataOfLength:(NSUInteger)bytesWritten
{
    if (_progressBlock) _progressBlock(bytesWritten, 0);
}

- (void)handleDidFinish:(CURLHandle *)handle;
{
    [self endWithError:nil];
}

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type;
{
    CKTranscriptType ckType;
    switch (type)
    {
        case CURLINFO_HEADER_IN:
            ckType = CKTranscriptReceived;
            break;

        case CURLINFO_HEADER_OUT:
            ckType = CKTranscriptSent;
            break;

        case CURLINFO_DATA_IN:
        case CURLINFO_DATA_OUT:
        case CURLINFO_SSL_DATA_IN:
        case CURLINFO_SSL_DATA_OUT:
            ckType = CKTranscriptData;
            break;

        case CURLINFO_TEXT:
        default:
            ckType = CKTranscriptInfo;
            break;
    }

    [[self client] protocol:self appendString:string toTranscript:ckType];
}

#pragma mark NSURLAuthenticationChallengeSender

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // Swap out existing handler for one that retries after an auth failure. Stores credential if requested upon success
    void (^oldHandler)(NSError *) = _completionHandler;
    
    _completionHandler = ^(NSError *error) {
        
        if ([error code] == NSURLErrorUserAuthenticationRequired && [[error domain] isEqualToString:NSURLErrorDomain])
        {
            // Swap back to the original handler...
            void (^thisBlock)(NSError *) = _completionHandler;
            _completionHandler = [oldHandler copy];
            
            // ...then retry auth
            NSURLAuthenticationChallenge *newChallenge = [[NSURLAuthenticationChallenge alloc]
                                                          initWithProtectionSpace:[challenge protectionSpace]
                                                          proposedCredential:credential
                                                          previousFailureCount:([challenge previousFailureCount] + 1)
                                                          failureResponse:nil
                                                          error:error
                                                          sender:self];
            
            [[self client] protocol:self didReceiveAuthenticationChallenge:newChallenge];
            [newChallenge release];
            
            [thisBlock release];
        }
        else
        {
            if (!error)
            {
                [[NSURLCredentialStorage sharedCredentialStorage] setCredential:credential forProtectionSpace:challenge.protectionSpace];
            }
            
            if (oldHandler)
            {
                oldHandler(error);
            }
            else
            {
                if (error)
                {
                    [[self client] protocol:self didFailWithError:error];
                }
                else
                {
                    [[self client] protocolDidFinish:self];
                }
            }
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

#pragma mark Customization

+ (BOOL)usesMultiHandle; { return YES; }

@end

//
//  CK2CURLBasedProtocol.m
//  Connection
//
//  Created by Mike on 06/12/2012.
//
//

#import "CK2CURLBasedProtocol.h"

#import "CK2FileManager.h"
#import "CK2RemoteURL.h"

#import <CurlHandle/NSURLRequest+CURLHandle.h>
#import <sys/dirent.h>


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

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock completionHandler:(void (^)(NSError *))handler
{
    if (self = [self initWithRequest:request client:client completionHandler:handler])
    {
        _progressBlock = [progressBlock copy];
    }
    return self;
}

- (id)initWithCustomCommands:(NSArray *)commands request:(NSURLRequest *)childRequest createIntermediateDirectories:(BOOL)createIntermediates client:(id <CK2ProtocolClient>)client completionHandler:(void (^)(NSError *error))handler;
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
    
    self = [self initWithRequest:request client:client dataHandler:nil completionHandler:handler];
    
    [request release];
    return self;
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
                    [totalData replaceBytesInRange:NSMakeRange(0, bytesConsumed) withBytes:NULL length:0];
                    
                    // Make sure CFFTPCreateParsedResourceListing was able to properly
                    // parse the incoming data
                    if (parsedDict)
                    {
                        NSString *name = CFDictionaryGetValue(parsedDict, kCFFTPResourceName);
                        
                        // SFTP and some FTP servers report . and .. which we don't care about
                        if ([name isEqualToString:@"."] || [name isEqualToString:@".."])
                        {
                            CFRelease(parsedDict);
                            continue;
                        }
                        
                        if (!((mask & NSDirectoryEnumerationSkipsHiddenFiles) && [name hasPrefix:@"."]))
                        {
                            NSNumber *type = CFDictionaryGetValue(parsedDict, kCFFTPResourceType);
                            BOOL isDirectory = [type intValue] == DT_DIR;
                            NSURL *nsURL = [url URLByAppendingPathComponent:name isDirectory:isDirectory];
                            
                            // Switch over to custom URL class that actually accepts temp values. rdar://problem/11069131
                            CK2RemoteURL *aURL = [[CK2RemoteURL alloc] initWithString:[nsURL relativeString] relativeToURL:[nsURL baseURL]];
                            
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

- (void)dealloc;
{
    [_handle release];
    [_completionHandler release];
    [_dataBlock release];
    [_progressBlock release];
    
    [super dealloc];
}

#pragma mark Loading

- (void)start; { return [self startWithCredential:nil]; }

- (void)startWithCredential:(NSURLCredential *)credential;
{
    _handle = [[CURLHandle alloc] initWithRequest:[self request]
                                       credential:credential
                                         delegate:self];
}

- (void)endWithError:(NSError *)error;
{
    if (_completionHandler)
    {
        _completionHandler(error);
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
    
    [_handle release]; _handle = nil;
}

- (void)stop;
{
    [_handle cancel];
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
    [[self client] protocol:self appendString:string toTranscript:(type == CURLINFO_HEADER_IN ? CKTranscriptReceived : CKTranscriptSent)];
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

@end

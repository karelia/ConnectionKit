//
//  CK2CURLBasedProtocol.m
//  Connection
//
//  Created by Mike on 06/12/2012.
//
//

#import "CK2CURLBasedProtocol.h"

#import <CURLHandle/CURLHandle.h>
#import <sys/dirent.h>

#import <AppKit/AppKit.h>   // for NSImage


@interface CURLTransfer (Testing)
- (id)initWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential delegate:(id<CURLTransferDelegate>)delegate delegateQueue:(NSOperationQueue *)queue multi:(CURLMultiHandle *)multi;
@end


@implementation CK2CURLBasedProtocol

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client completionHandler:(void (^)(NSError *))handler;
{
    if (self = [self initWithRequest:request client:client])
    {
        [self pushCompletionHandler:^(NSError *error) {
            
            // Update cache
            if (!error)
            {
                [self updateHomeDirectoryStore];
            }
            
            // Report the completion to handler or protocol
            if (handler)
            {
                handler(error);
            }
            else
            {
                [self reportToProtocolWithError:error];
            }
            
            // Clean up transfer
            [_transfer release]; _transfer = nil;
        }];
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

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request size:(int64_t)size withIntermediateDirectories:(BOOL)createIntermediates client:(id<CK2ProtocolClient>)client completionHandler:(void (^)(NSError *error))handler;
{
    if ([request curl_createIntermediateDirectories] != createIntermediates)
    {
        NSMutableURLRequest *mutableRequest = [[request mutableCopy] autorelease];
        [mutableRequest curl_setCreateIntermediateDirectories:createIntermediates];
        request = mutableRequest;
    }
    
    if (self = [self initWithRequest:request client:client completionHandler:handler])
    {
        _totalBytesExpectedToWrite = size;
    }
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

- (NSError*)processData:(NSMutableData*)data request:(NSURLRequest *)request url:(NSURL*)directoryURL path:(NSString*)directoryPath keys:(NSArray*)keys options:(NSDirectoryEnumerationOptions)mask
{
    NSString *listing = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (listing)
    {
        [self.client protocol:self appendStringToTranscript:listing isCommand:NO];
    }
    else
    {
        listing = [[NSString alloc] initWithFormat:@"Unable to stringify listing: %@", data];
        [self.client protocol:self appendStringToTranscript:listing isCommand:NO];
    }
    [listing release];
    
    
    NSError* result = nil;

    // Process the data to make a directory listing
    while (1)
    {
        CFDictionaryRef parsedDict = NULL;
        CFIndex bytesConsumed = CFFTPCreateParsedResourceListing(NULL,
                                                                 [data bytes], [data length],
                                                                 &parsedDict);

        if (bytesConsumed > 0)
        {
            [data replaceBytesInRange:NSMakeRange(0, bytesConsumed) withBytes:NULL length:0];

            // Make sure CFFTPCreateParsedResourceListing was able to properly
            // parse the incoming data
            if (parsedDict)
            {
                NSString *name = [self pathForKey:kCFFTPResourceName inDictionary:parsedDict];

                if ([self shouldEnumerateFilename:name options:mask])
                {
                    NSNumber *type = CFDictionaryGetValue(parsedDict, kCFFTPResourceType);
                    BOOL isDirectory = [type intValue] == DT_DIR;

                    NSURL *aURL = [directoryURL URLByAppendingPathComponent:name];
                    if (isDirectory && !CFURLHasDirectoryPath((CFURLRef)aURL))
                    {
                        aURL = [aURL URLByAppendingPathComponent:@""];  // http://www.mikeabdullah.net/guaranteeing-directory-urls.html
                    }

                    // Fill in requested keys as best we can
                    NSArray *keysToFill = (keys ? keys : self.class.defaultPropertyKeys);

                    for (NSString *aKey in keysToFill)
                    {
                        if ([aKey isEqualToString:NSURLContentModificationDateKey])
                        {
                            [CK2FileManager setTemporaryResourceValue:CFDictionaryGetValue(parsedDict, kCFFTPResourceModDate) forKey:aKey inURL:aURL];
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
                            NSString *path = [self pathForKey:kCFFTPResourceLink inDictionary:parsedDict];
                            if ([path length])
                            {
                                // Servers in my experience hand include a trailing slash to indicate if the target is a directory
                                // Could generate a CK2RemoteURL instead so as to explicitly mark it as a directory, but that seems unecessary for now
                                // According to the original CKConnectionOpenPanel source, some servers use a backslash instead. I don't know what though – Windows based ones? If so, do they use backslashes for all path components?
                                [CK2FileManager setTemporaryResourceValue:[self.class URLWithPath:path relativeToURL:directoryURL] forKey:aKey inURL:aURL];
                            }
                        }

                        // Trying to access a constant not available on an old platform will crash. Runtime check seems to be our best bet
                        else if (NSFoundationVersionNumber >= NSFoundationVersionNumber10_6)
                        {
                            if ([aKey isEqualToString:NSURLFileResourceTypeKey])
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

            result = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotParseResponse userInfo:userInfo];
            [userInfo release];
            break;
        }
        else
        {
            break;
        }
    }

    return result;
}

// Retrieves the path/filename for a given key, and then tries to take into account tricky encoding issues
// https://github.com/karelia/ConnectionKit/issues/41
- (NSString *)pathForKey:(CFStringRef)key inDictionary:(CFDictionaryRef)dictionary;
{
    NSString *result = CFDictionaryGetValue(dictionary, key);
    
    // For strings which fall outside of ASCII, hope that they're UTF-8
    if (![result canBeConvertedToEncoding:NSASCIIStringEncoding])
    {
        NSData *source = [result dataUsingEncoding:NSMacOSRomanStringEncoding];
        // technically, this is a little dodgy. -dataUsingEncoding: could generate some sort of BOM, but I don't believe MacRoman has such a concept so we're safe for now
        
        if (source)
        {
            NSString *utf8 = [[NSString alloc] initWithData:source encoding:NSUTF8StringEncoding];
            if (utf8)
            {
                result = [utf8 autorelease];
            }
        }
    }
    
    return result;
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
            [client protocol:self didCompleteWithError:error];
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
            NSError* error = [self processData:totalData request:request url:directoryURL path:directoryPath keys:keys options:mask];
            [self.client protocol:self didCompleteWithError:error];
        }
    }];

    [totalData release];
    [request release];
    return self;
}

+ (NSArray *)defaultPropertyKeys;
{
    NSArray *result = @[NSURLContentModificationDateKey,
                        NSURLIsDirectoryKey,
                        NSURLIsRegularFileKey,
                        NSURLIsSymbolicLinkKey,
                        NSURLNameKey,
                        NSURLFileSizeKey,
                        CK2URLSymbolicLinkDestinationKey];
    
    if (NSFoundationVersionNumber >= NSFoundationVersionNumber10_6)
    {
        result = [result arrayByAddingObjectsFromArray:@[
                  NSURLFileResourceTypeKey,
                  NSURLFileSecurityKey]];
    }
    
    return result;
}

#pragma mark Dealloc

- (void)dealloc;
{
    [_transfer release];
    [_user release];
    [_completionHandler release];
    [_dataBlock release];
    
    [super dealloc];
}

#pragma mark Loading

- (void)start; { return [self startWithRequest:self.request credential:nil]; }

- (void)startWithProtectionSpace:(NSURLProtectionSpace *)protectionSpace;
{
    NSURLAuthenticationChallenge *challenge = [[NSURLAuthenticationChallenge alloc]
                                               initWithProtectionSpace:protectionSpace
                                               proposedCredential:nil
                                               previousFailureCount:0
                                               failureResponse:nil
                                               error:nil
                                               sender:nil];
    
    [self sendAuthChallenge:challenge];
    [challenge release];
}

- (void)sendAuthChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSParameterAssert(challenge);
    
    [self.client protocol:self didReceiveChallenge:challenge completionHandler:^(CK2AuthChallengeDisposition disposition, NSURLCredential *credential) {
        
        switch (disposition)
        {
            case CK2AuthChallengePerformDefaultHandling:
                credential = challenge.proposedCredential;
                
            case CK2AuthChallengeUseCredential:
            {
                // Swap out existing handler for one that retries after an auth failure. Stores credential if requested upon success
                [self pushCompletionHandler:^(NSError *error) {
                    
                    if (error.code == NSURLErrorUserAuthenticationRequired && [error.domain isEqualToString:NSURLErrorDomain])
                    {
                        // Retry auth
                        NSURLAuthenticationChallenge *newChallenge = [[NSURLAuthenticationChallenge alloc]
                                                                      initWithProtectionSpace:challenge.protectionSpace
                                                                      proposedCredential:credential
                                                                      previousFailureCount:(challenge.previousFailureCount + 1)
                                                                      failureResponse:nil
                                                                      error:error
                                                                      sender:nil];
                        
                        [self sendAuthChallenge:newChallenge];
                        [newChallenge release];
                    }
                    else
                    {
                        if (!error)
                        {
                            [[NSURLCredentialStorage sharedCredentialStorage] setCredential:credential forProtectionSpace:challenge.protectionSpace];
                        }
                        
                        [self popCompletionHandlerByExecutingWithError:error];
                    }
                }];
                
                [self startWithRequest:self.request credential:credential];
                break;
            }
            default:
            {
                [self.client protocol:self didCompleteWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                                                    code:NSURLErrorUserCancelledAuthentication
                                                                                userInfo:nil]];
            }
        }
    }];
}

- (void)startWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential;
{
    _user = [credential.user copy];
    
    request = [self.client protocol:self willSendRequest:request redirectResponse:nil];
    
    CURLMultiHandle* multi = nil;
    if ([request respondsToSelector:@selector(ck2_multi)])  // should only be a testing/debugging feature
    {
        multi = [request performSelector:@selector(ck2_multi)]; // typically this is nil, meaning use the default, but we can override it for test purposes
    }
    
    _totalBytesWritten = 0;

    if ([[self class] usesMultiHandle])
    {
        if (multi)
        {
            _transfer = [[CURLTransfer alloc] initWithRequest:request
                                                 credential:credential
                                                   delegate:self
                                              delegateQueue:nil
                                                      multi:multi];
        }
        else
        {
            _transfer = [[CURLTransfer alloc] initWithRequest:request credential:credential delegate:self delegateQueue:nil];
        }
    }
    else
    {
        // Create the queue & handle for whole app to share
        static CURLTransfer *transfer;
        static dispatch_queue_t queue;
        
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            
            transfer = [[CURLTransfer alloc] init];
            queue = dispatch_queue_create("com.karelia.connection.fallback-CURLTransfer", NULL);
        });

        CURLTransfer* transferToUse;
        if (multi) // although we're not using the multi, we use it being set here as a signal to use a new handle for this transaction
        {
            transferToUse = [[[CURLTransfer alloc] init] autorelease];
        }
        else
        {
            transferToUse = transfer;
        }

        // Let the work commence!
        dispatch_async(queue, ^{
            
            if (_cancelled) return;
            
            _transfer = [transferToUse retain];
            [_transfer sendSynchronousRequest:request credential:credential delegate:self];
        });
    }
}

- (void)reportToProtocolWithError:(NSError*)error
{
    [[self client] protocol:self didCompleteWithError:error];
}

- (void)stop;
{
    // Mark as cancelled before actually cancelling so _cancelled has to be YES for any other transfers on the queue
    _cancelled = YES;
    [_transfer cancel];
}

#pragma mark Managing the Completion Handler

/*  This code is devious and perhaps even evil. Manages a "stack" of completion
 *  handlers by actually only having a single block. When the block runs, it
 *  replaces itself with the next one down the stack.
 */

- (void)pushCompletionHandler:(void (^)(NSError*))block;
{
    NSParameterAssert(block);
    
    id previousHandler = _completionHandler;
    
    _completionHandler = ^(NSError *error) {
        
        // Put the old handler back, then execute what was actually requested of us
        [_completionHandler release]; _completionHandler = previousHandler;
        block(error);
    };
    _completionHandler = [_completionHandler copy];
}

- (void)popCompletionHandlerByExecutingWithError:(NSError *)error;
{
    // If the block is nil, that means the entire stack of handlers has already been popped, which should be a programmer error
    id keepAlive = _completionHandler;
    [keepAlive retain];
    _completionHandler(error);
    [keepAlive release];
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
            
            url = [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:(NSString *)lastComponent];
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
    NSString *homeDirectoryPath = [_transfer initialFTPPath];
    
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

#pragma mark CURLTransferDelegate

- (void)transfer:(CURLTransfer *)transfer didReceiveData:(NSData *)data;
{
    [self updateHomeDirectoryStore];    // Make sure is updated before parsing of directory listing
    if (_dataBlock) _dataBlock(data);
}

- (void)transfer:(CURLTransfer *)transfer willSendBodyDataOfLength:(NSUInteger)bytesWritten
{
    _totalBytesWritten += bytesWritten;
    
    [self.client protocol:self
          didSendBodyData:bytesWritten
           totalBytesSent:_totalBytesWritten
 totalBytesExpectedToSend:_totalBytesExpectedToWrite];
}

- (void)transfer:(CURLTransfer *)transfer didCompleteWithError:(NSError *)error;
{
    [self popCompletionHandlerByExecutingWithError:error];
}

- (void)transfer:(CURLTransfer *)transfer didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type;
{
    switch (type)
    {
        case CURLINFO_HEADER_IN:
            [self.client protocol:self appendStringToTranscript:string isCommand:NO];
            break;

        case CURLINFO_HEADER_OUT:
            [self.client protocol:self appendStringToTranscript:string isCommand:YES];
            break;
            
        default:
            break;
    }
}

#pragma mark Customization

// Much to my annoyance, async backend doesn't seem to be working right at the moment
+ (BOOL)usesMultiHandle; { return NO; }

@end

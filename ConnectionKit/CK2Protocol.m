//
//  CK2Protocol
//  Connection
//
//  Created by Mike on 11/10/2012.
//
//

#import "CK2Protocol.h"

#import "CK2FTPProtocol.h"
#import "CK2SFTPProtocol.h"
#import "CK2FileProtocol.h"
#import "CK2WebDAVProtocol.h"

@implementation CK2Protocol

#pragma mark Serialization

+ (dispatch_queue_t)queue;
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("CK2FileTransferSystem", NULL);
        
        // Register built-in protocols too
        sRegisteredProtocols = [[NSMutableArray alloc] initWithObjects:[CK2FileProtocol class], [CK2SFTPProtocol class], [CK2FTPProtocol class], [CK2WebDAVProtocol class], nil];
    });
    
    return queue;
}

#pragma mark For Subclasses to Implement

+ (BOOL)canHandleURL:(NSURL *)url;
{
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

- (id)initForEnumeratingDirectoryWithRequest:(NSURLRequest *)request includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask client:(id<CK2ProtocolClient>)client;
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)initForCreatingDirectoryWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client;
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request size:(int64_t)size withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client;
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)initForRemovingItemWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)initForRenamingItemWithRequest:(NSURLRequest *)request newName:(NSString *)newName client:(id<CK2ProtocolClient>)client
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)initForSettingAttributes:(NSDictionary *)keyedValues ofItemWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (void)start;
{
    [self doesNotRecognizeSelector:_cmd];
}

- (void)stop;
{
    [self doesNotRecognizeSelector:_cmd];
}

#pragma mark For Subclasses to Customize

+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
{
    CFStringRef encodedPath = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                      (CFStringRef)path,
                                                                      NULL,
                                                                      CFSTR(";?#"),
                                                                      kCFStringEncodingUTF8);
    
    NSURL* result = [NSURL URLWithString:(NSString *)encodedPath relativeToURL:baseURL];
    CFRelease(encodedPath);

    return result;
}

+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;
{
    return [URL path];
}

+ (BOOL)isHomeDirectoryAtURL:(NSURL *)url;
{
    return [[self pathOfURLRelativeToHomeDirectory:url] isEqualToString:@""];
}

#pragma mark For Subclasses to Use

- (id)initWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    if (self = [self init])
    {
        _request = [request copy];
        _client = [client retain];
    }
    return self;
}

- (void)dealloc
{
    [_request release];
    [_client release];
    
    [super dealloc];
}

- (NSError*)standardCouldntWriteErrorWithUnderlyingError:(NSError *)error
{
    NSDictionary* info = error ? @{NSUnderlyingErrorKey : error} : nil;
    NSError* result = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:info];

    return result;
}

- (NSError*)standardFileNotFoundErrorWithUnderlyingError:(NSError *)error
{
    NSDictionary* info = error ? @{NSUnderlyingErrorKey : error} : nil;
    NSError* result = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:info];

    return result;
}

- (NSError*)standardCouldntReadErrorWithUnderlyingError:(NSError *)error
{
    NSDictionary* info = error ? @{NSUnderlyingErrorKey : error} : nil;
    NSError* result = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:info];

    return result;
}

- (NSError*)standardAuthenticationErrorWithUnderlyingError:(NSError *)error
{
    NSDictionary* info = error ? @{NSUnderlyingErrorKey : error} : nil;
    NSError* result = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUserAuthenticationRequired userInfo:info];

    return result;
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

@synthesize request = _request;
@synthesize client = _client;

#pragma mark Registration

static NSMutableArray *sRegisteredProtocols;

+ (void)registerClass:(Class)protocolClass;
{
    NSParameterAssert([protocolClass isSubclassOfClass:[CK2Protocol class]]);
    
    dispatch_async([self queue], ^{ // might as well be async as queue might be blocked momentarily by a protocol
        
        [sRegisteredProtocols insertObject:protocolClass
                                           atIndex:0];  // so newest is consulted first
    });
}

+ (void)classForURL:(NSURL *)url completionHandler:(void (^)(Class protocol))block;
{
    // Search for correct protocol
    dispatch_async([self queue], ^{
        
        Class result = nil;
        for (Class aProtocol in sRegisteredProtocols)
        {
            if ([aProtocol canHandleURL:url])
            {
                result = aProtocol;
                break;
            }
        }
        
        block(result);
    });
}

+ (Class)classForURL:(NSURL *)url;
{
    __block Class result = nil;
    
    // Search for correct protocol
    dispatch_sync([self queue], ^{
        
        for (Class aProtocol in sRegisteredProtocols)
        {
            if ([aProtocol canHandleURL:url])
            {
                result = aProtocol;
                break;
            }
        }
    });
    
    return result;
}

@end

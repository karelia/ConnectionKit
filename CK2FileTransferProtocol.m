//
//  CK2FileTransferProtocol.m
//  Connection
//
//  Created by Mike on 11/10/2012.
//
//

#import "CK2FileTransferProtocol.h"

#import "CK2FTPProtocol.h"
#import "CK2SFTPProtocol.h"
#import "CK2FileProtocol.h"


@implementation CK2FileTransferProtocol

#pragma mark Serialization

+ (dispatch_queue_t)queue;
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("CK2FileTransferSystem", DISPATCH_QUEUE_SERIAL);
        
        // Register built-in protocols too
        sRegisteredProtocols = [[NSMutableArray alloc] initWithObjects:[CK2FileProtocol class], [CK2SFTPProtocol class], [CK2FTPProtocol class], nil];
    });
    
    return queue;
}

#pragma mark For Subclasses to Implement

+ (BOOL)canHandleURL:(NSURL *)url;
{
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

- (id)initForEnumeratingDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask client:(id<CK2FileTransferProtocolClient>)client;
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)initForCreatingDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates client:(id<CK2FileTransferProtocolClient>)client;
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates client:(id<CK2FileTransferProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock;
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)initForRemovingFileAtURL:(NSURL *)url client:(id<CK2FileTransferProtocolClient>)client;
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)initForSettingResourceValues:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url client:(id<CK2FileTransferProtocolClient>)client;
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
    return [NSURL URLWithString:[path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]
                  relativeToURL:baseURL];
}

+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;
{
    return [URL path];
}

#pragma mark Registration

static NSMutableArray *sRegisteredProtocols;

+ (void)registerClass:(Class)protocolClass;
{
    NSParameterAssert([protocolClass isSubclassOfClass:[CK2FileTransferProtocol class]]);
    
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

//
//  CK2FileManager
//  Connection
//
//  Created by Mike on 08/10/2012.
//
//

#import "CK2FileManager.h"
#import "CK2FileTransferProtocol.h"


@interface CK2FileTransferClient : NSObject <CK2FileTransferProtocolClient>
{
  @private
    CK2FileTransferProtocol *_protocol;
    CK2FileManager          *_manager;
    
    void    (^_completionBlock)(NSError *);
    void    (^_enumerationBlock)(NSURL *);
}

- (id)initWithManager:(CK2FileManager *)manager completionBlock:(void (^)(NSError *))block;
- (id)initWithManager:(CK2FileManager *)manager enumerationBlock:(void (^)(NSURL *))enumBlock completionBlock:(void (^)(NSError *))block;

- (void)startWithProtocol:(CK2FileTransferProtocol *)protocol;

@end


#pragma mark -


@interface CK2FileTransferProtocol (Internals)

// Completion block is guaranteed to be called on our private serial queue
+ (void)classForURL:(NSURL *)url completionHandler:(void (^)(Class protocolClass))block;

+ (Class)classForURL:(NSURL *)url;    // only suitable for stateless calls to the protocol class

@end


#pragma mark -


NSString * const CK2URLSymbolicLinkDestinationKey = @"CK2URLSymbolicLinkDestination";


@implementation CK2FileManager

#pragma mark Lifecycle

- (id)init;
{
    if (self = [super init])
    {
        // Record the queue to use for delegate messages
        NSOperationQueue *queue = [NSOperationQueue currentQueue];
        if (queue)
        {
            _deliverDelegateMessages = ^(void(^block)(void)) {
                [queue addOperationWithBlock:block];
            };
        }
        else
        {
            dispatch_queue_t queue = dispatch_get_current_queue();
            NSAssert(queue, @"dispatch_get_current_queue unexpectedly claims there is no current queue");
            
            _deliverDelegateMessages = ^(void(^block)(void)) {
                dispatch_async(queue, block);
            };
        }
        _deliverDelegateMessages = [_deliverDelegateMessages copy];
    }
    
    return self;
}

- (void)dealloc;
{
    [_deliverDelegateMessages release]; _deliverDelegateMessages = nil;
    [super dealloc];
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
    
    [CK2FileTransferProtocol classForURL:url completionHandler:^(Class protocolClass) {
        
        if (protocolClass)
        {
            CK2FileTransferClient *client = [[CK2FileTransferClient alloc] initWithManager:self
                                                                          enumerationBlock:block
                                                                           completionBlock:completionBlock];
            
            CK2FileTransferProtocol *protocol = [[protocolClass alloc] initForEnumeratingDirectoryAtURL:url
                                                                             includingPropertiesForKeys:keys
                                                                                                options:mask
                                                                                                 client:client];
            
            [client startWithProtocol:protocol];
            [protocol release];
            [client release];
        }
        else
        {
            completionBlock([self unsupportedURLErrorWithURL:url]);
        }
    }];
}

#pragma mark Creating and Deleting Items

- (void)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(url);
    
    [CK2FileTransferProtocol classForURL:url completionHandler:^(Class protocolClass) {
        
        if (protocolClass)
        {
            CK2FileTransferClient *client = [self makeClientWithCompletionHandler:handler];
            
            CK2FileTransferProtocol *protocol = [[protocolClass alloc] initForCreatingDirectoryAtURL:url
                                                                         withIntermediateDirectories:createIntermediates
                                                                                              client:client];
            
            [client startWithProtocol:protocol];
            [protocol release];
        }
        else
        {            
            handler([self unsupportedURLErrorWithURL:url]);
        }
    }];
}

- (void)createFileAtURL:(NSURL *)url contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setHTTPBody:data];
    
    [self createFileWithRequest:request withIntermediateDirectories:createIntermediates progressBlock:progressBlock];
    [request release];
}

- (void)createFileAtURL:(NSURL *)destinationURL withContentsOfURL:(NSURL *)sourceURL withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
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

- (void)createFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
{
    NSParameterAssert(request);
    
    [CK2FileTransferProtocol classForURL:[request URL] completionHandler:^(Class protocolClass) {
        
        if (protocolClass)
        {
            CK2FileTransferClient *client = [self makeClientWithCompletionHandler:^(NSError *error) {
                progressBlock(0, error);
            }];
            
            CK2FileTransferProtocol *protocol = [[protocolClass alloc] initForCreatingFileWithRequest:request
                                                                          withIntermediateDirectories:createIntermediates
                                                                                               client:client
                                                                                        progressBlock:^(NSUInteger bytesWritten){
                progressBlock(bytesWritten, nil);
            }];
            
            [client startWithProtocol:protocol];
            [protocol release];
        }
        else
        {
            progressBlock(0, [self unsupportedURLErrorWithURL:[request URL]]);
        }
    }];
}

- (void)removeFileAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(url);
    
    [CK2FileTransferProtocol classForURL:url completionHandler:^(Class protocolClass) {
        
        if (protocolClass)
        {
            CK2FileTransferClient *client = [self makeClientWithCompletionHandler:handler];
            CK2FileTransferProtocol *protocol = [[protocolClass alloc] initForRemovingFileAtURL:url client:client];
            [client startWithProtocol:protocol];
            [protocol release];
        }
        else
        {
            handler([self unsupportedURLErrorWithURL:url]);
        }
    }];
}

#pragma mark Getting and Setting Attributes

- (void)setResourceValues:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(keyedValues);
    NSParameterAssert(url);
    
    [CK2FileTransferProtocol classForURL:url completionHandler:^(Class protocolClass) {
        
        if (protocolClass)
        {
            CK2FileTransferClient *client = [self makeClientWithCompletionHandler:handler];
            CK2FileTransferProtocol *protocol = [[protocolClass alloc] initForSettingResourceValues:keyedValues ofItemAtURL:url client:client];
            [client startWithProtocol:protocol];
            [protocol release];
        }
        else
        {
            handler([self unsupportedURLErrorWithURL:url]);
        }
    }];
}

#pragma mark Delegate

@synthesize delegate = _delegate;

- (void)deliverBlockToDelegate:(void (^)(void))block;
{
    _deliverDelegateMessages(block);
}

#pragma mark URLs

+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
{
    Class protocolClass = [CK2FileTransferProtocol classForURL:baseURL];
    if (!protocolClass)
    {
        protocolClass = [CK2FileTransferProtocol class];
        if ([path isAbsolutePath])
        {
            // On 10.6, file URLs sometimes behave strangely when combined with an absolute path. Force it to be resolved
            if ([baseURL isFileURL]) [baseURL absoluteString];
        }
    }
    return [protocolClass URLWithPath:path relativeToURL:baseURL];
}

+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;
{
    Class protocolClass = [CK2FileTransferProtocol classForURL:URL];
    if (!protocolClass) protocolClass = [CK2FileTransferProtocol class];
    return [protocolClass pathOfURLRelativeToHomeDirectory:URL];
}

+ (BOOL)canHandleURL:(NSURL *)url;
{
    return ([CK2FileTransferProtocol classForURL:url] != nil);
}

#pragma mark Transfers

- (CK2FileTransferClient *)makeClientWithCompletionHandler:(void (^)(NSError *error))block;
{
    CK2FileTransferClient *client = [[CK2FileTransferClient alloc] initWithManager:self completionBlock:block];
    return [client autorelease];
}

- (NSError *)unsupportedURLErrorWithURL:(NSURL *)url;
{
    NSDictionary *info = @{NSURLErrorKey : url, NSURLErrorFailingURLErrorKey : url, NSURLErrorFailingURLStringErrorKey : [url absoluteString]};
    return [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnsupportedURL userInfo:info];
}

@end


#pragma mark -


@implementation CK2FileTransferClient

- (id)initWithManager:(CK2FileManager *)manager completionBlock:(void (^)(NSError *))block;
{
    NSParameterAssert(block);
    NSParameterAssert(manager);
    
    if (self = [self init])
    {
        _manager = [manager retain];
        _completionBlock = [block copy];
        
        [self retain];  // until protocol finishes or fails
    }
    
    return self;
}

- (id)initWithManager:(CK2FileManager *)manager enumerationBlock:(void (^)(NSURL *))enumBlock completionBlock:(void (^)(NSError *))block;
{
    if (self = [self initWithManager:manager completionBlock:block])
    {
        _enumerationBlock = [enumBlock copy];
    }
    return self;
}

- (void)startWithProtocol:(CK2FileTransferProtocol *)protocol;
{
    _protocol = [protocol retain];
    [protocol start];
}

- (void)finishWithError:(NSError *)error;
{
    _completionBlock(error);
    
    [_completionBlock release]; _completionBlock = nil;
    [_enumerationBlock release]; _enumerationBlock = nil;
    [_manager release]; _manager = nil;
    
    [self release]; // balances call in -init
}

- (void)fileTransferProtocol:(CK2FileTransferProtocol *)protocol didFailWithError:(NSError *)error;
{
    if (!error) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil];
    [self finishWithError:error];
}

- (void)fileTransferProtocolDidFinish:(CK2FileTransferProtocol *)protocol;
{
    [self finishWithError:nil];
}

- (void)fileTransferProtocol:(CK2FileTransferProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // TODO: Cache credentials per protection space
    [_manager deliverBlockToDelegate:^{
        [[_manager delegate] fileManager:_manager didReceiveAuthenticationChallenge:challenge];
    }];
}

- (void)fileTransferProtocol:(CK2FileTransferProtocol *)protocol appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript;
{
    [_manager deliverBlockToDelegate:^{
        [[_manager delegate] fileManager:_manager appendString:info toTranscript:transcript];
    }];
}

- (void)fileTransferProtocol:(CK2FileTransferProtocol *)protocol didDiscoverItemAtURL:(NSURL *)url;
{
    if (_enumerationBlock)
    {
        _enumerationBlock(url);
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

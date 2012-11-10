//
//  CK2FileManager
//  Connection
//
//  Created by Mike on 08/10/2012.
//
//

#import "CK2FileManager.h"
#import "CK2Protocol.h"


@interface CK2FileOperation : NSObject <CK2ProtocolClient>
{
  @private
    CK2Protocol     *_protocol;
    CK2FileManager  *_manager;
    
    void    (^_completionBlock)(NSError *);
    void    (^_enumerationBlock)(NSURL *);
}

- (id)initEnumerationOperationWithURL:(NSURL *)url
           includingPropertiesForKeys:(NSArray *)keys
                              options:(NSDirectoryEnumerationOptions)mask
                              manager:(CK2FileManager *)manager
                     enumerationBlock:(void (^)(NSURL *))enumBlock
                      completionBlock:(void (^)(NSError *))block;

- (id)initDirectoryCreationOperationWithURL:(NSURL *)url
                withIntermediateDirectories:(BOOL)createIntermediates
                                    manager:(CK2FileManager *)manager
                            completionBlock:(void (^)(NSError *))block;

- (id)initFileCreationOperationWithRequest:(NSURLRequest *)request
               withIntermediateDirectories:(BOOL)createIntermediates
                                   manager:(CK2FileManager *)manager
                             progressBlock:(void (^)(NSUInteger))progressBlock
                           completionBlock:(void (^)(NSError *))block;

- (id)initFileRemovalOperationWithURL:(NSURL *)url
                              manager:(CK2FileManager *)manager
                      completionBlock:(void (^)(NSError *))block;

- (id)initResourceValueSettingOperationWithURL:(NSURL *)url
                                        values:(NSDictionary *)keyedValues
                                       manager:(CK2FileManager *)manager
                               completionBlock:(void (^)(NSError *))block;


@end


#pragma mark -


@interface CK2Protocol (Internals)

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
    
    CK2FileOperation *operation = [[CK2FileOperation alloc] initEnumerationOperationWithURL:url
                                                                 includingPropertiesForKeys:keys
                                                                                    options:mask
                                                                                    manager:self
                                                                           enumerationBlock:block
                                                                            completionBlock:completionBlock];
    [operation release];
}

#pragma mark Creating and Deleting Items

- (void)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(url);
    
    CK2FileOperation *operation = [[CK2FileOperation alloc] initDirectoryCreationOperationWithURL:url
                                                                      withIntermediateDirectories:createIntermediates
                                                                                          manager:self
                                                                                  completionBlock:handler];
    [operation release];
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
    CK2FileOperation *operation = [[CK2FileOperation alloc] initFileCreationOperationWithRequest:request
                                                                     withIntermediateDirectories:createIntermediates
                                                                                         manager:self
                                                                                   progressBlock:^(NSUInteger bytesWritten) {
                                                                                       
                                                                                       progressBlock(bytesWritten, nil);
                                                                                   }
                                                                                 completionBlock:^(NSError *error) {
                                                                                     
                                                                                     progressBlock(0, error);
                                                                                 }];
    [operation release];
}

- (void)removeFileAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
{
    CK2FileOperation *operation = [[CK2FileOperation alloc] initFileRemovalOperationWithURL:url manager:self completionBlock:handler];
    [operation release];
}

#pragma mark Getting and Setting Attributes

- (void)setResourceValues:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(keyedValues);
    
    CK2FileOperation *operation = [[CK2FileOperation alloc] initResourceValueSettingOperationWithURL:url
                                                                                              values:keyedValues
                                                                                             manager:self
                                                                                     completionBlock:handler];
    [operation release];
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
    Class protocolClass = [CK2Protocol classForURL:baseURL];
    if (!protocolClass)
    {
        protocolClass = [CK2Protocol class];
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
    Class protocolClass = [CK2Protocol classForURL:URL];
    if (!protocolClass) protocolClass = [CK2Protocol class];
    return [protocolClass pathOfURLRelativeToHomeDirectory:URL];
}

+ (BOOL)canHandleURL:(NSURL *)url;
{
    return ([CK2Protocol classForURL:url] != nil);
}

#pragma mark Operations

@end


#pragma mark -


@implementation CK2FileOperation

#pragma mark Lifecycle

- (id)initWithURL:(NSURL *)url
          manager:(CK2FileManager *)manager
completionHandler:(void (^)(NSError *))completionBlock
createProtocolBlock:(CK2Protocol *(^)(Class protocolClass))createBlock;
{
    NSParameterAssert(url);
    NSParameterAssert(manager);
    
    if (self = [self init])
    {
        _manager = [manager retain];
        _completionBlock = [completionBlock copy];
        
        [CK2Protocol classForURL:url completionHandler:^(Class protocolClass) {
            
            if (protocolClass)
            {
                _protocol = createBlock(protocolClass);
                // TODO: Handle protocol's init method returning nil
                [_protocol start];
            }
            else
            {
                NSDictionary *info = @{NSURLErrorKey : url, NSURLErrorFailingURLErrorKey : url, NSURLErrorFailingURLStringErrorKey : [url absoluteString]};
                NSError *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorUnsupportedURL userInfo:info];
                [self finishWithError:error];
                [error release];
            }
        }];
    }
    
    return self;
}

- (id)initEnumerationOperationWithURL:(NSURL *)url
           includingPropertiesForKeys:(NSArray *)keys
                              options:(NSDirectoryEnumerationOptions)mask
                              manager:(CK2FileManager *)manager
                     enumerationBlock:(void (^)(NSURL *))enumBlock
                      completionBlock:(void (^)(NSError *))block;
{
    self = [self initWithURL:url manager:manager completionHandler:block createProtocolBlock:^CK2Protocol *(Class protocolClass) {
        
        return [[protocolClass alloc] initForEnumeratingDirectoryAtURL:url
                                            includingPropertiesForKeys:keys
                                                               options:mask
                                                                client:self];
    }];
    
    if (self) _enumerationBlock = [enumBlock copy];
    return self;
}

- (id)initDirectoryCreationOperationWithURL:(NSURL *)url
                withIntermediateDirectories:(BOOL)createIntermediates
                                    manager:(CK2FileManager *)manager
                            completionBlock:(void (^)(NSError *))block;
{
    return [self initWithURL:url manager:manager completionHandler:block createProtocolBlock:^CK2Protocol *(Class protocolClass) {
        
        return [[protocolClass alloc] initForCreatingDirectoryAtURL:url
                                        withIntermediateDirectories:createIntermediates
                                                             client:self];
    }];
}

- (id)initFileCreationOperationWithRequest:(NSURLRequest *)request
               withIntermediateDirectories:(BOOL)createIntermediates
                                   manager:(CK2FileManager *)manager
                             progressBlock:(void (^)(NSUInteger))progressBlock
                           completionBlock:(void (^)(NSError *))block;
{
    return [self initWithURL:[request URL] manager:manager completionHandler:block createProtocolBlock:^CK2Protocol *(Class protocolClass) {
        
        return [[protocolClass alloc] initForCreatingFileWithRequest:request
                                         withIntermediateDirectories:createIntermediates
                                                              client:self
                                                       progressBlock:progressBlock];
    }];
}

- (id)initFileRemovalOperationWithURL:(NSURL *)url
                              manager:(CK2FileManager *)manager
                      completionBlock:(void (^)(NSError *))block;
{
    return [self initWithURL:url manager:manager completionHandler:block createProtocolBlock:^CK2Protocol *(Class protocolClass) {
        
        return [[protocolClass alloc] initForRemovingFileAtURL:url client:self];
    }];
}

- (id)initResourceValueSettingOperationWithURL:(NSURL *)url
                                        values:(NSDictionary *)keyedValues
                                       manager:(CK2FileManager *)manager
                               completionBlock:(void (^)(NSError *))block;
{
    return [self initWithURL:url manager:manager completionHandler:block createProtocolBlock:^CK2Protocol *(Class protocolClass) {
        
        return [[protocolClass alloc] initForSettingResourceValues:keyedValues
                                                       ofItemAtURL:url
                                                            client:self];
    }];
}

- (void)finishWithError:(NSError *)error;
{
    _completionBlock(error);
    
    [_completionBlock release]; _completionBlock = nil;
    [_enumerationBlock release]; _enumerationBlock = nil;
    [_manager release]; _manager = nil;
    
    [self release]; // balances call in -init
}

- (void)dealloc
{
    [_protocol release];
    [_manager release];
    [_completionBlock release];
    [_enumerationBlock release];
    
    [super dealloc];
}

- (void)fileTransferProtocol:(CK2Protocol *)protocol didFailWithError:(NSError *)error;
{
    if (!error) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil];
    [self finishWithError:error];
}

- (void)fileTransferProtocolDidFinish:(CK2Protocol *)protocol;
{
    [self finishWithError:nil];
}

- (void)fileTransferProtocol:(CK2Protocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // TODO: Cache credentials per protection space
    [_manager deliverBlockToDelegate:^{
        [[_manager delegate] fileManager:_manager didReceiveAuthenticationChallenge:challenge];
    }];
}

- (void)fileTransferProtocol:(CK2Protocol *)protocol appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript;
{
    [_manager deliverBlockToDelegate:^{
        [[_manager delegate] fileManager:_manager appendString:info toTranscript:transcript];
    }];
}

- (void)fileTransferProtocol:(CK2Protocol *)protocol didDiscoverItemAtURL:(NSURL *)url;
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

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
  @public   // HACK so auth trampoline can get at them
    CK2FileManager  *_manager;
    dispatch_queue_t    _queue;
    
  @private
    CK2Protocol     *_protocol;
    
    void    (^_completionBlock)(NSError *);
    void    (^_enumerationBlock)(NSURL *);
    
    BOOL    _cancelled;
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

- (void)cancel;

@end


#pragma mark -


@interface CK2AuthenticationChallengeTrampoline : NSObject <NSURLAuthenticationChallengeSender>
{
  @private
    NSURLAuthenticationChallenge    *_originalChallenge;
    CK2FileOperation                *_operation;
    NSURLAuthenticationChallenge    *_trampolineChallenge;
}

+ (void)handleChallenge:(NSURLAuthenticationChallenge *)challenge operation:(CK2FileOperation *)operation;
@property(nonatomic, readonly, retain) NSURLAuthenticationChallenge *originalChallenge;

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

- (NSURLRequest *)requestWithURL:(NSURL *)url;
{
    return [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:60.0];
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
        _queue = dispatch_queue_create("CK2FileOperation", NULL);
        
        [CK2Protocol classForURL:url completionHandler:^(Class protocolClass) {
            
            if (protocolClass)
            {
                // Bounce over to operation's own queue for kicking off the real work
                // Keep an eye out for early opportunity to bail out if get cancelled
                dispatch_async(_queue, ^{
                    
                    if (![self isCancelled])
                    {
                        _protocol = createBlock(protocolClass);
                        // TODO: Handle protocol's init method returning nil
                        
                        if (![self isCancelled]) [_protocol start];
                    }
                });
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
        
        return [[protocolClass alloc] initForEnumeratingDirectoryWithRequest:[manager requestWithURL:url]
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
        
        return [[protocolClass alloc] initForCreatingDirectoryWithRequest:[manager requestWithURL:url]
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
        
        return [[protocolClass alloc] initForRemovingFileWithRequest:[manager requestWithURL:url] client:self];
    }];
}

- (id)initResourceValueSettingOperationWithURL:(NSURL *)url
                                        values:(NSDictionary *)keyedValues
                                       manager:(CK2FileManager *)manager
                               completionBlock:(void (^)(NSError *))block;
{
    return [self initWithURL:url manager:manager completionHandler:block createProtocolBlock:^CK2Protocol *(Class protocolClass) {
        
        return [[protocolClass alloc] initForSettingResourceValues:keyedValues
                                                 ofItemWithRequest:[manager requestWithURL:url]
                                                            client:self];
    }];
}

- (void)finishWithError:(NSError *)error;
{
    // Run completion block on own queue so that:
    //  A) It doesn't potentially hold up the calling queue for too long
    //  B) Serialises access, guaranteeing the block is only run once
    dispatch_async(_queue, ^{
        if (_completionBlock)
        {
            _completionBlock(error);
            [_completionBlock release]; _completionBlock = nil;
        }
    });
    
    // These ivars are already finished with, so can ditch them early
    [_enumerationBlock release]; _enumerationBlock = nil;
    [_manager release]; _manager = nil;
}

- (void)dealloc
{
    [_protocol release];
    [_manager release];
    if (_queue) dispatch_release(_queue);
    [_completionBlock release];
    [_enumerationBlock release];
    
    [super dealloc];
}

#pragma mark Cancellation

- (void)cancel;
{
    /*  Any already-enqueued delegate messages will likely still run. That's fine as it seems we might as well report things that are already known to have happened
     */
    
    _cancelled = YES;
    
    // Tell the protocol as soon as we can.
    dispatch_set_target_queue(_queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    
    dispatch_async(_queue, ^{
        [_protocol stop];
    });
    
    // Report cancellation to completion handler. If protocol has already finished or failed, it'll go ignored
    NSError *cancellationError = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
    [self finishWithError:cancellationError];
    [cancellationError release];
}

- (BOOL)isCancelled; { return _cancelled; }

#pragma mark CK2ProtocolClient

- (void)protocol:(CK2Protocol *)protocol didFailWithError:(NSError *)error;
{
    NSParameterAssert(protocol == _protocol);
    if ([self isCancelled]) return; // ignore errors once cancelled as protocol might be trying to invent its own
    
    if (!error) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil];
    [self finishWithError:error];
}

- (void)protocolDidFinish:(CK2Protocol *)protocol;
{
    NSParameterAssert(protocol == _protocol);
    // Might as well report success even if cancelled
    
    [self finishWithError:nil];
}

- (void)protocol:(CK2Protocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSParameterAssert(protocol == _protocol);
    if ([self isCancelled]) return; // don't care about auth once cancelled
    
    [CK2AuthenticationChallengeTrampoline handleChallenge:challenge operation:self];
    // TODO: Cache credentials per protection space
}

- (void)protocol:(CK2Protocol *)protocol appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript;
{
    NSParameterAssert(protocol == _protocol);
    // Even if cancelled, allow through since could well be valuable debugging info
    
    // Tell delegate on a global queue so that we don't risk blocking the op's serial queue, delaying cancellation
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[_manager delegate] fileManager:_manager appendString:info toTranscript:transcript];
    });
}

- (void)protocol:(CK2Protocol *)protocol didDiscoverItemAtURL:(NSURL *)url;
{
    NSParameterAssert(protocol == _protocol);
    // Even if cancelled, allow through as the discovery still stands; might be useful for caching elsewhere
    
    if (_enumerationBlock) _enumerationBlock(url);
}

@end


#pragma mark -


@implementation CK2AuthenticationChallengeTrampoline

+ (void)handleChallenge:(NSURLAuthenticationChallenge *)challenge operation:(CK2FileOperation *)operation;
{
    // Trust the tramoline to release itself when done
    [[[self alloc] initWithChallenge:challenge operation:operation] release];
}

- (id)initWithChallenge:(NSURLAuthenticationChallenge *)challenge operation:(CK2FileOperation *)operation;
{
    if (self = [super init])
    {
        _originalChallenge = [challenge retain];
        _operation = [operation retain];
        
        if ([challenge proposedCredential])
        {
            _trampolineChallenge = [[NSURLAuthenticationChallenge alloc] initWithAuthenticationChallenge:challenge sender:self];
        }
        else
        {
            // Invent the best credential available
            // TODO: Base on the URL's user + password if included
            NSURLProtectionSpace *space = [challenge protectionSpace];
            NSURLCredential *credential = [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:space];
            
            _trampolineChallenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                                              proposedCredential:credential
                                                                            previousFailureCount:[challenge previousFailureCount]
                                                                                 failureResponse:[challenge failureResponse]
                                                                                           error:[challenge error]
                                                                                          sender:self];
        }
        
        CK2FileManager *manager = operation->_manager;
        
        // Tell delegate on a global queue so that we don't risk blocking the op's serial queue, delaying cancellation
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[manager delegate] fileManager:manager didReceiveAuthenticationChallenge:_trampolineChallenge];
        });
        
        [self retain];  // gets released when challenge is replied to
    }
    return self;
}

- (void)dealloc
{
    [_originalChallenge release];
    [_operation release];
    [_trampolineChallenge release];
    [super dealloc];
}

@synthesize originalChallenge = _originalChallenge;

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSParameterAssert(challenge == _trampolineChallenge);
    
    dispatch_async(_operation->_queue, ^{
        [[_originalChallenge sender] useCredential:credential forAuthenticationChallenge:_originalChallenge];
        [self release];
    });
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSParameterAssert(challenge == _trampolineChallenge);
    
    dispatch_async(_operation->_queue, ^{
        [[_originalChallenge sender] continueWithoutCredentialForAuthenticationChallenge:_originalChallenge];
        [self release];
    });
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSParameterAssert(challenge == _trampolineChallenge);
    
    dispatch_async(_operation->_queue, ^{
        [[_originalChallenge sender] cancelAuthenticationChallenge:challenge];
        [self release];
    });
}

- (void)performDefaultHandlingForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // TODO: Should this be forwarded straight on to the original sender if implements this method?
    if ([challenge previousFailureCount] == 0)
    {
        NSURLCredential *credential = [challenge proposedCredential];
        if (credential)
        {
            [self useCredential:credential forAuthenticationChallenge:challenge];
            return;
        }
    }
    
    [self continueWithoutCredentialForAuthenticationChallenge:challenge];
}

- (void)rejectProtectionSpaceAndContinueWithChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // TODO: Presumably this should move on to the next protection space if there is one
    [self cancelAuthenticationChallenge:challenge];
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

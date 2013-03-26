//
//  CK2FileOperation.m
//  Connection
//
//  Created by Mike on 22/03/2013.
//
//

#import "CK2FileOperation.h"
#import "CK2Protocol.h"

#if !TARGET_OS_IPHONE
#import <AppKit/AppKit.h>   // so icon handling can use NSImage and NSWorkspace for now
#endif


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
@end


@interface CK2FileManager (Internals)
+ (void)setTemporaryResourceValueForKey:(NSString *)key inURL:(NSURL *)url asBlock:(id (^)(void))block;
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
        _URL = [url copy];
        _completionBlock = [completionBlock copy];
        _queue = dispatch_queue_create("com.karelia.connection.file-operation", NULL);
        
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
        
        // If we try to do this outside the block there's a risk the protocol object will be created *before* the enum block has been stored, which ends real badly
        _enumerationBlock = [enumBlock copy];
        
        return [[protocolClass alloc] initForEnumeratingDirectoryWithRequest:[self requestWithURL:url]
                                                  includingPropertiesForKeys:keys
                                                                     options:mask
                                                                      client:self];
    }];
    
    return self;
}

- (id)initDirectoryCreationOperationWithURL:(NSURL *)url
                withIntermediateDirectories:(BOOL)createIntermediates
                          openingAttributes:(NSDictionary *)attributes
                                    manager:(CK2FileManager *)manager
                            completionBlock:(void (^)(NSError *))block;
{
    return [self initWithURL:url manager:manager completionHandler:block createProtocolBlock:^CK2Protocol *(Class protocolClass) {
        
        return [[protocolClass alloc] initForCreatingDirectoryWithRequest:[self requestWithURL:url]
                                              withIntermediateDirectories:createIntermediates
                                                        openingAttributes:attributes
                                                                   client:self];
    }];
}

- (id)initFileCreationOperationWithURL:(NSURL *)url
                                  data:(NSData *)data
           withIntermediateDirectories:(BOOL)createIntermediates
                     openingAttributes:(NSDictionary *)attributes
                               manager:(CK2FileManager *)manager
                         progressBlock:(CK2ProgressBlock)progressBlock
                       completionBlock:(void (^)(NSError *))block;
{
    return [self initWithURL:url manager:manager completionHandler:block createProtocolBlock:^CK2Protocol *(Class protocolClass) {
        
        NSMutableURLRequest *request = [[self requestWithURL:url] mutableCopy];
        request.HTTPBody = data;
        
        CK2Protocol *result = [[protocolClass alloc] initForCreatingFileWithRequest:request
                                                        withIntermediateDirectories:createIntermediates
                                                                  openingAttributes:attributes
                                                                             client:self
                                                                      progressBlock:progressBlock];
        
        [request release];
        return result;
    }];
}

- (id)initFileCreationOperationWithURL:(NSURL *)url
                                  file:(NSURL *)sourceURL
           withIntermediateDirectories:(BOOL)createIntermediates
                     openingAttributes:(NSDictionary *)attributes
                               manager:(CK2FileManager *)manager
                         progressBlock:(CK2ProgressBlock)progressBlock
                       completionBlock:(void (^)(NSError *))block;
{
    return [self initWithURL:url manager:manager completionHandler:block createProtocolBlock:^CK2Protocol *(Class protocolClass) {
        
        _localURL = [sourceURL copy];
        
        NSMutableURLRequest *request = [[self requestWithURL:url] mutableCopy];
        
        // Read the data using an input stream if possible, and know file size
        NSNumber *fileSize;
        if ([sourceURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL] && fileSize)
        {
            NSString *length = [NSString stringWithFormat:@"%llu", fileSize.unsignedLongLongValue];
            
            NSInputStream *stream = [self protocol:nil needNewBodyStream:nil];
            if (stream)
            {
                [request setHTTPBodyStream:stream];
                [request setValue:length forHTTPHeaderField:@"Content-Length"];
            }
        }
        
        if (!request.HTTPBodyStream)
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
                [self protocol:nil didFailWithError:error];
                return nil;
            }
        }
        
        CK2Protocol *result = [[protocolClass alloc] initForCreatingFileWithRequest:request
                                                        withIntermediateDirectories:createIntermediates
                                                                  openingAttributes:attributes
                                                                             client:self
                                                                      progressBlock:progressBlock];
        
        [request release];
        return result;
    }];
}

- (id)initRemovalOperationWithURL:(NSURL *)url
                          manager:(CK2FileManager *)manager
                  completionBlock:(void (^)(NSError *))block;
{
    return [self initWithURL:url manager:manager completionHandler:block createProtocolBlock:^CK2Protocol *(Class protocolClass) {
        
        return [[protocolClass alloc] initForRemovingFileWithRequest:[self requestWithURL:url] client:self];
    }];
}

- (id)initResourceValueSettingOperationWithURL:(NSURL *)url
                                        values:(NSDictionary *)keyedValues
                                       manager:(CK2FileManager *)manager
                               completionBlock:(void (^)(NSError *))block;
{
    return [self initWithURL:url manager:manager completionHandler:block createProtocolBlock:^CK2Protocol *(Class protocolClass) {
        
        return [[protocolClass alloc] initForSettingAttributes:keyedValues
                                             ofItemWithRequest:[self requestWithURL:url]
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
    [_URL release];
    if (_queue) dispatch_release(_queue);
    [_completionBlock release];
    [_enumerationBlock release];
    [_localURL release];
    
    [super dealloc];
}

#pragma mark Requests

- (NSURLRequest *)requestWithURL:(NSURL *)url;
{
    return [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:60.0];
}

#pragma mark Cancellation

- (void)cancel;
{
    /*  Any already-enqueued delegate messages will likely still run. That's fine as it seems we might as well report things that are already known to have happened
     */
    
    _cancelled = YES;
    
    // Report cancellation to completion handler. If protocol has already finished or failed, it'll go ignored
    NSError *cancellationError = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
    [self finishWithError:cancellationError];
    
    // Once the cancellation message is queued up, it's safe to tell the protocol as it can't misinterpret the message and issue its own cancellation error
    [_protocol stop];
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
        
        id <CK2FileManagerDelegate> delegate = [_manager delegate];
        if ([delegate respondsToSelector:@selector(fileManager:appendString:toTranscript:)])
        {
            [delegate fileManager:_manager appendString:info toTranscript:transcript];
        }
    });
}

- (void)protocol:(CK2Protocol *)protocol didDiscoverItemAtURL:(NSURL *)url;
{
    NSParameterAssert(protocol == _protocol);
    // Even if cancelled, allow through as the discovery still stands; might be useful for caching elsewhere
    
    // Provide ancestry and other fairly generic keys on-demand
    [self.class setResourceValueBlocksForURL:url protocolClass:protocol.class];
    
    if (_enumerationBlock) _enumerationBlock(url);
    
    // It seems poor security to vend out passwords here, so have a quick sanity check
    if (CFURLGetByteRangeForComponent((CFURLRef)url, kCFURLComponentPassword, NULL).location != kCFNotFound)
    {
        NSLog(@"%@ is reporting URLs with a password, such as %@\nThis seems poor security practice", protocol, url);
    }
}

#if !TARGET_OS_IPHONE
+ (void)setResourceValueBlocksForURL:(NSURL *)strongURL protocolClass:(Class)protocolClass;
{
    __block NSURL *url = strongURL;    // URL retains its resource values; so if the blocks retained the URL would be a cycle
    
    NSString *path = [protocolClass pathOfURLRelativeToHomeDirectory:url];
    if ([path isAbsolutePath])
    {
        [CK2FileManager setTemporaryResourceValueForKey:NSURLParentDirectoryURLKey inURL:url asBlock:^id {
            
            if (path.pathComponents.count > 1)   // stop at root
            {
                NSURL *result = [protocolClass URLWithPath:[path stringByDeletingLastPathComponent] relativeToURL:url].absoluteURL;
                [CK2FileManager setTemporaryResourceValue:@YES forKey:NSURLIsDirectoryKey inURL:result];
                
                // Recurse
                [self setResourceValueBlocksForURL:result protocolClass:protocolClass];
                
                return result;
            }
            
            return nil;
        }];
        
        
        // Only need supply icon if protocol hasn't done so
        NSImage *icon;
        if (![url getResourceValue:&icon forKey:NSURLEffectiveIconKey error:NULL] || !icon)
        {
            // Fill in icon as best we can
            [CK2FileManager setTemporaryResourceValueForKey:NSURLEffectiveIconKey inURL:url asBlock:^id{
                
                NSString *fileType = url.pathExtension;
                if (path.pathComponents.count == 1)
                {
                    fileType = NSFileTypeForHFSTypeCode(kGenericFileServerIcon);
                }
                else if ([fileType isEqual:@"app"])
                {
                    fileType = NSFileTypeForHFSTypeCode(kGenericApplicationIcon);
                }
                else
                {
                    NSNumber *isDirectory;
                    if (![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL] || isDirectory == nil)
                    {
                        isDirectory = @(CFURLHasDirectoryPath((CFURLRef)url));
                    }
                    
                    // Guess based on file type
                    if (isDirectory.boolValue)
                    {
                        if ([protocolClass isHomeDirectoryAtURL:url])
                        {
                            fileType = NSFileTypeForHFSTypeCode(kUserFolderIcon);
                        }
                        else
                        {
                            NSNumber *package;
                            if (![url getResourceValue:&package forKey:NSURLIsPackageKey error:NULL] || !package.boolValue)
                            {
                                return [NSImage imageNamed:NSImageNameFolder];
                            }
                        }
                    }
                }
                
                return [[NSWorkspace sharedWorkspace] iconForFileType:fileType];
            }];
        }
    }
}
#endif

- (NSInputStream *)protocol:(CK2Protocol *)protocol needNewBodyStream:(NSURLRequest *)request;
{
    NSParameterAssert(protocol == _protocol);
    
    NSInputStream *stream = [[NSInputStream alloc] initWithURL:_localURL];
    return [stream autorelease];
}

@end


#pragma mark -


@implementation CK2AuthenticationChallengeTrampoline

+ (void)handleChallenge:(NSURLAuthenticationChallenge *)challenge operation:(CK2FileOperation *)operation;
{
    // Trust the trampoline to release itself when done
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
            NSURLProtectionSpace *space = [challenge protectionSpace];
            NSString *user = [_operation->_URL user];
            NSString *password = [_operation->_URL password];
            
            NSURLCredential *credential;
            if (user && password)
            {
                credential = [NSURLCredential credentialWithUser:user password:password persistence:NSURLCredentialPersistenceNone];
            }
            else
            {
                credential = [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:space];
            }
            
            _trampolineChallenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                                              proposedCredential:credential
                                                                            previousFailureCount:[challenge previousFailureCount]
                                                                                 failureResponse:[challenge failureResponse]
                                                                                           error:[challenge error]
                                                                                          sender:self];
        }
        
#ifndef __clang_analyzer__ // clang seems to produce an entirely spurious warning here - it says that self hasn't been set, but it has
        CK2FileManager *manager = operation->_manager;
#endif
        
        id <CK2FileManagerDelegate> delegate = [manager delegate];
        if ([delegate respondsToSelector:@selector(fileManager:didReceiveAuthenticationChallenge:)])
        {
            [delegate fileManager:manager didReceiveAuthenticationChallenge:_trampolineChallenge];
        }
        else
        {
            [[_trampolineChallenge sender] performDefaultHandlingForAuthenticationChallenge:_trampolineChallenge];
        }
        
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

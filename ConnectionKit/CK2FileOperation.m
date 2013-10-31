//
//  CK2FileOperation.m
//  Connection
//
//  Created by Mike on 22/03/2013.
//
//

#import "CK2FileOperation.h"
#import "CK2Protocol.h"

#import <AppKit/AppKit.h>   // so icon handling can use NSImage and NSWorkspace for now


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
                        if (!_protocol)
                        {
                            // it's likely that the protocol has already called protocol:didFailWithError:, which will have called finishWithError:, which means that a call to the completion
                            // block is queue up already with an error in it
                            // just in case though, we can report a more generic error here - once the completion block is called once it will be cleared out, the protocol's error will win
                            // if there is one
                            NSDictionary *info = @{NSURLErrorKey : url, NSURLErrorFailingURLErrorKey : url, NSURLErrorFailingURLStringErrorKey : [url absoluteString]};
                            NSError *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorUnsupportedURL userInfo:info]; // TODO: what's the correct error to report here?
                            [self completeWithError:error];
                            [error release];
                        }

                        if (![self isCancelled]) [_protocol start];
                    }
                });
            }
            else
            {
                NSDictionary *info = @{NSURLErrorKey : url, NSURLErrorFailingURLErrorKey : url, NSURLErrorFailingURLStringErrorKey : [url absoluteString]};
                NSError *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorUnsupportedURL userInfo:info];
                [self completeWithError:error];
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
        
        return [[protocolClass alloc] initForRemovingItemWithRequest:[self requestWithURL:url] client:self];
    }];
}

- (id)initRenameOperationWithSourceURL:(NSURL *)srcURL
                      newName:(NSString *)newName
                             manager:(CK2FileManager *)manager
                     completionBlock:(void (^)(NSError *))block;
{
    return [self initWithURL:srcURL manager:manager completionHandler:block createProtocolBlock:^CK2Protocol *(Class protocolClass) {
        
        return [[protocolClass alloc] initForRenamingItemWithRequest:[self requestWithURL:srcURL] newName:newName client:self];
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

- (void)completeWithError:(NSError *)error;
{
    // Run completion block on own queue so that:
    //  A) It doesn't potentially hold up the calling queue for too long
    //  B) Serialises access
    dispatch_async(_queue, ^{
        
        if (_completionBlock)   // only allow "completion" to happen the once!
        {
            // It's now safe to stop the protocol as it can't misinterpret the message and issue its own cancellation error (or at least if it does, goes ignored)
            [_protocol stop];
            
            _completionBlock(error);
            [_completionBlock release]; _completionBlock = nil;

            // Break retain cycle, but deliberately keep weak reference so we know we're associated with it
            [_protocol release];
        }
    });
    
    // These ivars are already finished with, so can ditch them early
    [_enumerationBlock release]; _enumerationBlock = nil;
    [_manager release]; _manager = nil;
}

- (void)dealloc
{
    //[_protocol release];  DON'T release protocol. It should be a weak reference by the time deallocation happens
    [_manager release];
    [_URL release];
    if (_queue) dispatch_release(_queue);
    [_completionBlock release];
    [_enumerationBlock release];
    [_localURL release];

    [super dealloc];
}

#pragma mark Manager

@synthesize fileManager = _manager;

#pragma mark URL & Requests

@synthesize originalURL = _URL;

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
    [self completeWithError:cancellationError];
    
    [cancellationError release];
}

- (BOOL)isCancelled; { return _cancelled; }

#pragma mark CK2ProtocolClient

- (void)protocol:(CK2Protocol *)protocol didFailWithError:(NSError *)error;
{
    NSAssert(protocol == _protocol, @"Message received from unexpected protocol: %@ (should be %@)", protocol, _protocol);
    
    if (!error) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil];
    [self completeWithError:error];
}

- (void)protocolDidFinish:(CK2Protocol *)protocol;
{
    NSAssert(protocol == _protocol, @"Message received from unexpected protocol: %@ (should be %@)", protocol, _protocol);
    // Might as well report success even if cancelled
    
    [self completeWithError:nil];
}

- (void)protocol:(CK2Protocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)originalChallenge;
{
    NSAssert(protocol == _protocol, @"Message received from unexpected protocol: %@ (should be %@)", protocol, _protocol);
    if ([self isCancelled]) return; // don't care about auth once cancelled
    
    
    // Invent a default credential if needed
    NSURLAuthenticationChallenge *challenge = originalChallenge;
    if (!originalChallenge.proposedCredential)
    {
        NSURLProtectionSpace *space = originalChallenge.protectionSpace;
        NSString *user = self.originalURL.user;
        NSString *password = self.originalURL.password;
        
        NSURLCredential *credential;
        if (user && password)
        {
            credential = [NSURLCredential credentialWithUser:user password:password persistence:NSURLCredentialPersistenceNone];
        }
        else
        {
            credential = [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:space];
        }
        
        challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                               proposedCredential:credential
                                                             previousFailureCount:originalChallenge.previousFailureCount
                                                                  failureResponse:originalChallenge.failureResponse
                                                                            error:originalChallenge.error
                                                                           sender:originalChallenge.sender];
        
        [challenge autorelease];
    }
    
    
    // Notify the delegate
    CK2FileManager *manager = self.fileManager;
    id <CK2FileManagerDelegate> delegate = manager.delegate;
    
    if ([delegate respondsToSelector:@selector(fileManager:operation:didReceiveChallenge:completionHandler:)])
    {
        __block BOOL handlerCalled = NO;
        [delegate fileManager:manager operation:self didReceiveChallenge:challenge completionHandler:^(CK2AuthChallengeDisposition disposition, NSURLCredential *credential) {
            
            if (handlerCalled) [NSException raise:NSInvalidArgumentException format:@"Auth Challenge completion handler block called more than once"];
            handlerCalled = YES;
            
            switch (disposition)
            {
                case CK2AuthChallengeUseCredential:
                    dispatch_async(_queue, ^{
                        [originalChallenge.sender useCredential:credential forAuthenticationChallenge:originalChallenge];
                    });
                    break;
                    
                case CK2AuthChallengePerformDefaultHandling:
                    [self performDefaultHandlingForAuthenticationChallenge:originalChallenge proposedCredential:challenge.proposedCredential];
                    break;
                    
                case CK2AuthChallengeRejectProtectionSpace:
                    // TODO: Presumably this should move on to the next protection space if there is one, rather than cancelling
                case CK2AuthChallengeCancelAuthenticationChallenge:
                    dispatch_async(_queue, ^{
                        [originalChallenge.sender cancelAuthenticationChallenge:originalChallenge];
                    });
                    break;
                    
                default:
                    [NSException raise:NSInvalidArgumentException format:@"Unrecognised Auth Challenge Disposition"];
            }
        }];
    }
    else if ([delegate respondsToSelector:@selector(fileManager:didReceiveAuthenticationChallenge:)])
    {
        NSLog(@"%@ implements the old CK2FileManager authentication delegate method instead of the new one", delegate.class);
    }
    else
    {
        [self performDefaultHandlingForAuthenticationChallenge:originalChallenge proposedCredential:challenge.proposedCredential];
    }
    
    
    // TODO: Cache credentials per protection space
}

- (void)performDefaultHandlingForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge proposedCredential:(NSURLCredential *)credential;
{
    // TODO: Should this be forwarded straight on to the original sender if implements this method?
    
    dispatch_async(_queue, ^{
        
        if (challenge.previousFailureCount == 0)
        {
            if (credential)
            {
                [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
                return;
            }
        }
        
        [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
    });
}

- (void)protocol:(CK2Protocol *)protocol appendString:(NSString *)info toTranscript:(CK2TranscriptType)transcript;
{
    NSAssert(protocol == _protocol, @"Message received from unexpected protocol: %@ (should be %@)", protocol, _protocol);
    
    
    // Pass straight onto delegate and trust it not to take too long handling it
    // We used to dispatch off onto one of the global queues, but that does have the nasty downside of messages sometimes arriving out-of-order or concurrently
    id <CK2FileManagerDelegate> delegate = [self.fileManager delegate];
    if ([delegate respondsToSelector:@selector(fileManager:appendString:toTranscript:)])
    {
        [delegate fileManager:self.fileManager appendString:info toTranscript:transcript];
    }
}

- (void)protocol:(CK2Protocol *)protocol didDiscoverItemAtURL:(NSURL *)url;
{
    NSAssert(protocol == _protocol, @"Message received from unexpected protocol: %@ (should be %@)", protocol, _protocol);
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

+ (void)setResourceValueBlocksForURL:(NSURL *)strongURL protocolClass:(Class)protocolClass;
{
    __block NSURL *url = strongURL;    // URL retains its resource values; so if the blocks retained the URL would be a cycle
    
    NSString *path = [protocolClass pathOfURLRelativeToHomeDirectory:url];
    if ([path isAbsolutePath])
    {
        [CK2FileManager setTemporaryResourceValueForKey:NSURLParentDirectoryURLKey inURL:url asBlock:^id {
            
            if (path.pathComponents.count > 1)   // stop at root
            {
                NSURL *result = [url URLByDeletingLastPathComponent];
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

- (NSInputStream *)protocol:(CK2Protocol *)protocol needNewBodyStream:(NSURLRequest *)request;
{
    NSAssert(protocol == _protocol, @"Message received from unexpected protocol: %@ (should be %@)", protocol, _protocol);
    
    NSInputStream *stream = [[NSInputStream alloc] initWithURL:_localURL];
    return [stream autorelease];
}

@end

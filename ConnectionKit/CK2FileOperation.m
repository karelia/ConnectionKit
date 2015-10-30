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


@interface CK2FileOperationCallbacks : NSObject {
    
    CK2Protocol *(^_protocolCreator)(CK2FileOperation *fileOp, Class protocolClass);
}

/**
 @param protocolCreator The block is passed the file operation it applies to — so don't wind up with
 a retain cycle — and the class of the protocol to be created.
 */
+ (instancetype)callbacksWithProtocolCreator:(CK2Protocol *(^)(CK2FileOperation *fileOp, Class protocolClass))protocolCreator;

- (CK2Protocol *)createProtocolForFileOperation:(CK2FileOperation *)fileOp class:(Class)protocolClass NS_RETURNS_RETAINED;

@end


#pragma mark -


@interface CK2FileOperation () <CK2ProtocolClient>

- (id)initWithURL:(NSURL *)url
 errorDescription:(NSString *)errorDescription
          manager:(CK2FileManager *)manager
completionHandler:(void (^)(NSError *))completionBlock
callbacks:(CK2FileOperationCallbacks *)callbacks NS_DESIGNATED_INITIALIZER;

@property(readonly) CK2FileManager *fileManager;    // goes to nil once finished/failed
@property (readwrite) int64_t countOfBytesWritten;
@property (readwrite) int64_t countOfBytesExpectedToWrite;
@property(readwrite) CK2FileOperationState state;
@property (readwrite, copy) NSError *error;
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
 errorDescription:(NSString *)errorDescription
          manager:(CK2FileManager *)manager
completionHandler:(void (^)(NSError *))completionBlock
callbacks:(CK2FileOperationCallbacks *)callbacks;
{
    NSParameterAssert(url);
    NSParameterAssert(manager);
    
    if (self = [super init])
    {
        _state = CK2FileOperationStateSuspended;
        _manager = [manager retain];
        _originalURL = [url copy];
        _descriptionForErrors = [errorDescription copy];
        
        if (!completionBlock)
        {
            completionBlock = ^(NSError *error) {
                id <CK2FileManagerDelegate> delegate = manager.delegate;
                if ([delegate respondsToSelector:@selector(fileManager:operation:didCompleteWithError:)])
                {
                    [delegate fileManager:manager operation:self didCompleteWithError:error];
                }
            };
        }
        _completionBlock = [completionBlock copy];
        
        _callbacks = [callbacks retain];
        _queue = dispatch_queue_create("com.karelia.connection.file-operation", NULL);
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
    NSString *name = url.lastPathComponent;
    
    NSString *description;
    if (name.length)
    {
        description = [NSString stringWithFormat:NSLocalizedString(@"The folder “%@” could not be accessed.", "error descrption"),
                       url.lastPathComponent];
    }
    else
    {
        description = NSLocalizedString(@"The server could not be accessed.", "error description");
    }
    
    CK2FileOperationCallbacks *callbacks = [CK2FileOperationCallbacks callbacksWithProtocolCreator:^CK2Protocol *(CK2FileOperation *fileOp, Class protocolClass) {
        
        // If we try to do this outside the block there's a risk the protocol object will be created *before* the enum block has been stored, which ends real badly
        fileOp->_enumerationBlock = [enumBlock copy];
        
        return [[protocolClass alloc] initForEnumeratingDirectoryWithRequest:[fileOp requestWithURL:url]
                                                  includingPropertiesForKeys:keys
                                                                     options:mask
                                                                      client:fileOp];
    }];
    
    return [self initWithURL:url errorDescription:description manager:manager completionHandler:block callbacks:callbacks];
}

- (id)initDirectoryCreationOperationWithURL:(NSURL *)url
                withIntermediateDirectories:(BOOL)createIntermediates
                          openingAttributes:(NSDictionary *)attributes
                                    manager:(CK2FileManager *)manager
                            completionBlock:(void (^)(NSError *))block;
{
    NSString *description = [NSString stringWithFormat:NSLocalizedString(@"The folder “%@” could not be created.", "error descrption"),
                             url.lastPathComponent];
    
    CK2FileOperationCallbacks *callbacks = [CK2FileOperationCallbacks callbacksWithProtocolCreator:^CK2Protocol *(CK2FileOperation *fileOp, Class protocolClass) {
        
        return [[protocolClass alloc] initForCreatingDirectoryWithRequest:[fileOp requestWithURL:url]
                                              withIntermediateDirectories:createIntermediates
                                                        openingAttributes:attributes
                                                                   client:fileOp];
    }];
    
    self = [self initWithURL:url errorDescription:description manager:manager completionHandler:block callbacks:callbacks];
    
    // Special case SFTP for now.
    if ([url.scheme caseInsensitiveCompare:@"sftp"] == NSOrderedSame) {
        _createIntermediateDirectories = createIntermediates;
    }
    
    return self;
}

- (id)initFileCreationOperationWithURL:(NSURL *)url
                                  data:(NSData *)data
           withIntermediateDirectories:(BOOL)createIntermediates
                     openingAttributes:(NSDictionary *)attributes
                               manager:(CK2FileManager *)manager
                         progressBlock:(CK2ProgressBlock)progressBlock
                       completionBlock:(void (^)(NSError *))block;
{
    NSString *description = [NSString stringWithFormat:NSLocalizedString(@"The file “%@” could not be uploaded.", "error description"),
                             url.lastPathComponent];
    
    CK2FileOperationCallbacks *callbacks = [CK2FileOperationCallbacks callbacksWithProtocolCreator:^CK2Protocol *(CK2FileOperation *fileOp, Class protocolClass) {
        
        NSMutableURLRequest *request = [[fileOp requestWithURL:url] mutableCopy];
        request.HTTPBody = data;
        
        CK2Protocol *result = [[protocolClass alloc] initForCreatingFileWithRequest:request
                                                                               size:data.length
                                                        withIntermediateDirectories:createIntermediates
                                                                  openingAttributes:attributes
                                                                             client:fileOp];
        
        [request release];
        return result;
    }];
    
    self = [self initWithURL:url errorDescription:description manager:manager completionHandler:block callbacks:callbacks];
    
    _bytesExpectedToWrite = data.length;
    _progressBlock = [progressBlock copy];
    
    // Special case SFTP for now.
    if ([url.scheme caseInsensitiveCompare:@"sftp"] == NSOrderedSame) {
        _createIntermediateDirectories = createIntermediates;
    }

    return self;
}

- (id)initFileCreationOperationWithURL:(NSURL *)url
                                  file:(NSURL *)sourceURL
           withIntermediateDirectories:(BOOL)createIntermediates
                     openingAttributes:(NSDictionary *)attributes
                               manager:(CK2FileManager *)manager
                         progressBlock:(CK2ProgressBlock)progressBlock
                       completionBlock:(void (^)(NSError *))block;
{
    NSString *description = [NSString stringWithFormat:NSLocalizedString(@"The file “%@” could not be uploaded.", "error descrption"),
                             url.lastPathComponent];
    
    NSNumber *fileSize;
    if (![sourceURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL]) fileSize = nil;;
    
    CK2FileOperationCallbacks *callbacks = [CK2FileOperationCallbacks callbacksWithProtocolCreator:^CK2Protocol *(CK2FileOperation *fileOp, Class protocolClass) {
        
        fileOp->_localURL = [sourceURL copy];
        
        NSMutableURLRequest *request = [[fileOp requestWithURL:url] mutableCopy];
        
        // Read the data using an input stream if possible, and know file size
        int64_t size = (fileSize ? fileSize.longLongValue : NSURLResponseUnknownLength);
        if (size >= 0)
        {
            NSInputStream *stream = [fileOp protocol:nil needNewBodyStream:nil];
            if (stream)
            {
                [request setHTTPBodyStream:stream];
            }
        }
        
        if (!request.HTTPBodyStream)
        {
            NSError *error;
            NSData *data = [[NSData alloc] initWithContentsOfURL:sourceURL options:0 error:&error];
            
            if (data)
            {
                [request setHTTPBody:data];
                size = data.length;
                [data release];
            }
            else
            {
                [request release];
                if (!error) error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
                [fileOp protocol:nil didCompleteWithError:error];
                return nil;
            }
        }
        
        CK2Protocol *result = [[protocolClass alloc] initForCreatingFileWithRequest:request
                                                                               size:size
                                                        withIntermediateDirectories:createIntermediates
                                                                  openingAttributes:attributes
                                                                             client:fileOp];
        
        [request release];
        return result;
    }];
    
    self = [self initWithURL:url errorDescription:description manager:manager completionHandler:block callbacks:callbacks];
    
    _bytesExpectedToWrite = fileSize.longLongValue;
    _progressBlock = [progressBlock copy];
    
    // Special case SFTP for now.
    if ([url.scheme caseInsensitiveCompare:@"sftp"] == NSOrderedSame) {
        _createIntermediateDirectories = createIntermediates;
    }
    
    return self;
}

- (id)initRemovalOperationWithURL:(NSURL *)url
                          manager:(CK2FileManager *)manager
                  completionBlock:(void (^)(NSError *))block;
{
    NSString *description = [NSString stringWithFormat:NSLocalizedString(@"The file “%@” could not be deleted.", "error descrption"),
                             url.lastPathComponent];
    
    CK2FileOperationCallbacks *callbacks = [CK2FileOperationCallbacks callbacksWithProtocolCreator:^CK2Protocol *(CK2FileOperation *fileOp, Class protocolClass) {
        return [[protocolClass alloc] initForRemovingItemWithRequest:[fileOp requestWithURL:url] client:fileOp];
    }];
    
    return [self initWithURL:url errorDescription:description manager:manager completionHandler:block callbacks:callbacks];
}

- (id)initRenameOperationWithSourceURL:(NSURL *)srcURL
                      newName:(NSString *)newName
                             manager:(CK2FileManager *)manager
                     completionBlock:(void (^)(NSError *))block;
{
    NSString *description = [NSString stringWithFormat:NSLocalizedString(@"The file “%@” could not be renamed.", "error descrption"),
                             srcURL.lastPathComponent];
    
    CK2FileOperationCallbacks *callbacks = [CK2FileOperationCallbacks callbacksWithProtocolCreator:^CK2Protocol *(CK2FileOperation *fileOp, Class protocolClass) {
        return [[protocolClass alloc] initForRenamingItemWithRequest:[fileOp requestWithURL:srcURL] newName:newName client:fileOp];
    }];
    
    return [self initWithURL:srcURL errorDescription:description manager:manager completionHandler:block callbacks:callbacks];
}

- (id)initResourceValueSettingOperationWithURL:(NSURL *)url
                                        values:(NSDictionary *)keyedValues
                                       manager:(CK2FileManager *)manager
                               completionBlock:(void (^)(NSError *))block;
{
    NSString *description = [NSString stringWithFormat:NSLocalizedString(@"The file “%@” could not be updated.", "error descrption"),
                             url.lastPathComponent];
    
    CK2FileOperationCallbacks *callbacks = [CK2FileOperationCallbacks callbacksWithProtocolCreator:^CK2Protocol *(CK2FileOperation *fileOp, Class protocolClass) {
        
        return [[protocolClass alloc] initForSettingAttributes:keyedValues
                                             ofItemWithRequest:[fileOp requestWithURL:url]
                                                        client:fileOp];
    }];
    
    return [self initWithURL:url errorDescription:description manager:manager completionHandler:block callbacks:callbacks];
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
            
            // Store the error and notify completion handler
            // Make all notifications — including KVO — happen on the delegate queue
            // Grab the handler now since we're about to clear out the original storage. The
            // delegate block should capture this so we don't need to retain it ourselves
            void (^handler)(NSError *) = _completionBlock;
            
            [self tryToMessageDelegateSelector:NULL usingBlock:^(id<CK2FileManagerDelegate> delegate) { // NULL selector so always executes
                self.error = error;
                self.state = CK2FileOperationStateCompleted;
                handler(error);
            }];
            
            // Clean up too so as to break retain cycles. HAS to happen within this block (and not
            // e.g. during the delegate call back) so _completionBlock is cleared out and never
            // allowed to run twice
            [_completionBlock release]; _completionBlock = nil;
            [_progressBlock release];   _progressBlock = nil;
            [_enumerationBlock release];_enumerationBlock = nil;
            
            
            // Break retain cycle, but deliberately keep weak reference so we know we're associated with it
            [_protocol release];
        }
    });
}

- (void)dealloc
{
    //[_protocol release];  DON'T release protocol. It should be a weak reference by the time deallocation happens
    [_manager release];
    [_originalURL release];
    if (_queue) dispatch_release(_queue);
    [_completionBlock release];
    [_enumerationBlock release];
    [_callbacks release];
    [_progressBlock release];
    [_localURL release];
    [_error release];

    [super dealloc];
}

#pragma mark Manager

@synthesize fileManager = _manager;

- (void)tryToMessageDelegateSelector:(SEL)selector usingBlock:(void (^)(id <CK2FileManagerDelegate> delegate))block;
{
    CK2FileManager *manager = self.fileManager;
    NSAssert(manager, @"%@ disconnected from its manager too early", self.class);
    
    // Clients could change the delegate at any time. If we trust them to do so in concert with the
    // delegate queue, then that can be made reasonably safe by only accessing the delegate from
    // within the queue.
    // It's still inherently a bit dangerous though, as the client could change it on a different
    // queue, or could have specified a non-serial delegate queue.
    [manager.delegateQueue addOperationWithBlock:^{
        id <CK2FileManagerDelegate> delegate = manager.delegate;
        if (!selector || [delegate respondsToSelector:selector]) {
            block(delegate);
        }
    }];
}

#pragma mark URL & Requests

@synthesize originalURL = _originalURL;

- (NSURLRequest *)requestWithURL:(NSURL *)url;
{
    return [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:60.0];
}

#pragma mark Body Data

@synthesize countOfBytesWritten = _bytesWritten;
@synthesize countOfBytesExpectedToWrite = _bytesExpectedToWrite;

#pragma mark Cancellation

- (void)cancel;
{
    if (self.state >= CK2FileOperationStateCanceling) return;
    
    /*  Any already-enqueued delegate messages will likely still run. That's fine as it seems we might as well report things that are already known to have happened
     */
    
    // FIXME: There's a race condition here where .state could change after our intitial check of it
    
    self.state = CK2FileOperationStateCanceling;
    
    // Report cancellation to completion handler. If protocol has already finished or failed, it'll go ignored
    NSError *cancellationError = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
    [self completeWithError:cancellationError];
    
    [cancellationError release];
}

#pragma mark State

@synthesize state = _state;
@synthesize error = _error;

- (void)resume;
{
    if (self.state == CK2FileOperationStateSuspended)
    {
        self.state = CK2FileOperationStateRunning;
        [self createProtocolAndStart];
    }
}

/**
 Private method that does the work of creating the protocol instance, and getting it going
 */
- (void)createProtocolAndStart {
    NSURL *url = self.originalURL;
    
    [CK2Protocol classForURL:url completionHandler:^(Class protocolClass) {
        
        if (protocolClass)
        {
            // Bounce over to operation's own queue for kicking off the real work
            // Keep an eye out for early opportunity to bail out if get cancelled
            dispatch_async(_queue, ^{
                
                if (self.state == CK2FileOperationStateRunning)
                {
                    NSAssert(_protocol == nil, @"Protocol has already been created");
                    _protocol = [_callbacks createProtocolForFileOperation:self class:protocolClass];
                    
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
                    
                    if (self.state == CK2FileOperationStateRunning) [_protocol start];
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

#pragma mark CK2ProtocolClient

- (void)protocol:(CK2Protocol *)protocol didCompleteWithError:(NSError *)error;
{
    NSAssert(protocol == _protocol, @"Message received from unexpected protocol: %@ (should be %@)", protocol, _protocol);
    
    // Errors should start with our description
    if (error)
    {
        if (_createIntermediateDirectories) {
            NSString *path = [CK2FileManager pathOfURL:self.originalURL];
            if (path.length && ![path isEqualToString:@"/"]) {
                
                NSURL *directoryURL = [self.originalURL URLByDeletingLastPathComponent];
                _createIntermediateDirectories = NO;    // avoid doing this again
                
                [self.fileManager createDirectoryAtURL:directoryURL
                           withIntermediateDirectories:YES
                                     openingAttributes:nil  // probably ought to provide something better, but I'm being lazy
                                     completionHandler:^(NSError *directoryError) {
                                         
                                         // If creating directory also fails, give up. Otherwise let's try again!
                                         if (directoryError) {
                                             [self protocol:protocol didCompleteWithError:error];
                                         }
                                         else {
                                             [_protocol release]; _protocol = nil;
                                             [self createProtocolAndStart];
                                         }
                                     }];
                
                return;
            }
        }
        
        if (_descriptionForErrors)
        {
            NSMutableDictionary *info = [error.userInfo mutableCopy];
            NSString *description = [_descriptionForErrors stringByAppendingFormat:@" %@", error.localizedDescription];
            [info setObject:description forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:error.domain code:error.code userInfo:info];
            [info release];
        }
    }
    
    [self completeWithError:error];
}

- (NSURLRequest *)protocol:(CK2Protocol *)protocol willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response;
{
    NSAssert(protocol == _protocol, @"Message received from unexpected protocol: %@ (should be %@)", protocol, _protocol);
    
    id <CK2FileManagerDelegate> delegate = self.fileManager.delegate;
    if ([delegate respondsToSelector:@selector(fileManager:operation:willSendRequest:redirectResponse:completionHandler:)])
    {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        __block NSURLRequest *weakRequest;
        [delegate fileManager:self.fileManager operation:self willSendRequest:request redirectResponse:response completionHandler:^(NSURLRequest *request) {
            weakRequest = [request retain];
            dispatch_semaphore_signal(semaphore);
        }];
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        request = [weakRequest autorelease];
        dispatch_release(semaphore);
    }
    
    return request;
}

- (void)protocol:(CK2Protocol *)protocol didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(CK2AuthChallengeDisposition, NSURLCredential *))completionHandler;
{
    NSAssert(protocol == _protocol, @"Message received from unexpected protocol: %@ (should be %@)", protocol, _protocol);
    if (self.state >= CK2FileOperationStateCanceling) return; // don't care about auth once cancelled
    
    
    // Invent a default credential if needed
    if (!challenge.proposedCredential)
    {
        NSURLProtectionSpace *space = challenge.protectionSpace;
        NSString *user = self.originalURL.user;
        NSString *password = self.originalURL.password;
        
        NSURLCredential *credential;
        if (user)
        {
            if (password) {
                credential = [NSURLCredential credentialWithUser:user password:password persistence:NSURLCredentialPersistenceNone];
            }
            else {
                credential = [[NSURLCredentialStorage.sharedCredentialStorage credentialsForProtectionSpace:space] objectForKey:user];
            }
        }
        else
        {
            credential = [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:space];
        }
        
        challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                               proposedCredential:credential
                                                             previousFailureCount:challenge.previousFailureCount
                                                                  failureResponse:challenge.failureResponse
                                                                            error:challenge.error
                                                                           sender:challenge.sender];
        
        [challenge autorelease];
    }
    
    
    // Notify the delegate
    CK2FileManager *manager = self.fileManager;
    id <CK2FileManagerDelegate> delegate = manager.delegate;
    
    if ([delegate respondsToSelector:@selector(fileManager:operation:didReceiveChallenge:completionHandler:)])
    {
        [manager.delegateQueue addOperationWithBlock:^{
            
        __block BOOL handlerCalled = NO;
        [delegate fileManager:manager operation:self didReceiveChallenge:challenge completionHandler:^(CK2AuthChallengeDisposition disposition, NSURLCredential *credential) {
            
            if (handlerCalled) [NSException raise:NSInvalidArgumentException format:@"Auth Challenge completion handler block called more than once"];
            handlerCalled = YES;
            
            dispatch_async(_queue, ^{
                completionHandler(disposition, credential);
            });
        }];
            
        }];
    }
    else if ([delegate respondsToSelector:@selector(fileManager:didReceiveAuthenticationChallenge:)])
    {
        NSLog(@"%@ implements the old CK2FileManager authentication delegate method instead of the new one", delegate.class);
    }
    else
    {
        dispatch_async(_queue, ^{
            completionHandler(CK2AuthChallengePerformDefaultHandling, nil);
        });
    }
    
    
    // TODO: Cache credentials per protection space
}

- (void)protocol:(CK2Protocol *)protocol appendString:(NSString *)info toTranscript:(CK2TranscriptType)transcript;
{
    NSAssert(protocol == _protocol, @"Message received from unexpected protocol: %@ (should be %@)", protocol, _protocol);
    
    
    // Pass straight onto delegate and trust it not to take too long handling it
    // We used to dispatch off onto one of the global queues, but that does have the nasty downside of messages sometimes arriving out-of-order or concurrently
    [self tryToMessageDelegateSelector:@selector(fileManager:appendString:toTranscript:) usingBlock:^(id<CK2FileManagerDelegate> delegate) {
        [delegate fileManager:self.fileManager appendString:info toTranscript:transcript];
    }];
}

- (void)protocol:(CK2Protocol *)protocol didDiscoverItemAtURL:(NSURL *)url;
{
    NSAssert(protocol == _protocol, @"Message received from unexpected protocol: %@ (should be %@)", protocol, _protocol);
    // Even if cancelled, allow through as the discovery still stands; might be useful for caching elsewhere
    
    // Provide ancestry and other fairly generic keys on-demand
    [self.class setResourceValueBlocksForURL:url protocolClass:protocol.class];
    
    
        [self tryToMessageDelegateSelector:NULL usingBlock:^(id<CK2FileManagerDelegate> delegate) {
            if (_enumerationBlock) _enumerationBlock(url);
        }];
    
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

- (void)protocol:(CK2Protocol *)protocol didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
{
    self.countOfBytesWritten = totalBytesSent;
    self.countOfBytesExpectedToWrite = totalBytesExpectedToSend;
    
    CK2FileManager *manager = self.fileManager;
    [manager.delegateQueue addOperationWithBlock:^{
        
    if (_progressBlock)
    {
        _progressBlock(bytesSent, totalBytesSent, totalBytesExpectedToSend);
    }
    else
    {
        id <CK2FileManagerDelegate> delegate = manager.delegate;
        if ([delegate respondsToSelector:@selector(fileManager:operation:didWriteBodyData:totalBytesWritten:totalBytesExpectedToWrite:)])
        {
            [delegate fileManager:manager
                        operation:self
                 didWriteBodyData:bytesSent
                totalBytesWritten:totalBytesSent
        totalBytesExpectedToWrite:totalBytesExpectedToSend];
        }
    }
        
    }];
}

- (NSInputStream *)protocol:(CK2Protocol *)protocol needNewBodyStream:(NSURLRequest *)request;
{
    NSAssert(protocol == _protocol, @"Message received from unexpected protocol: %@ (should be %@)", protocol, _protocol);
    
    NSInputStream *stream = [[NSInputStream alloc] initWithURL:_localURL];
    return [stream autorelease];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    // For easy stashing in dictionaries
    return [self retain];
}

@end


#pragma mark -


@implementation CK2FileOperationCallbacks

+ (instancetype)callbacksWithProtocolCreator:(CK2Protocol *(^)(CK2FileOperation *, Class))protocolCreator {
    CK2FileOperationCallbacks *result = [[self alloc] init];
    result->_protocolCreator = [protocolCreator copy];
    return [result autorelease];
}

- (CK2Protocol *)createProtocolForFileOperation:(CK2FileOperation *)fileOp class:(Class)protocolClass {
    return _protocolCreator(fileOp, protocolClass);
}

@end

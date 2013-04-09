//
//  CK2WebDAVProtocol.h
//
//  Created by Sam Deane on 19/11/2012.
//

#import "CK2WebDAVProtocol.h"
#import "CKTransferRecord.h"

#ifndef CK2WebDAVLog
#define CK2WebDAVLog NSLog
#endif

@interface CK2WebDAVProtocol()

@property (assign, nonatomic) NSUInteger attempts;
@property (copy, nonatomic) CK2WebDAVCompletionHandler completionHandler;
@property (copy, nonatomic) CK2WebDAVErrorHandler errorHandler;
@property (assign, nonatomic) NSUInteger expectedLength;
@property (copy, nonatomic) CK2ProgressBlock progressHandler;
@property (strong, nonatomic) NSOperationQueue* queue;

@end

@implementation CK2WebDAVProtocol

@synthesize attempts = _attempts;
@synthesize completionHandler = _completionHandler;
@synthesize errorHandler = _errorHandler;
@synthesize expectedLength = _expectedLength;
@synthesize progressHandler = _progressHandler;
@synthesize queue = _queue;

+ (BOOL)canHandleURL:(NSURL *)url;
{
    return [url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"];
}

#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client
{
    if (self = [super initWithRequest:request client:client])
    {
        [self setupQueue];
        _session = [[DAVSession alloc] initWithRootURL:request.URL delegate:self];
    }

    return self;
}

- (void)dealloc;
{
    CK2WebDAVLog(@"dealloced");
    
    [_completionHandler release];
    [_errorHandler release];
    [_progressHandler release];
    [_queue release];
    [_session release];

    [super dealloc];
}

#pragma mark - Operations

- (id)initForEnumeratingDirectoryWithRequest:(NSURLRequest *)request includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask client:(id<CK2ProtocolClient>)client;
{
    CK2WebDAVLog(@"enumerating directory");

    if ((self = [self initWithRequest:request client:client]) != nil)
    {
        NSString* path = [self pathForRequest:request];

        DAVRequest* davRequest = [[DAVListingRequest alloc] initWithPath:path session:_session delegate:self];
        [_queue addOperation:davRequest];

        self.completionHandler = ^(id result) {
            CK2WebDAVLog(@"enumerating directory results");

            if (mask & CK2DirectoryEnumerationIncludesDirectory && result)
            {
                NSURL *directoryURL = [request.URL URLByAppendingPathComponent:@""];    // ensure has a trailing slash
                [client protocol:self didDiscoverItemAtURL:directoryURL];
            }
            
            for (DAVResponseItem* item in result)
            {
                NSString *name = [[item href] lastPathComponent];
                if (!((mask & NSDirectoryEnumerationSkipsHiddenFiles) && [name hasPrefix:@"."]))
                {

                    NSURL* url = [davRequest concatenatedURLWithPath:[item href]];
                    [CK2FileManager setTemporaryResourceValue:[item modificationDate] forKey:NSURLContentModificationDateKey inURL:url];
                    [CK2FileManager setTemporaryResourceValue:[item creationDate] forKey:NSURLCreationDateKey inURL:url];
                    [CK2FileManager setTemporaryResourceValue:[NSNumber numberWithUnsignedInteger:[item contentLength]] forKey:NSURLFileSizeKey inURL:url];
                    [item.fileAttributes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                        [CK2FileManager setTemporaryResourceValue:obj forKey:key inURL:url];
                    }];
                    [CK2FileManager setTemporaryResourceValue:[item contentType] forKey:NSURLFileResourceTypeKey inURL:url];
                    [client protocol:self didDiscoverItemAtURL:url];
                    CK2WebDAVLog(@"%@", url);
                }
            }

            [self reportFinished];
        };

    }

    return self;
}

- (id)initForCreatingDirectoryWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client;
{
    CK2WebDAVLog(@"creating directory");

    if ((self = [self initWithRequest:request client:client]) != nil)
    {
        NSString* path = [self pathForRequest:request];

        // when done, we just report that we're finished
        CK2WebDAVCompletionHandler handleCompletion = ^(id result) {

            CK2WebDAVLog(@"create directory done");
            [self reportFinished];
        };

        // when a real error occurs, report it
        CK2WebDAVErrorHandler handleRealError = ^(NSError *error) {
            CK2WebDAVLog(@"create directory failed");
            [self reportFailedWithError:error];
        };

        // the first time an error occurs, if we were asked to create intermediates, try again with that flag actually set to YES
        CK2WebDAVErrorHandler handleFirstError = ^(NSError *error) {
            // only bother trying again if we actually got a relevant error
            if (createIntermediates && [error.domain isEqualToString:DAVClientErrorDomain] && (error.code == 405))
            {
                [self addCreateDirectoryRequestForPath:path withIntermediateDirectories:YES errorHandler:handleRealError completionHandler:handleCompletion];
            }
            else
            {
                handleRealError(error);
            }
        };

        // for the sake of efficiency, the first time we always try the creation without making intermediates
        // if that fails, and if we were asked to make intermediates, we try again
        [self addCreateDirectoryRequestForPath:path withIntermediateDirectories:NO errorHandler:handleFirstError completionHandler:handleCompletion];
    };

    return self;
}

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client progressBlock:(CK2ProgressBlock)progressBlock;
{
    CK2WebDAVLog(@"creating file");

    if ((self = [self initWithRequest:request client:client]) != nil)
    {
        NSString* path = [self pathForRequest:request];

        CK2WebDAVCompletionHandler makeFileBlock = ^(id result) {

            DAVPutRequest* davRequest = [[DAVPutRequest alloc] initWithPath:path originalRequest:request session:_session delegate:self];
            
            [_queue addOperation:davRequest];
            [davRequest release];

            self.expectedLength = davRequest.expectedLength;
            CKTransferRecord* transfer = [CKTransferRecord recordWithName:[path lastPathComponent] size:self.expectedLength];

            self.progressHandler = ^(NSUInteger progress, NSUInteger previousAttemptsCount) {
                [transfer setProgress:progress];
                if (progressBlock)
                {
                    progressBlock(progress, previousAttemptsCount);
                }
            };

            self.completionHandler =  ^(id result) {
                CK2WebDAVLog(@"creating file done");
                [transfer transferDidFinish:transfer error:nil];
                [self reportFinished];
            };

            self.errorHandler = ^(NSError* error) {
                CK2WebDAVLog(@"creating file failed");
                [transfer transferDidFinish:transfer error:error];
                [self reportFailedWithError:error];
            };
        };

        if (createIntermediates)
        {
            NSString* parent = [path stringByDeletingLastPathComponent];
            createIntermediates = ![parent isEqualToString:@"/"];
            if (createIntermediates)
            {
                [self addCreateDirectoryRequestForPath:path
                           withIntermediateDirectories:createIntermediates
                                          errorHandler:^(NSError *error) {

                                              CK2WebDAVLog(@"create subdirectory failed");
                                              [self reportFailedWithError:error];

                                          } completionHandler:^(id result) {
                                              // reset the attempts count (don't count attempts whilst creating)
                                              self.attempts = 0;
                                              makeFileBlock(result);
                                          }
                 ];
            }
        }

        if (!createIntermediates)
        {
            makeFileBlock(nil);
        }

   }

    return self;
}

- (id)initForRenamingItemWithRequest:(NSURLRequest *)request newName:(NSString *)newName client:(id<CK2ProtocolClient>)client
{
    CK2WebDAVLog(@"renaming file");

    if ((self = [self initWithRequest:request client:client]) != nil)
    {
        NSString* path = [self pathForRequest:request];
        DAVMoveRequest* davRequest = [[DAVMoveRequest alloc] initWithPath:path session:_session delegate:self];
        davRequest.destinationPath = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:newName];
        [_queue addOperation:davRequest];
        [davRequest release];

        self.completionHandler = ^(id result) {
            CK2WebDAVLog(@"renaming file done");
            [self reportFinished];
        };
    }

    return self;
}
- (id)initForRemovingFileWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    CK2WebDAVLog(@"removing file");

    if ((self = [self initWithRequest:request client:client]) != nil)
    {
        NSString* path = [self pathForRequest:request];
        DAVRequest* davRequest = [[DAVDeleteRequest alloc] initWithPath:path session:_session delegate:self];
        [_queue addOperation:davRequest];
        [davRequest release];

        self.completionHandler = ^(id result) {
            CK2WebDAVLog(@"removing file done");
            [self reportFinished];
        };
    }

    return self;
}

- (id)initForSettingAttributes:(NSDictionary *)keyedValues ofItemWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    CK2WebDAVLog(@"setting resource values");

    if ((self = [self initWithRequest:request client:client]) != nil)
    {
        [self reportFinished];
    }

    return self;
}

- (void)start;
{
    CK2WebDAVLog(@"started");
    self.queue.suspended = NO;
}

- (void)stop
{
    CK2WebDAVLog(@"stopped");
    self.queue.suspended = YES;
    [self.queue cancelAllOperations];
}

- (NSString*)pathForRequest:(NSURLRequest*)request
{
    NSString *path = [CK2WebDAVProtocol pathOfURLRelativeToHomeDirectory:request.URL];
    if (!path) path = @"/";

    return path;
}

#pragma mark Request Delegate

- (void)requestDidBegin:(DAVRequest *)aRequest;
{
    CK2WebDAVLog(@"webdav request began");
}

- (void)request:(DAVRequest *)aRequest didSucceedWithResult:(id)result;
{
    CK2WebDAVLog(@"webdav request succeeded");

    // if there is a completion handler set, it is expected to call protocolDidFinish
    // this lets us build chains of requests where only the final one makes the
    // didFinish call
    if (self.completionHandler)
    {
        self.completionHandler(result);
    }

    // if not, we call it
    else
    {
        [self reportFinished];
    }
}

- (void)request:(DAVRequest *)aRequest didFailWithError:(NSError *)error;
{
    CK2WebDAVLog(@"webdav request failed");

    if (self.errorHandler)
    {
        self.errorHandler(error);
    }
    else
    {
        [self reportFailedWithError:error];
    }
}

- (void)webDAVRequest:(DAVRequest *)request didSendDataOfLength:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    CK2WebDAVLog(@"webdav sent data");

    if (self.expectedLength != totalBytesExpectedToWrite)
    {
        ++self.attempts;
        self.expectedLength = totalBytesExpectedToWrite;
    }
    
    if (self.progressHandler)
    {
        self.progressHandler(totalBytesWritten, self.attempts);
    }
}

- (NSInputStream*)webDAVRequest:(DAVRequest *)request needNewBodyStream:(NSURLRequest *)urlRequest
{

    NSInputStream* result = [[self client] protocol:self needNewBodyStream:urlRequest];

    return result;
}

#pragma mark WebDAV Authentication


- (void)webDAVSession:(DAVSession *)session didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    CK2WebDAVLog(@"webdav received challenge");

    [[self client] protocol:self didReceiveAuthenticationChallenge:challenge];
}

- (void)webDAVSession:(DAVSession *)session didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    CK2WebDAVLog(@"webdav cancelled challenge");
    
    [[self client] protocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                                      code:NSURLErrorUserCancelledAuthentication
                                                                  userInfo:nil]];
}

- (void)webDAVSession:(DAVSession *)session appendStringToTranscript:(NSString *)string sent:(BOOL)sent;
{
    CK2WebDAVLog(sent ? @"<-- %@ " : @"--> %@", string);

    [[self client] protocol:self appendString:string toTranscript:(sent ? CKTranscriptSent : CKTranscriptReceived)];
}

#pragma mark - Utilities

- (void)setupQueue
{
    NSOperationQueue* queue = [[NSOperationQueue alloc] init];
    queue.suspended = YES;
    queue.name = @"CK2WebDAVProtocol";
    queue.maxConcurrentOperationCount = 1;
    self.queue = queue;
    [queue release];
}

- (void)reportFinished
{
    [self.queue addOperationWithBlock:^{
        [self.client protocolDidFinish:self];
    }];
}

- (void)reportFailedWithError:(NSError*)error
{
    [self.queue addOperationWithBlock:^{
        [self.client protocol:self didFailWithError:error];
    }];
}

/**
 Create a chain of createDirectory requests.
 If createIntermediates is NO, we just create one request for the specified path, and set the completion handler
 for the operation to whatever we were given.

 If it's YES, we recurse down to the root of the path, and make a request which creates the root directory. We then
 set the completion of this request to create the next level up, and so on, until the final completion which creates
 the path we were initially given, and calls the completion block we were given.
 */

- (void)addCreateDirectoryRequestForPath:(NSString*)path
             withIntermediateDirectories:(BOOL)createIntermediates
                            errorHandler:(CK2WebDAVErrorHandler)errorHandler
                       completionHandler:(CK2WebDAVCompletionHandler)completionHandler
{
    CK2WebDAVCompletionHandler createDirectoryBlock = Block_copy(^(id result) {
        DAVRequest* davRequest = [[DAVMakeCollectionRequest alloc] initWithPath:path session:_session delegate:self];
        [_queue addOperation:davRequest];
        [davRequest release];

        self.completionHandler = completionHandler;
        self.errorHandler = errorHandler;
    });

    CK2WebDAVErrorHandler errorBlock = Block_copy(^(NSError* error) {
        if (([error.domain isEqualToString:DAVClientErrorDomain]) && (error.code == 405))
        {
            // ignore failure to create for all but the top directory, on the basis that they may well exist already
            createDirectoryBlock(nil);
        }
        else
        {
            // other errors are passed on
            errorHandler(error);
        }
    });

    BOOL recursed = NO;
    if (createIntermediates)
    {
        NSString* parent = [path stringByDeletingLastPathComponent];
        if (![parent isEqualToString:@"/"])
        {
            [self addCreateDirectoryRequestForPath:parent withIntermediateDirectories:YES errorHandler:errorBlock completionHandler:createDirectoryBlock];
            recursed = YES;
        }
    }

    if (!recursed)
    {
        createDirectoryBlock(nil);
    }

    Block_release(errorHandler);
    Block_release(createDirectoryBlock);
}

@end


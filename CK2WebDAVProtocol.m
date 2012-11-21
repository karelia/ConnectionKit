//
//  CK2WebDAVProtocol.h
//
//  Created by Sam Deane on 19/11/2012.
//

#import "CK2WebDAVProtocol.h"
#import "CKRemoteURL.h"
#import "CKTransferRecord.h"

#define CK2WebDAVLog NSLog
//#define CK2WebDAVLog(...)

@interface CK2WebDAVProtocol()

@property (copy, nonatomic) CK2WebDAVCompletionHandler completionHandler;
@property (copy, nonatomic) CK2WebDAVErrorHandler errorHandler;
@property (copy, nonatomic) CK2WebDAVProgressHandler progressHandler;

@end

@implementation CK2WebDAVProtocol

@synthesize completionHandler = _completionHandler;
@synthesize errorHandler = _errorHandler;
@synthesize progressHandler = _progressHandler;


+ (BOOL)canHandleURL:(NSURL *)url;
{
    return [url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"];
}

#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client
{
    if (self = [super initWithRequest:request client:client])
    {
        _queue = [[NSOperationQueue alloc] init];
        _queue.name = @"CK2WebDAVProtocol";
        _queue.suspended = YES;
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

            NSURL* root = [[NSURL URLWithString:@"/" relativeToURL:request.URL] absoluteURL];
            for (DAVResponseItem* item in result)
            {
                NSString *name = [[item href] lastPathComponent];
                if (!((mask & NSDirectoryEnumerationSkipsHiddenFiles) && [name hasPrefix:@"."]))
                {
                    CKRemoteURL* url = [[CKRemoteURL alloc] initWithString:[[root URLByAppendingPathComponent:[item href]] absoluteString]];
                    [url setTemporaryResourceValue:[item modificationDate] forKey:NSURLContentModificationDateKey];
                    [url setTemporaryResourceValue:[item creationDate] forKey:NSURLCreationDateKey];
                    [url setTemporaryResourceValue:[NSNumber numberWithUnsignedInteger:[item contentLength]] forKey:NSURLFileSizeKey];
                    [item.fileAttributes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                        [url setTemporaryResourceValue:obj forKey:key];
                    }];
                    [url setTemporaryResourceValue:[item contentType] forKey:NSURLFileResourceTypeKey]; // 10.7 properties go last because might be nil at runtime
                    [client protocol:self didDiscoverItemAtURL:url];
                    CK2WebDAVLog(@"%@", url);
                    [url release];
                }
            }
        };

    }

    return self;
}

- (id)initForCreatingDirectoryWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates client:(id<CK2ProtocolClient>)client;
{
    CK2WebDAVLog(@"creating directory");

    if ((self = [self initWithRequest:request client:client]) != nil)
    {
        NSString* path = [self pathForRequest:request];
        DAVRequest* davRequest = [[DAVMakeCollectionRequest alloc] initWithPath:path session:_session delegate:self];
        [_queue addOperation:davRequest];

        self.completionHandler = ^(id result) {
            CK2WebDAVLog(@"create directory done");
        };
    };

    return self;
}

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates client:(id<CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock;
{
    CK2WebDAVLog(@"creating file");

    if ((self = [self initWithRequest:request client:client]) != nil)
    {
        NSString* path = [self pathForRequest:request];
        NSData* data = [request HTTPBody];

        DAVPutRequest* davRequest = [[DAVPutRequest alloc] initWithPath:path session:_session delegate:self];
        [davRequest setData:data];
        [_queue addOperation:davRequest];
        [davRequest release];

        CFStringRef type = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)[path pathExtension], NULL);
        CFStringRef mimeType = NULL;
        if (type)
        {
            mimeType = UTTypeCopyPreferredTagWithClass(type, kUTTagClassMIMEType);
            CFRelease(type);
        }
        if (!mimeType) mimeType = CFRetain(CFSTR("application/octet-stream"));
        [davRequest setDataMIMEType:(NSString *)mimeType];
        CFRelease(mimeType);

        CKTransferRecord* transfer = [CKTransferRecord recordWithName:[path lastPathComponent] size:[data length]];

        self.progressHandler = ^(NSUInteger progress) {
            [transfer setProgress:progress];
        };

        self.completionHandler =  ^(id result) {
            CK2WebDAVLog(@"creating file done");
            [transfer transferDidFinish:transfer error:nil];
        };

        self.errorHandler = ^(NSError* error) {
            CK2WebDAVLog(@"creating file failed");
            [transfer transferDidFinish:transfer error:error];
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
        };
    }

    return self;
}

- (id)initForSettingResourceValues:(NSDictionary *)keyedValues ofItemWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    CK2WebDAVLog(@"setting resource values");

    return self;
}

- (void)start;
{
    CK2WebDAVLog(@"started");
    _queue.suspended = NO;
}

- (void)stop
{
    CK2WebDAVLog(@"stopped");
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

    if (self.progressHandler)
    {
        self.progressHandler(0);
    }
}

- (void)request:(DAVRequest *)aRequest didSucceedWithResult:(id)result;
{
    CK2WebDAVLog(@"webdav request succeeded");

    if (self.completionHandler)
    {
        self.completionHandler(result);
    }

    [self.client protocolDidFinish:self];
}

- (void)request:(DAVRequest *)aRequest didFailWithError:(NSError *)error;
{
    CK2WebDAVLog(@"webdav request failed");

    if (self.errorHandler)
    {
        self.errorHandler(error);
    }

    [self.client protocol:self didFailWithError:error];
}

- (void)webDAVRequest:(DAVRequest *)request didSendDataOfLength:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    CK2WebDAVLog(@"webdav sent data");

    if (self.progressHandler)
    {
        self.progressHandler(totalBytesWritten);
    }
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
    CK2WebDAVLog(sent ? @"< %@ " : @"> %@", string);

    [[self client] protocol:self appendString:string toTranscript:(sent ? CKTranscriptSent : CKTranscriptReceived)];
}

@end


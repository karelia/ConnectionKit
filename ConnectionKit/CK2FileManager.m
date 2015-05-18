//
//  CK2FileManager
//  Connection
//
//  Created by Mike on 08/10/2012.
//
//

#import "CK2FileManager.h"
#import "CK2FileOperation.h"
#import "CK2Protocol.h"

#import <objc/runtime.h>


NSString * const CK2FileMIMEType = @"CK2FileMIMEType";


#pragma mark -


@interface CK2FileOperation (Private) <CK2ProtocolClient>

- (id)initEnumerationOperationWithURL:(NSURL *)url
           includingPropertiesForKeys:(NSArray *)keys
                              options:(NSDirectoryEnumerationOptions)mask
                              manager:(CK2FileManager *)manager
                     enumerationBlock:(void (^)(NSURL *))enumBlock
                      completionBlock:(void (^)(NSError *))block;

- (id)initDirectoryCreationOperationWithURL:(NSURL *)url
                withIntermediateDirectories:(BOOL)createIntermediates
                          openingAttributes:(NSDictionary *)attributes
                                    manager:(CK2FileManager *)manager
                            completionBlock:(void (^)(NSError *))block;

- (id)initFileCreationOperationWithURL:(NSURL *)url
                                  data:(NSData *)data
           withIntermediateDirectories:(BOOL)createIntermediates
                     openingAttributes:(NSDictionary *)attributes
                               manager:(CK2FileManager *)manager
                         progressBlock:(CK2ProgressBlock)progressBlock
                       completionBlock:(void (^)(NSError *))block;

- (id)initFileCreationOperationWithURL:(NSURL *)remoteURL
                                  file:(NSURL *)localURL
           withIntermediateDirectories:(BOOL)createIntermediates
                     openingAttributes:(NSDictionary *)attributes
                               manager:(CK2FileManager *)manager
                         progressBlock:(CK2ProgressBlock)progressBlock
                       completionBlock:(void (^)(NSError *))block;

- (id)initRemovalOperationWithURL:(NSURL *)url
                          manager:(CK2FileManager *)manager
                  completionBlock:(void (^)(NSError *))block;

- (id)initRenameOperationWithSourceURL:(NSURL *)srcURL
                               newName:(NSString *)newName
                               manager:(CK2FileManager *)manager
                       completionBlock:(void (^)(NSError *))block;

- (id)initResourceValueSettingOperationWithURL:(NSURL *)url
                                        values:(NSDictionary *)keyedValues
                                       manager:(CK2FileManager *)manager
                               completionBlock:(void (^)(NSError *))block;

@end


@interface CK2Protocol (Internals)
+ (Class)classForURL:(NSURL *)url;    // only suitable for stateless calls to the protocol class
@end


#pragma mark -


NSString * const CK2URLSymbolicLinkDestinationKey = @"CK2URLSymbolicLinkDestination";

@interface CK2FileManager()
- (Class)classForOperation;
@end

@implementation CK2FileManager

#pragma mark Creating a File Manager

+ (CK2FileManager *)fileManagerWithDelegate:(id <CK2FileManagerDelegate>)delegate delegateQueue:(NSOperationQueue *)queue;
{
    return [[[self alloc] initWithDelegate:delegate delegateQueue:queue] autorelease];
}

- initWithDelegate:(id <CK2FileManagerDelegate>)delegate delegateQueue:(NSOperationQueue *)queue;
{
    if (self = [super init])
    {
        // Create our own serial queue if needed
        _delegateQueue = [queue retain];
        if (!_delegateQueue)
        {
            _delegateQueue = [[NSOperationQueue alloc] init];
            _delegateQueue.maxConcurrentOperationCount = 1;
        }
        
        self.delegate = delegate;
    }
    
    return self;
}

- init;
{
    return [self initWithDelegate:nil delegateQueue:nil];
}

- (void)dealloc {
    [_delegateQueue release];
    
    [super dealloc];
}

#pragma mark Discovering Directory Contents

- (CK2FileOperation *)contentsOfDirectoryAtURL:(NSURL *)url
      includingPropertiesForKeys:(NSArray *)keys
                         options:(NSUInteger)mask
               completionHandler:(void (^)(NSArray *, NSError *))block;
{
    NSMutableArray *contents = [[NSMutableArray alloc] init];
    
    CK2FileOperation * result = [self enumerateContentsOfURL:url includingPropertiesForKeys:keys options:(mask|NSDirectoryEnumerationSkipsSubdirectoryDescendants) usingBlock:^(NSURL *aURL) {
        
        [contents addObject:aURL];
        
    } completionHandler:^(NSError *error) {
        
        block((error ? nil : contents), // don't confuse clients should we have recieved only a partial listing
              error);
        
        [contents release];
    }];
    
    return result;
}

- (CK2FileOperation *)enumerateContentsOfURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSUInteger)mask usingBlock:(void (^)(NSURL *))block completionHandler:(void (^)(NSError *))completionBlock;
{
    NSParameterAssert(url);
    
    CK2FileOperation *operation = [[[self classForOperation] alloc] initEnumerationOperationWithURL:url
                                                                 includingPropertiesForKeys:keys
                                                                                    options:mask
                                                                                    manager:self
                                                                           enumerationBlock:block
                                                                            completionBlock:completionBlock];
    
    [operation resume];
    return [operation autorelease];
}

#pragma mark Creating and Deleting Items

- (CK2FileOperation *)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(url);
    
    CK2FileOperation *operation = [[[self classForOperation] alloc] initDirectoryCreationOperationWithURL:url
                                                                      withIntermediateDirectories:createIntermediates
                                                                                openingAttributes:attributes
                                                                                          manager:self
                                                                                  completionBlock:handler];
    
    [operation resume];
    return [operation autorelease];
}

- (CK2FileOperation *)createFileAtURL:(NSURL *)url contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *error))handler;
{
    CK2FileOperation *result = [self createFileOperationWithURL:url
                                                       fromData:data
                                    withIntermediateDirectories:createIntermediates
                                              openingAttributes:attributes
                                                  progressBlock:progressBlock
                                              completionHandler:handler];
    
    [result resume];
    return result;
}

- (CK2FileOperation *)createFileOperationWithURL:(NSURL *)url fromData:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes completionHandler:(void (^)(NSError *error))handler;
{
    return [self createFileOperationWithURL:url
                                   fromData:data
                withIntermediateDirectories:createIntermediates
                          openingAttributes:attributes
                              progressBlock:NULL
                          completionHandler:handler];
}

- (CK2FileOperation *)createFileOperationWithURL:(NSURL *)url fromData:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *))handler;
{
    CK2FileOperation *result = [[[self classForOperation] alloc] initFileCreationOperationWithURL:url
                                                                                             data:data
                                                                      withIntermediateDirectories:createIntermediates
                                                                                openingAttributes:attributes
                                                                                          manager:self
                                                                                    progressBlock:progressBlock
                                                                                  completionBlock:handler];
    
    return [result autorelease];
}

- (CK2FileOperation *)createFileAtURL:(NSURL *)destinationURL withContentsOfURL:(NSURL *)sourceURL withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *error))handler;
{
    CK2FileOperation *result = [self createFileOperationWithURL:destinationURL
                                                       fromFile:sourceURL
                                    withIntermediateDirectories:createIntermediates
                                              openingAttributes:attributes
                                                  progressBlock:progressBlock
                                              completionHandler:handler];
    
    [result resume];
    return result;
}

- (CK2FileOperation *)createFileOperationWithURL:(NSURL *)destinationURL fromFile:(NSURL *)sourceURL withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes completionHandler:(void (^)(NSError *error))handler;
{
    __block CK2FileOperation *result = [self createFileOperationWithURL:destinationURL
                                                               fromFile:sourceURL
                                            withIntermediateDirectories:createIntermediates
                                                      openingAttributes:attributes
                                                          progressBlock:^(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToSend) {
                                                              
                                                              id <CK2FileManagerDelegate> delegate = self.delegate;
                                                              if ([delegate respondsToSelector:@selector(fileManager:operation:didWriteBodyData:totalBytesWritten:totalBytesExpectedToWrite:)])
                                                              {
                                                                  [delegate fileManager:self
                                                                              operation:result
                                                                       didWriteBodyData:bytesWritten
                                                                      totalBytesWritten:totalBytesWritten
                                                              totalBytesExpectedToWrite:totalBytesExpectedToSend];
                                                              }
                                                          }
                                                      completionHandler:handler];
    return result;
}

- (CK2FileOperation *)createFileOperationWithURL:(NSURL *)destinationURL fromFile:(NSURL *)sourceURL withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *error))handler;
{
    CK2FileOperation *operation = [[[self classForOperation] alloc] initFileCreationOperationWithURL:destinationURL
                                                                                        file:sourceURL
                                                                 withIntermediateDirectories:createIntermediates
                                                                           openingAttributes:attributes
                                                                                     manager:self
                                                                               progressBlock:progressBlock
                                                                             completionBlock:handler];
    
    return [operation autorelease];
}

- (CK2FileOperation *)removeItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
{
    CK2FileOperation *operation = [self removeOperationWithURL:url completionHandler:handler];
    [operation resume];
    return operation;
}

- (CK2FileOperation *)removeOperationWithURL:(NSURL *)url completionHandler:(void (^)(NSError *))handler;
{
    CK2FileOperation *operation = [[[self classForOperation] alloc] initRemovalOperationWithURL:url manager:self completionBlock:handler];
    return [operation autorelease];
}

#pragma mark Renaming Items

- (CK2FileOperation *)renameItemAtURL:(NSURL *)srcURL toFilename:(NSString *)newName completionHandler:(void (^)(NSError *))handler
{
    CK2FileOperation *operation = [[[self classForOperation] alloc] initRenameOperationWithSourceURL:srcURL
                                                                                    newName:newName
                                                                                           manager:self
                                                                                   completionBlock:handler];
    
    [operation resume];
    return [operation autorelease];
}

#pragma mark Getting and Setting Attributes

- (CK2FileOperation *)setAttributesOperationWithURL:(NSURL *)url attributes:(NSDictionary *)keyedValues completionHandler:(void (^)(NSError *))handler {
    NSParameterAssert(url);
    NSParameterAssert(keyedValues);
    
    CK2FileOperation *operation = [[[self classForOperation] alloc] initResourceValueSettingOperationWithURL:url
                                                                                              values:keyedValues
                                                                                             manager:self
                                                                                     completionBlock:handler];
    
    return [operation autorelease];
}

#pragma mark Delegate

@synthesize delegate = _delegate;
@synthesize delegateQueue = _delegateQueue;

#pragma mark Operations

- (Class)classForOperation
{
    return [CK2FileOperation class];
}

- (void)cancelOperation:(CK2FileOperation *)operation;
{
    [operation cancel];
}

@end


@implementation CK2FileManager (URLs)

#pragma mark URLs

+ (NSURL *)URLWithPath:(NSString *)path isDirectory:(BOOL)isDir hostURL:(NSURL *)baseURL;
{
    NSParameterAssert(path);
    NSParameterAssert(baseURL);
    
    
    // Make a directory if demanded
    if (isDir && ![path hasSuffix:@"/"] && path.length)
    {
        path = [path stringByAppendingString:@"/"];
    }
    
    // Strip down to just host URL
    CFIndex length = CFURLGetBytes((CFURLRef)baseURL, NULL, 0);
    CFRange pathRange = CFURLGetByteRangeForComponent((CFURLRef)baseURL, kCFURLComponentPath, NULL);
    
    if (pathRange.location != kCFNotFound &&
        pathRange.location < length)
    {
        NSMutableData *data = [[NSMutableData alloc] initWithLength:pathRange.location];
        CFURLGetBytes((CFURLRef)baseURL, data.mutableBytes, pathRange.location);
        
        NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        baseURL = [NSURL URLWithString:string];
        
        [string release];
        [data release];
    }
    
    NSURL *result = [self URLWithPath:path relativeToURL:baseURL].absoluteURL;
    
    // Make sure is a directory if requested
    if (isDir) NSAssert(CFURLHasDirectoryPath((CFURLRef)result), @"Not a directory: %@", result);
    
    return result;
}

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

+ (NSString *)pathOfURL:(NSURL *)URL;
{
    Class protocolClass = [CK2Protocol classForURL:URL];
    if (!protocolClass) protocolClass = [CK2Protocol class];
    NSString *result = [protocolClass pathOfURLRelativeToHomeDirectory:URL];
    
    // Forcefully strip trailing slashes
    NSUInteger length = result.length;
    if (length >= 2) // ignore leading slash
    {
        NSRange searchRange = NSMakeRange(1, length - 1);   // ignore leading slash
        
        do
        {
            NSRange trailingSlashRange = [result rangeOfString:@"/"
                                                       options:NSBackwardsSearch|NSAnchoredSearch
                                                         range:searchRange];
            
            if (trailingSlashRange.location == NSNotFound) break;
            
            result = [result substringToIndex:trailingSlashRange.location];
            searchRange.length -= trailingSlashRange.length;
        }
        while (searchRange.length);
    }
    
    return result;
}

+ (void)setTemporaryResourceValue:(id)value forKey:(NSString *)key inURL:(NSURL *)url;
{
    // File URLs are already handled by the system
    // Ideally, would use CFURLSetTemporaryResourcePropertyForKey() first for all URLs as a test, but on 10.7.5 at least, it crashes with non-file URLs
    if ([url isFileURL])
    {
        CFURLSetTemporaryResourcePropertyForKey((CFURLRef)value, (CFStringRef)key, value);
    }
    else
    {
        [self setTemporaryResourceValueForKey:key inURL:url asBlock:^id{
            return value;
        }];
    }
}

// The block is responsible for returning the value on-demand
+ (void)setTemporaryResourceValueForKey:(NSString *)key inURL:(NSURL *)url asBlock:(id (^)(void))block;
{
    // Store the block as an associated object
    objc_setAssociatedObject(url, key, block, OBJC_ASSOCIATION_COPY);
    
    
    // Swizzle so getter method includes cache in its search
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        Class class = NSURL.class;
        Method originalMethod = class_getInstanceMethod(class, @selector(getResourceValue:forKey:error:));
        Method overrideMethod = class_getInstanceMethod(class, @selector(ck2_getResourceValue:forKey:error:));
        method_exchangeImplementations(originalMethod, overrideMethod);
    });
}

/*!
 @method         canHandleURL:
 
 @abstract
 Performs a "preflight" operation that performs some speculative checks to see if a URL has a suitable protocol registered to handle it.
 
 @discussion
 The result of this method is valid only as long as no protocols are registered or unregistered, and as long as the request is not mutated (if the request is mutable). Hence, clients should be prepared to handle failures even if they have performed request preflighting by calling this method.
 
 @param
 url     The URL to preflight.
 
 @result
 YES         if it is likely that the given request can be used to
 perform a file operation and the associated I/O can be
 started
 */
+ (BOOL)canHandleURL:(NSURL *)url;
{
    return ([CK2Protocol classForURL:url] != nil);
}

@end


#pragma mark -


@implementation NSURL (CK2TemporaryResourceProperties)

#pragma mark Getting and Setting File System Resource Properties

- (BOOL)ck2_getResourceValue:(out id *)value forKey:(NSString *)key error:(out NSError **)error;
{
    // Special case, as for the setter method
    if ([self isFileURL])
    {
        return [self ck2_getResourceValue:value forKey:key error:error];    // calls the original implementation
    }
    
    
    // See if key has been cached
    id (^block)(void) = objc_getAssociatedObject(self, key);
    
    if (block)
    {
        *value = block();
        return YES;
    }
    
    
    // A few special keys we generate on-demand pretty much by guessing since the server isn't up to providing that sort of info
        if ([key isEqualToString:NSURLHasHiddenExtensionKey])
        {
            *value = [NSNumber numberWithBool:NO];
            return YES;
        }
        else if ([key isEqualToString:NSURLLocalizedNameKey])
        {
            *value = [self lastPathComponent];
            return YES;
        }
        
        // Have to define NSURLPathKey as a macro for older releases:
#if (!defined MAC_OS_X_VERSION_10_8) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_8
#define NSURLPathKey @"_NSURLPathKey"
#endif
        else if ([key isEqualToString:NSURLPathKey])
        {
            *value = [CK2FileManager pathOfURL:self];
            return YES;
        }
#undef NSURLPathKey
        
        else if ([key isEqualToString:NSURLIsPackageKey])
        {
            NSString        *extension;
            
            *value = @NO;
            extension = [self pathExtension];
            
            if ([extension length] > 0)
            {
                NSArray         *baseUTIs;
                
                baseUTIs = (NSArray *)UTTypeCreateAllIdentifiersForTag(kUTTagClassFilenameExtension, (CFStringRef)extension, NULL);

                for (NSString *uti in baseUTIs)
                {
                    if (UTTypeConformsTo((CFStringRef)uti, CFSTR("com.apple.package")))
                    {
                        *value = @YES;
                        break;
                    }
                }
                
                [baseUTIs release];
            }
            
            return YES;
        }
        else
        {
            return [self ck2_getResourceValue:value forKey:key error:error];    // calls the original implementation
        }
    
    return YES;
}

@end

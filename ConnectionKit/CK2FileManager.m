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


@interface CK2Protocol (Internals)
+ (Class)classForURL:(NSURL *)url;    // only suitable for stateless calls to the protocol class
@end


#pragma mark -


NSString * const CK2URLSymbolicLinkDestinationKey = @"CK2URLSymbolicLinkDestination";

@interface CK2FileManager()
- (Class)classForOperation;
@end

@implementation CK2FileManager

#pragma mark Discovering Directory Contents

- (id)contentsOfDirectoryAtURL:(NSURL *)url
      includingPropertiesForKeys:(NSArray *)keys
                         options:(NSDirectoryEnumerationOptions)mask
               completionHandler:(void (^)(NSArray *, NSError *))block;
{
    NSMutableArray *contents = [[NSMutableArray alloc] init];
    
    id result = [self enumerateContentsOfURL:url includingPropertiesForKeys:keys options:(mask|NSDirectoryEnumerationSkipsSubdirectoryDescendants) usingBlock:^(NSURL *aURL) {
        
        [contents addObject:aURL];
        
    } completionHandler:^(NSError *error) {
        
        block((error ? nil : contents), // don't confuse clients should we have recieved only a partial listing
              error);
        
        [contents release];
    }];
    
    return result;
}

- (id)enumerateContentsOfURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask usingBlock:(void (^)(NSURL *))block completionHandler:(void (^)(NSError *))completionBlock;
{
    NSParameterAssert(url);
    
    CK2FileOperation *operation = [[[self classForOperation] alloc] initEnumerationOperationWithURL:url
                                                                 includingPropertiesForKeys:keys
                                                                                    options:mask
                                                                                    manager:self
                                                                           enumerationBlock:block
                                                                            completionBlock:completionBlock];
    return [operation autorelease];
}

#pragma mark Creating and Deleting Items

- (id)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(url);
    
    CK2FileOperation *operation = [[[self classForOperation] alloc] initDirectoryCreationOperationWithURL:url
                                                                      withIntermediateDirectories:createIntermediates
                                                                                openingAttributes:attributes
                                                                                          manager:self
                                                                                  completionBlock:handler];
    return [operation autorelease];
}

- (id)createFileAtURL:(NSURL *)url contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *error))handler;
{
    CK2FileOperation *operation = [[[self classForOperation] alloc] initFileCreationOperationWithURL:url
                                                                                        data:data
                                                                 withIntermediateDirectories:createIntermediates
                                                                           openingAttributes:attributes
                                                                                     manager:self
                                                                               progressBlock:progressBlock
                                                                             completionBlock:handler];
    
    return [operation autorelease];
}

- (id)createFileAtURL:(NSURL *)destinationURL withContentsOfURL:(NSURL *)sourceURL withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *error))handler;
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

- (id)removeItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
{
    CK2FileOperation *operation = [[[self classForOperation] alloc] initRemovalOperationWithURL:url manager:self completionBlock:handler];
    return [operation autorelease];
}

#pragma mark Renaming Items
- (BOOL)renameItemAtURL:(NSURL *)srcURL withName:(NSString *)newName completionHandler:(void (^)(NSError *))handler
{
    CK2FileOperation *operation = [[[self classForOperation] alloc] initRenameOperationWithSourceURL:srcURL
                                                                                    newName:newName
                                                                                           manager:self
                                                                                   completionBlock:handler];
    
    return [operation autorelease];
}

#pragma mark Getting and Setting Attributes

- (id)setAttributes:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(keyedValues);
    
    CK2FileOperation *operation = [[[self classForOperation] alloc] initResourceValueSettingOperationWithURL:url
                                                                                              values:keyedValues
                                                                                             manager:self
                                                                                     completionBlock:handler];
    return [operation autorelease];
}

#pragma mark Delegate

@synthesize delegate = _delegate;

#pragma mark Operations


- (Class)classForOperation
{
    return [CK2FileOperation class];
}

- (void)cancelOperation:(id)operation;
{
    [operation cancel];
}

@end


@implementation CK2FileManager (URLs)

#pragma mark URLs

+ (NSURL *)URLWithPath:(NSString *)path hostURL:(NSURL *)baseURL;
{
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
    
    return [self URLWithPath:path relativeToURL:baseURL].absoluteURL;
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
    return [protocolClass pathOfURLRelativeToHomeDirectory:URL];
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
            
            extension = [self pathExtension];
            
            if ([extension length] > 0)
            {
                if ([extension isEqual:@"app"])
                {
                    *value = @YES;
                    return YES;
                }
                else
                {
                    OSStatus        status;
                    
                    status = LSGetApplicationForInfo(kLSUnknownType, kLSUnknownCreator, (CFStringRef)extension, kLSRolesAll, NULL, NULL);
                    
                    if (status == kLSApplicationNotFoundErr)
                    {
                        *value = @NO;
                        return YES;
                    }
                    else if (status != noErr)
                    {
                        NSLog(@"Error getting app info for extension for URL %@: %s", [self absoluteString], GetMacOSStatusCommentString(status));
                    }
                    else
                    {
                        *value = @YES;
                        return YES;
                    }
                }
            }
            
            *value = @NO;
            return YES;
        }
        else
        {
            return [self ck2_getResourceValue:value forKey:key error:error];    // calls the original implementation
        }
    
    return YES;
}

@end

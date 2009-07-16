//
//  CKFSProtocol.m
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKConnectionProtocol1.h"

#import "CKLocalFileSystemProtocol.h"
#import "CKWebDAVProtocol.h"


@implementation CKFSProtocol

static NSMutableArray *sRegisteredClasses;

+ (void)initialize
{
    if (!sRegisteredClasses)
    {
        sRegisteredClasses = [[NSMutableArray alloc] init];
        
        // Register the built-in protocols. Use NSClassFromString() in case the code's been built without them included. Register S3 last so that it gets consulted *before* WebDAV.
        Class aProtocol = NSClassFromString(@"CKLocalFileSystemProtocol");
        if (aProtocol) [self registerClass:aProtocol];
        
        aProtocol = NSClassFromString(@"CKWebDAVProtocol");
        if (aProtocol) [self registerClass:aProtocol];
        
        aProtocol = NSClassFromString(@"CKAmazonS3Protocol");
        if (aProtocol) [self registerClass:aProtocol];
    }
}

+ (BOOL)registerClass:(Class)protocolClass
{
    BOOL result = [protocolClass isSubclassOfClass:[CKFSProtocol class]];
    if (result && [sRegisteredClasses indexOfObjectIdenticalTo:protocolClass] == NSNotFound)
    {
        [sRegisteredClasses addObject:protocolClass];
    }
    return result;
}

/*  Classes are consulted in reverse order of registration
 */
+ (Class)classForRequest:(NSURLRequest *)request
{
    NSEnumerator *classesEnumerator = [sRegisteredClasses reverseObjectEnumerator];
    Class aClass;
    while (aClass = [classesEnumerator nextObject])
    {
        if ([aClass canInitWithRequest:request])
        {
            return aClass;
        }
    }
    
    return nil;
}

#define SUBCLASS_RESPONSIBLE @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"%@ must implement %@", [self className], NSStringFromSelector(_cmd)] userInfo:nil];

+ (BOOL)canInitWithRequest:(NSURLRequest *)request;
{
    SUBCLASS_RESPONSIBLE;
    return NO;
}

#pragma mark -
#pragma mark Init & Dealloc

- (id)initWithRequest:(NSURLRequest *)request client:(id <CKFileTransferProtocolClient>)client
{
    NSParameterAssert(request);
    NSParameterAssert(client);
    
    [super init];
    
    _request = [request copy];
    _client = [client retain];
    
    return self;
}

- (void)dealloc
{
    [_request release];
    [_client release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark Accessors

@synthesize request = _request;
@synthesize client = _client;

#pragma mark -
#pragma mark Overall Connection

- (void)startConnection
{
    SUBCLASS_RESPONSIBLE;
}

- (void)stopConnection
{
    SUBCLASS_RESPONSIBLE;
}

#pragma mark -
#pragma mark File Operations

- (void)downloadContentsOfFileAtPath:(NSString *)remotePath
{
    SUBCLASS_RESPONSIBLE;
}

- (void)uploadData:(NSData *)data toPath:(NSString *)path
{
    SUBCLASS_RESPONSIBLE;
}

- (void)fetchContentsOfDirectoryAtPath:(NSString *)path
{
    SUBCLASS_RESPONSIBLE;
}

- (void)createDirectoryAtPath:(NSString *)path
{
    SUBCLASS_RESPONSIBLE;
}

- (void)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath
{
    SUBCLASS_RESPONSIBLE;
}

- (void)setPermissions:(unsigned long)posixPermissions ofItemAtPath:(NSString *)path
{
    SUBCLASS_RESPONSIBLE;
}

- (void)deleteItemAtPath:(NSString *)path
{
    SUBCLASS_RESPONSIBLE;
}

- (void)stopCurrentOperation
{
    SUBCLASS_RESPONSIBLE;
}

+ (id)propertyForKey:(NSString *)key inRequest:(CKFileRequest *)request
{
    NSDictionary *properties = [request performSelector:@selector(CK_extensibleProperties)];
    return [properties objectForKey:key];
}

+ (void)setProperty:(id)value forKey:(NSString *)key inRequest:(CKMutableFileRequest *)request
{
    NSMutableDictionary *properties = [request performSelector:@selector(CK_extensibleProperties)];
    [properties setObject:value forKey:key];
}

+ (void)removePropertyForKey:(NSString *)key inRequest:(CKMutableFileRequest *)request;
{
    NSMutableDictionary *properties = [request performSelector:@selector(CK_extensibleProperties)];
    [properties removeObjectForKey:key];
}

@end

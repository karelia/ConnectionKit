//
//  CKFileRequest.m
//  ConnectionKit
//
//  Created by Mike on 14/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFileRequest.h"
#import "CKFileTransferProtocol.h"


@interface CKFileRequest ()

@property(nonatomic, retain, setter=CK_setExtensibleProperties) id CK_extensibleProperties;
- (void)CK_setOperationType:(NSString *)type;
- (void)CK_setPath:(NSString *)path;

@end


#pragma mark -


@implementation CKFileRequest

#pragma mark Initialisation & Deallocation

+ (id)requestWithOperationType:(NSString *)type path:(NSString *)path
{
    return [[[self alloc] initWithOperationType:type path:path] autorelease];
}

- (id)initWithOperationType:(NSString *)type path:(NSString *)path
{
    [super init];
    
    [self CK_setOperationType:type];
    [self CK_setPath:path];
    
    return self;
}

- (id)init
{
    [NSException raise:NSInvalidArgumentException
                format:@"-[%@ init] is not a valid initializer", NSStringFromClass([self class])];
    
    [self release];
    return nil;
}

// Support for mutable subclass
- (id)CK_init { return [super init]; }

- (id)initWithRequest:(CKFileRequest *)request;
{
    [self initWithOperationType:[request operationType] path:[request path]];
    
    NSDictionary *properties = [[request CK_extensibleProperties] copy];
    [self CK_setExtensibleProperties:properties];
    [properties release];
    
    return self;
}

- (void)dealloc
{
    [_operationType release];
    [_path release];
    [_extensibleProperties release];
    
    [super dealloc];
}

#pragma mark Properties

@synthesize operationType = _operationType;
- (void)CK_setOperationType:(NSString *)type
{
    NSParameterAssert(type);
    
    type = [type copy];
    [_operationType release];
    _operationType = type;
}

@synthesize path = _path;
- (void)CK_setPath:(NSString *)path
{
    NSParameterAssert(path);
    NSParameterAssert([path isAbsolutePath]);
    
    path = [path copy];
    [_path release];
    _path = path;
}

- (NSString *)standardizedPath
{
    return [[self path] stringByStandardizingPath]; // FIXME: This could seriously screw up with local symlinks!!
}

- (NSData *)data
{
    return [CKFileTransferProtocol propertyForKey:@"CKData" inRequest:self];
}

- (NSString *)fileType
{
    return [CKFileTransferProtocol propertyForKey:@"CKFileType" inRequest:self];
}

// CKFileTransferProtocol will use this to get properties
@synthesize CK_extensibleProperties = _extensibleProperties;

#pragma mark Copying

- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

- (id)mutableCopyWithZone:(NSZone *)zone;
{
    return [[CKMutableFileRequest allocWithZone:zone] initWithRequest:self];
}

@end


#pragma mark -


@implementation CKMutableFileRequest

#pragma mark Initialisation & Deallocation

- (id)initWithOperationType:(NSString *)type path:(NSString *)path
{
    [super initWithOperationType:type path:path];
    
    NSMutableDictionary *properties = [[NSMutableDictionary alloc] init];
    [self CK_setExtensibleProperties:properties];
    [properties release];
    
    return self;
}

// Overridden as we need a mutable properties dict
- (id)initWithRequest:(CKFileRequest *)request;
{
    [self initWithOperationType:[request operationType] path:[request path]];
    
    NSMutableDictionary *properties = [self CK_extensibleProperties];
    [properties addEntriesFromDictionary:[request CK_extensibleProperties]];
    
    return self;
}

#pragma mark Properties

@dynamic operationType;
- (void)setOperationType:(NSString *)type
{
    [self CK_setOperationType:type];
}

@dynamic path;
- (void)setPath:(NSString *)path
{
    [self CK_setPath:path];
}
                      
- (void)setData:(NSData *)data fileType:(NSString *)UTI;
{
    NSParameterAssert(data);
    // UTI can be nil for "unknown." Protocol must choose how to deal with it, generally falling back to something like binary/octet-stream
    
    data = [data copy];
    [CKFileTransferProtocol setProperty:data forKey:@"CKData" inRequest:self];
    [data release];
    
    if (UTI)
    {
        UTI = [UTI copy];
        [CKFileTransferProtocol setProperty:UTI forKey:@"CKFileType" inRequest:self];
        [UTI release];
    }
    else
    {
        [CKFileTransferProtocol removePropertyForKey:@"CKFileType" inRequest:self];
    }
}

#pragma mark Copying

- (id)copyWithZone:(NSZone *)zone;
{
    return [[CKMutableFileRequest allocWithZone:zone] initWithRequest:self];
}

@end

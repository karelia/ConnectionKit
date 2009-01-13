//
//  CKConnectionRequest.m
//  Connection
//
//  Created by Mike on 13/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKConnectionRequest.h"


const NSTimeInterval CKConnectionRequestDefaultTimeoutInterval = 60.0;


@implementation CKConnectionRequest

+ (id)requestWithURL:(NSURL *)URL
{
    return [[[self alloc] initWithURL:URL
                      timeoutInterval:CKConnectionRequestDefaultTimeoutInterval] autorelease];
}

+ (id)requestWithURL:(NSURL *)URL timeoutInterval:(NSTimeInterval)timeoutInterval
{
    return [[[self alloc] initWithURL:URL timeoutInterval:timeoutInterval] autorelease];
}

- (id)_initWithURL:(NSURL *)URL timeoutInterval:(NSTimeInterval)timeoutInterval extensibleProperties:(NSDictionary *)extensibleProperties
{
    [super init];
    
    _URL = [URL copy];
    _timeoutInterval = timeoutInterval;
    _extensibleProperties = [extensibleProperties retain];
    
    return self;
}

- (id)initWithURL:(NSURL *)URL
{
    return [self initWithURL:URL timeoutInterval:CKConnectionRequestDefaultTimeoutInterval];
}

- (id)initWithURL:(NSURL *)URL timeoutInterval:(NSTimeInterval)timeoutInterval
{
    NSParameterAssert(URL);
    return [self _initWithURL:URL timeoutInterval:timeoutInterval extensibleProperties:nil];
}

- (NSURL *)URL { return _URL; }

- (NSTimeInterval)timeoutInterval { return _timeoutInterval; }

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];   // We're immutable. Mutable subclass reimplements this
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
    NSMutableDictionary *extensibleProperties =
        (_extensibleProperties) ? [_extensibleProperties mutableCopy] : [[NSMutableDictionary alloc] init];
    
    CKMutableConnectionRequest *result = [[CKMutableConnectionRequest alloc] _initWithURL:[self URL]
                                                                          timeoutInterval:[self timeoutInterval]
                                                                     extensibleProperties:extensibleProperties];
    
    [extensibleProperties release];
    return result;
}

@end


#pragma mark -


@implementation CKMutableConnectionRequest

- (id)initWithURL:(NSURL *)URL timeoutInterval:(NSTimeInterval)timeoutInterval
{
    NSParameterAssert(URL);
    
    // We reimplement this method so that extensible properties are mutable
    NSDictionary *extensibleProperties = [[NSMutableDictionary alloc] init];
    
    self = [self _initWithURL:URL
              timeoutInterval:timeoutInterval
         extensibleProperties:extensibleProperties];
    
    [extensibleProperties release];
    return self;
}

- (void)setURL:(NSURL *)URL
{
    NSParameterAssert(URL);
    
    URL = [URL copy];
    [_URL release];
    _URL = URL;
}

- (void)setTimeoutInterval:(NSTimeInterval)seconds { _timeoutInterval = seconds; }

- (id)copyWithZone:(NSZone *)zone
{
    // Our superclass is immutable so we have to re-implement this method
    NSDictionary *extensibleProperties = [_extensibleProperties copy];
    
    CKConnectionRequest *result = [[CKConnectionRequest alloc] _initWithURL:[self URL]
                                                            timeoutInterval:[self timeoutInterval]
                                                       extensibleProperties:extensibleProperties];
    
    [extensibleProperties release];
    return result;
}

@end


#pragma mark -


@implementation CKConnectionRequest (CKURLRequestExtensibility)

- (id)propertyForKey:(NSString *)key
{
    return [_extensibleProperties objectForKey:key];
}

@end


@implementation CKMutableConnectionRequest (CKURLRequestExtensibility)

- (void)setProperty:(id)value forKey:(NSString *)key
{
    [(NSMutableDictionary *)_extensibleProperties setObject:value forKey:key];
}

- (void)removePropertyForKey:(NSString *)key
{
    [(NSMutableDictionary *)_extensibleProperties removeObjectForKey:key];
}

@end



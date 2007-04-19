//
//  CKCacheableHost.m
//  Connection
//
//  Created by Greg Hulands on 16/02/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "CKCacheableHost.h"

static NSMutableDictionary *sCachedHosts = nil;
static NSLock *sCacheLock = nil;

@implementation CKCacheableHost

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	sCachedHosts = [[NSMutableDictionary alloc] initWithCapacity:32];
	sCacheLock = [[NSRecursiveLock alloc] init];
	
	[pool release];
}

+ (NSHost *)hostWithName:(NSString *)name
{
	NSHost *host = nil;
	
	[sCacheLock lock];
	host = [sCachedHosts objectForKey:name];
	[sCacheLock unlock];
	
	if (!host && (nil != name))
	{
		host = [NSHost hostWithName:name];
		if ( nil == host ) return nil;
		// kvo hack
		[host setValue:[NSArray arrayWithObject:name] forKey:@"names"];
		[sCacheLock lock];
		[sCachedHosts setObject:host forKey:name];
		[sCacheLock unlock];
	}
	return host;
}

+ (NSHost *)hostWithAddress:(NSString *)address
{
	NSHost *host = nil;
	
	[sCacheLock lock];
	host = [sCachedHosts objectForKey:address];
	[sCacheLock unlock];
	
	if (!host)
	{
		host = [NSHost hostWithName:address];
		if ( nil == host ) return nil;
		// kvo hack
		[host setValue:[NSArray arrayWithObject:address] forKey:@"addresses"];
		[sCacheLock lock];
		[sCachedHosts setObject:host forKey:address];
		[sCacheLock unlock];
	}
	return host;
}

@end

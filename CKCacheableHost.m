//
//  CKCacheableHost.m
//  Connection
//
//  Created by Greg Hulands on 16/02/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "CKCacheableHost.h"
#import "AbstractConnection.h"

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
		NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
		host = [NSHost hostWithName:name];
		NSTimeInterval end = [NSDate timeIntervalSinceReferenceDate];
		
		if ( nil == host ) return nil;
		
		KTLog(TransportDomain, KTLogDebug, @"Resolved hostWithName:%@ in %g seconds", name, end - start);
		
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
		NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
		host = [NSHost hostWithName:address];
		NSTimeInterval end = [NSDate timeIntervalSinceReferenceDate];
		
		if ( nil == host ) return nil;
		
		KTLog(TransportDomain, KTLogDebug, @"Resolved hostWithName:%@ in %g seconds", address, end - start);
		
		// kvo hack
		[host setValue:[NSArray arrayWithObject:address] forKey:@"addresses"];
		[sCacheLock lock];
		[sCachedHosts setObject:host forKey:address];
		[sCacheLock unlock];
	}
	return host;
}

@end

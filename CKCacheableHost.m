/*
 Copyright (c) 2007, Greg Hulands <ghulands@mac.com>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

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

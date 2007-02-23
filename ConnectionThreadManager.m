//
//  ConnectionThreadManager.m
//  Connection
//
//  Created by Greg Hulands on 4/07/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "ConnectionThreadManager.h"
#import "KTLog.h"
#import "InterThreadMessaging.h"
#import "AbstractConnection.h"

@interface ConnectionThreadManager (Private)
- (void)processTasks;
@end

enum {
	CHECK_TASKS = 1
};

static ConnectionThreadManager *_default = nil;
static NSLock *_initLock = nil;

@implementation ConnectionThreadManager

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	_initLock = [[NSLock alloc] init];
	[pool release];
}

+ (id)defaultManager 
{
	[_initLock lock];
	if (!_default)
	{
		_default = [[ConnectionThreadManager alloc] init];
	}
	[_initLock unlock];
	return _default;
}

- (id)init
{
	if (self = [super init])
	{
		myLock = [[NSLock alloc] init];
		myTasks = [[NSMutableArray alloc] init];
		myPort = [[NSPort port] retain];
		[myPort setDelegate:self];
		
		[NSThread detachNewThreadSelector:@selector(connectionFrameworkThread:) toTarget:self withObject:nil];
	}
	return self;
}

- (void)dealloc
{
	[myLock release];
	[myTasks release];
	
	[super dealloc];
}

- (void)connectionFrameworkThread:(id)unused
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	myBgThread = [NSThread currentThread];
	[NSThread prepareForConnectionInterThreadMessages];
	
	[[NSRunLoop currentRunLoop] addPort:myPort forMode:NSDefaultRunLoopMode];
	
	// NOTE: this may be leaking ... there are two retains going on here.  Apple bug report #2885852, still open since 2002!
	// But then again, we can't remove the thread, so it really doesn't mean much.	
	NSDate *backToTheFuture = [NSDate distantFuture];
	
	while (1)
	{		
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:backToTheFuture];
	}
	
	[pool release];
}

#pragma mark -
#pragma mark Threading Support

- (void)sendPortMessage:(int)aMessage
{
	if (nil != myPort)
	{
		NSPortMessage *message = [[NSPortMessage alloc] initWithSendPort:myPort
															 receivePort:myPort components:nil];
		[message setMsgid:aMessage];
		
		@try {
			if ([NSThread currentThread] != myBgThread)
			{
				BOOL sent = [message sendBeforeDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
				if (!sent)
				{
					KTLog(ThreadingDomain, KTLogFatal, @"ConnectionThreadManager couldn't send message %d", aMessage);
				}
			}
			else
			{
				[self handlePortMessage:message];
			}
		} @catch (NSException *ex) {
			KTLog(ThreadingDomain, KTLogError, @"%@", ex);
			// if we fail to send it is usually because the queueing is occurring on the main thread. so we can actually just use the runloop to repost
			[self performSelector:@selector(runloopResend:) withObject:[NSNumber numberWithInt:aMessage] afterDelay:0.0];
		} @finally {
			[message release];
		} 
	}
}

- (void)runloopResend:(NSNumber *)msg
{
	[self sendPortMessage:[msg intValue]];
}

- (void)handlePortMessage:(NSPortMessage *)portMessage
{
    int message = [portMessage msgid];
	
	switch (message)
	{
		case CHECK_TASKS:
		{
			[self processTasks];
		}
	}
}

- (void)processTasks
{
	[myLock lock];
	NSArray *tasks = [[myTasks copy] autorelease];
	[myTasks removeAllObjects];
	[myLock unlock];
	NSEnumerator *e = [tasks objectEnumerator];
	NSInvocation *cur;
	
	while (cur = [e nextObject])
	{
		@try {
			[cur invoke];
			[[cur target] release];
		}
		@catch (NSException *ex) {
			KTLog(ThreadingDomain, KTLogDebug, @"Exception caught when invoking: %@\n %@", cur, ex);
			NSLog(@"Exception caught when invoking: %@\n %@", cur, ex);
		}
	}
	
}

- (void)scheduleInvocation:(NSInvocation *)inv
{
	[myLock lock];
	[myTasks addObject:inv];
	[myLock unlock];
	
	if ([NSThread currentThread] != myBgThread)
	{
		[self sendPortMessage:CHECK_TASKS];
	}
	else
	{
		[self processTasks];
	}
}

- (id)prepareWithInvocationTarget:(id)target
{
	[myLock lock];
	[myTarget release];
	myTarget = [target retain];
	return self;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
	NSMethodSignature *sig = [super methodSignatureForSelector:aSelector];
	if (!sig)
	{
		sig = [myTarget methodSignatureForSelector:aSelector];
	}
	return sig;
}

- (void)forwardInvocation:(NSInvocation *)inv
{
	[inv setTarget:myTarget];
	[inv retainArguments];
	myTarget = nil;
	[myLock unlock];
	
	[self scheduleInvocation:inv];
	//[self performSelector:@selector(scheduleInvocation:) withObject:inv afterDelay:0.0];
}

@end

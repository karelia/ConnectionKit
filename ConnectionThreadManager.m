/*
 Copyright (c) 2006, Greg Hulands <ghulands@mac.com>
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
				BOOL sent = [message sendBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.0]];
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
		// we want to do this the next time through the runloop
		[self performSelector:@selector(processTasks)
				   withObject:nil
				   afterDelay:0.0];
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

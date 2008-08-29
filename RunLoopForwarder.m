/*
 
 RunLoopForwarder.m
 Marvel
 
 Copyright (c) 2004-2006 Karelia Software. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Karelia Software nor the names of its contributors may be used to 
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

#import "RunLoopForwarder.h"
#import "InterThreadMessaging.h"

@implementation RunLoopForwarder

- (id)init
{
	if (self = [super init]) {
		lock = [[NSRecursiveLock alloc] init];
		createdOnThread = [NSThread currentThread];
		[NSThread prepareForConnectionInterThreadMessages];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(threadWillDie:)
													 name:NSThreadWillExitNotification
												   object:createdOnThread];
		useMainThread = NO;
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[lock release];
	[super dealloc];
}

- (void)threadWillDie:(NSNotification *)n
{
	[lock lock];
	createdOnThread = nil;
	[lock unlock];
}

- (void) setDelegate:(id)aDelegate
{
//	if (![lock tryLock])
//	{
//		[self performSelector:@selector(setDelegate:)
//				   withObject:aDelegate
//				   afterDelay:0.0];
//		return;
//	}
	[lock lock];
	myDelegate = aDelegate;
	[lock unlock];
}

- (void) setReturnValueDelegate:(id)delegate
{
	[lock lock];
	returnValueDelegate = delegate;
	[lock unlock];
}

- (void) setUseMainThread:(BOOL)flag
{
	[lock lock];
	useMainThread = flag;
	createdOnThread = nil;
	[lock unlock];
}

/*!	Take an invocation that didn't get recognized ... pretty much every one ... and run it on the main thread's runloop.
*/
- (void) forwardInvocation: (NSInvocation *)anInvocation
{
	[lock lock];
	SEL aSelector = [anInvocation selector];
	if ([myDelegate respondsToSelector:aSelector])
	{
		[anInvocation retainArguments];

		if ([[anInvocation methodSignature] methodReturnLength] == 0)
		{
			if (useMainThread)
			{
				[anInvocation performSelectorOnMainThread:@selector(invokeWithTarget:)
											   withObject:myDelegate
											waitUntilDone:NO];
			}
			else if ([NSThread currentThread] == createdOnThread)
			{
				[anInvocation performSelector:@selector(invokeWithTarget:)
								   withObject:myDelegate];
			}
			else
			{
				[anInvocation performSelector:@selector(invokeWithTarget:)
								   withObject:myDelegate
									 inThread:createdOnThread];
			}
		} 
		else 
		{
			//we need to get the return value
			unsigned int length = [[anInvocation methodSignature] methodReturnLength];
			void * buffer = (void *)malloc(length);
			[anInvocation performSelectorOnMainThread:@selector(invokeWithTarget:) 
										   withObject:myDelegate 
										waitUntilDone:YES];
			[anInvocation getReturnValue:buffer];
			[returnValueDelegate runloopForwarder:self returnedValue:buffer];
			free (buffer);
		}
	}
	[lock unlock];
}

- (NSMethodSignature *) methodSignatureForSelector:(SEL)aSelector
{
	NSMethodSignature *result = nil;
	[lock lock];
	if (myDelegate)
	{
		result = [myDelegate methodSignatureForSelector:aSelector];
	}
	if (!result)
	{
		result = [super methodSignatureForSelector:aSelector];	// allow this class to also respond
	}
	[lock unlock];
	return result;
}

- (IMP)methodForSelector:(SEL)aSelector
{
	IMP implementation = NULL;
	[lock lock];
	if (myDelegate)
	{
		implementation = [myDelegate methodForSelector:aSelector];
	}
	if (!implementation)
	{
		implementation = [super methodForSelector:aSelector];
	}
	[lock unlock];
	return implementation;
}

- (BOOL)respondsToSelector:(SEL)selector
{
	BOOL result = NO;
	[lock lock];
	if (myDelegate)
	{
		result = [myDelegate respondsToSelector:selector];
	}
	if (!result)
	{
		result = [super respondsToSelector:selector];
	}
	[lock unlock];
	return result;
}

@end


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

#import "CKInternalTransferRecord.h"
#import "RunLoopForwarder.h"
#import "NSObject+Connection.h"

@implementation CKInternalTransferRecord

+ (id)recordWithLocal:(NSString *)localPath
				 data:(NSData *)data
			   offset:(unsigned long long)offset
			   remote:(NSString *)remote
			 delegate:(id)delegate
			 userInfo:(id)ui
{
	return [[[CKInternalTransferRecord alloc] initWithLocal:localPath
													   data:data
													 offset:offset
													 remote:remote
												   delegate:delegate
												   userInfo:ui] autorelease];
}

- (id)initWithLocal:(NSString *)localPath
			   data:(NSData *)data
			 offset:(unsigned long long)offset
			 remote:(NSString *)remote
		   delegate:(id)delegate
		   userInfo:(id)ui
{
	if ((self = [super init]))
	{
		myLocalPath = [localPath copy];
		myRemotePath = [remote copy];
		myData = [data retain];
		myOffset = offset;
		myDelegate = [delegate retain];
		/* Why retain this delegate?  If an app only uses the original upload/download methods that don't take a delegate, then internally the delegate will be created which is a CKTR. If the internal transfer record doesn't retain it then you can see that when the transfer starts up, the delegate will be a dangling pointer and will crash. Because the internal transfer record is a private class, convention doesn't have to apply.
		*/

		myForwarder = [[RunLoopForwarder alloc] init];
		[myForwarder setUseMainThread:YES];
		[myForwarder setDelegate:myDelegate];
		myUserInfo = [ui retain];
		
		myFlags.didBegin = [myDelegate respondsToSelector:@selector(transferDidBegin:)];
		myFlags.didFinish = [myDelegate respondsToSelector:@selector(transferDidFinish:error:)];
		myFlags.error = [myDelegate respondsToSelector:@selector(transfer:didReceiveError:)];
		myFlags.percent = [myDelegate respondsToSelector:@selector(transfer:progressedTo:)];
		myFlags.progressed = [myDelegate respondsToSelector:@selector(transfer:transferredDataOfLength:)];
		
		myProperties = [[NSMutableDictionary alloc] initWithCapacity:8];
	}
	return self;
}

- (void)dealloc
{
	[myDelegate release];
	[myLocalPath release];
	[myRemotePath release];
	[myData release];
	[myUserInfo release];
	[myForwarder release];
	[myProperties release];
	
	[super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
	CKInternalTransferRecord *copy = [[[self class] alloc] initWithLocal:myLocalPath
																	data:myData
																  offset:myOffset
																  remote:myRemotePath
																delegate:myDelegate
																userInfo:myUserInfo];
	return copy;
}

- (NSString *)localPath
{
	return myLocalPath;
}

- (NSData *)data
{
	return myData;
}

- (unsigned long long)offset
{
	return myOffset;
}

- (void)setRemotePath:(NSString *)path
{
	[myRemotePath autorelease];
	myRemotePath = [path copy];
}

- (NSString *)remotePath
{
	return myRemotePath;
}

- (id)delegate
{
	return myForwarder;
}

- (void)setUserInfo:(id)ui
{
	[myUserInfo autorelease];
	myUserInfo = [ui retain];
}

- (id)userInfo
{
	return myUserInfo;
}

- (BOOL)delegateRespondsToTransferDidBegin
{
	return myFlags.didBegin;
}

- (BOOL)delegateRespondsToTransferProgressedTo
{
	return myFlags.percent;
}

- (BOOL)delegateRespondsToTransferTransferredData
{
	return myFlags.progressed;
}

- (BOOL)delegateRespondsToTransferDidFinish
{
	return myFlags.didFinish;
}

- (BOOL)delegateRespondsToError
{
	return myFlags.error;
}

- (NSString *)description
{
	NSMutableString *str = [NSMutableString stringWithFormat:@"%@ <0x%06x>\n", [self className], self];
	
	[str appendFormat:@"Local: %@\n", myLocalPath];
	[str appendFormat:@"Remote: %@\n", myRemotePath];
	[str appendFormat:@"Data: %@\n", [myData shortDescription]];
	[str appendFormat:@"Offset: %lld", myOffset];
	
	return str;
}

- (void)setObject:(id)object forKey:(id)key
{
	[myProperties setObject:object forKey:key];
}

- (id)objectForKey:(id)key
{
	return [myProperties objectForKey:key];
}

@end

//
//  CKInternalTransferRecord.m
//  Connection
//
//  Created by Greg Hulands on 27/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

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
		myFlags.didFinish = [myDelegate respondsToSelector:@selector(transferDidFinish:)];
		myFlags.error = [myDelegate respondsToSelector:@selector(transfer:didReceiveError:)];
		myFlags.percent = [myDelegate respondsToSelector:@selector(transfer:progressedTo:)];
		myFlags.progressed = [myDelegate respondsToSelector:@selector(transfer:transferredDataOfLength:)];
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

@end

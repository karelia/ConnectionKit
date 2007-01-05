//
//  CKInternalTransferRecord.h
//  Connection
//
//  Created by Greg Hulands on 27/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class RunLoopForwarder;

@interface CKInternalTransferRecord : NSObject <NSCopying>
{
	NSString	*myLocalPath;
	NSString	*myRemotePath;
	NSData		*myData;
	unsigned long long myOffset;
	RunLoopForwarder *myForwarder;
	id			myDelegate;
	id			myUserInfo;
	
	struct __ckinternaltransferrecordflags {
		unsigned didBegin: 1;
		unsigned didFinish: 1;
		unsigned error: 1;
		unsigned percent: 1;
		unsigned progressed: 1;
		
		unsigned unused: 27;
	} myFlags;
}

+ (id)recordWithLocal:(NSString *)localPath
				 data:(NSData *)data
			   offset:(unsigned long long)offset
			   remote:(NSString *)remote
			 delegate:(id)delegate
			 userInfo:(id)ui;

- (id)initWithLocal:(NSString *)localPath
				 data:(NSData *)data
			   offset:(unsigned long long)offset
			   remote:(NSString *)remote
			 delegate:(id)delegate
		   userInfo:(id)ui;

- (NSString *)localPath;
- (NSData *)data;
- (unsigned long long)offset;
- (NSString *)remotePath;
- (id)delegate;

- (void)setUserInfo:(id)ui;
- (id)userInfo;

- (BOOL)delegateRespondsToTransferDidBegin;
- (BOOL)delegateRespondsToTransferProgressedTo;
- (BOOL)delegateRespondsToTransferTransferredData;
- (BOOL)delegateRespondsToTransferDidFinish;
- (BOOL)delegateRespondsToError;

@end

@interface CKInternalTransferRecord (Private)
- (void)setRemotePath:(NSString *)path;
@end

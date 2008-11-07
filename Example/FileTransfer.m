//
//  FileTransfer.m
//  FTPConnection
//
//  Created by Greg Hulands on 24/11/05.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "FileTransfer.h"


@implementation FileTransfer

+ (id)uploadFile:(NSString *)local to:(NSString *)remote
{
	FileTransfer *transfer =  [[[FileTransfer alloc] initWithType:UploadType
									 localFile:local
									remoteFile:remote] autorelease];
  
  [transfer setSize: [NSNumber numberWithUnsignedLongLong: [[[NSFileManager defaultManager] fileAttributesAtPath: local
                                                                                                    traverseLink: NO] fileSize]]];
  
  return transfer;
}

+ (id)downloadFile:(NSString *)remote to:(NSString *)local
{
	return [[[FileTransfer alloc] initWithType:DownloadType
									 localFile:local
									remoteFile:remote] autorelease];
}

+ (id)deleteFile:(NSString *)remote
{
	return [[[FileTransfer alloc] initWithType: DeleteType
                                   localFile: nil
                                  remoteFile: remote] autorelease];
}

- (id)initWithType:(TransferType)type localFile:(NSString *)local remoteFile:(NSString *)remote
{
	[super init];
	_type = type;
	_local = [local copy];
	_remote = [remote copy];
  _transferred = [NSNumber numberWithInt: 0];
	return self;
}

- (void)dealloc
{
	[_local release];
	[_remote release];
	[_size release];
	[_percent release];
	[_transferred release];
	[super dealloc];
}

- (void)setLocalFile:(NSString *)local
{
	[_local autorelease];
	_local = [local copy];
}

- (void)setRemoteFile:(NSString *)remote
{
	[_remote autorelease];
	_remote = [remote copy];
}

- (void)setSize:(NSNumber *)size
{
	[_size autorelease];
	_size = [size copy];
}

- (void)setPercentTransferred:(NSNumber *)percent
{
	[_percent autorelease];
	_percent = [percent copy];
}

- (void)setAmountTransferred:(NSNumber *)transferred
{
	[_transferred autorelease];
	_transferred = [transferred copy];
}

- (NSString *)localFile
{
	return _local;
}

- (NSString *)remoteFile
{
	return _remote;
}

- (NSNumber *)size
{
	return _size;
}

- (NSNumber *)percentTransferred
{
	if (_completed)
		return [NSNumber numberWithInt:100];
	return _percent;
}

- (NSNumber *)amountTransferred
{
	return _transferred;
}

- (void)setCompleted:(BOOL)flag
{
	_completed = flag;
}

- (BOOL)isCompleted
{
	return _completed;
}

- (void)setType:(TransferType)type
{
	_type = type;
}

- (TransferType)type
{
	return _type;
}

- (NSString *)description
{
	NSMutableString *d = [NSMutableString stringWithString:@"File Transfer\n"];
	[d appendFormat:@"Local File: %@\n", _local];
	[d appendFormat:@"Remote File: %@\n", _remote];
  
	if (_type == DownloadType)
		[d appendString:@"is Download"];
	else if (_type == UploadType)
		[d appendString:@"is Upload"];
	else
		[d appendString:@"is Delete"];
  
	[d appendFormat:@" transfered: %@\n", [self amountTransferred]];

  
	return d;
}
@end

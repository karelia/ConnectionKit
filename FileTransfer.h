//
//  FileTransfer.h
//  FTPConnection
//
//  Created by Greg Hulands on 24/11/05.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

// This is just a wrapper around the notion of a file transfer

#import <Cocoa/Cocoa.h>

typedef enum {
	UploadType = 0,
	DownloadType,
  DeleteType
} TransferType;

@interface FileTransfer : NSObject 
{
	TransferType _type;
	NSString *_local;
	NSString *_remote;
	NSNumber *_size;
	NSNumber *_percent;
	NSNumber *_transferred;
	BOOL	_completed;
}

+ (id)uploadFile:(NSString *)local to:(NSString *)remote;
+ (id)downloadFile:(NSString *)remote to:(NSString *)local;
+ (id)deleteFile:(NSString *)remote;

- (id)initWithType:(TransferType)type localFile:(NSString *)local remoteFile:(NSString *)remote;

- (void)setLocalFile:(NSString *)local;
- (void)setRemoteFile:(NSString *)remote;
- (void)setSize:(NSNumber *)size;
- (void)setPercentTransferred:(NSNumber *)percent;
- (void)setAmountTransferred:(NSNumber *)transferred;
- (void)setCompleted:(BOOL)flag;
- (void)setType:(TransferType)type;
- (TransferType)type;

- (BOOL)isCompleted;
- (NSString *)localFile;
- (NSString *)remoteFile;
- (NSNumber *)size;
- (NSNumber *)percentTransferred;
- (NSNumber *)amountTransferred;

@end

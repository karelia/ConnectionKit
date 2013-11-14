//
//  CKUploader.h
//  Connection
//
//  Created by Mike Abdullah on 14/11/2011.
//  Copyright (c) 2011 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CK2FileManager.h"
#import "CKTransferRecord.h"


enum {
    CKUploadingDeleteExistingFileFirst = 1 << 0,
    CKUploadingDryRun = 1 << 1,
};
typedef NSUInteger CKUploadingOptions;


@protocol CKUploaderDelegate;


@interface CKUploader : NSObject <CK2FileManagerDelegate>
{
  @private
	NSURLRequest        *_request;
    unsigned long       _permissions;
    NSUInteger          _maxConcurrentOperationCount;
    CKUploadingOptions  _options;
    
    CK2FileManager      *_fileManager;
    NSMutableArray      *_queue;
    
    CKTransferRecord    *_rootRecord;
    CKTransferRecord    *_baseRecord;
    
    BOOL    _isFinishing;
    BOOL    _isCancelled;
    
    id <CKUploaderDelegate> _delegate;
}

// File permissions default to 0644. Supply a non-nil value if you want something different, or override -posixPermissionsForPath:isDirectory:
+ (CKUploader *)uploaderWithRequest:(NSURLRequest *)request
               filePosixPermissions:(NSNumber *)customPermissions
                            options:(CKUploadingOptions)options;

@property (nonatomic) NSUInteger maxConcurrentOperationCount;   // defaults to 1
@property (nonatomic, assign, readonly) CKUploadingOptions options;
@property (nonatomic, assign) id <CKUploaderDelegate> delegate;

- (CKTransferRecord *)uploadFileAtURL:(NSURL *)url toPath:(NSString *)path;
- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path;
- (void)removeFileAtPath:(NSString *)path;

@property (nonatomic, retain, readonly) CKTransferRecord *rootTransferRecord;
@property (nonatomic, retain, readonly) CKTransferRecord *baseTransferRecord;

- (void)finishUploading;    // will disconnect once all files are uploaded
- (void)cancel;             // bails out as quickly as possible

// The permissions given to uploaded files
- (unsigned long)posixPermissionsForPath:(NSString *)path isDirectory:(BOOL)directory;
+ (unsigned long)posixPermissionsForDirectoryFromFilePermissions:(unsigned long)filePermissions;

@end


@protocol CKUploaderDelegate <NSObject>

- (void)uploaderDidFinishUploading:(CKUploader *)uploader;
- (void)uploader:(CKUploader *)uploader didFailWithError:(NSError *)error;

- (void)uploader:(CKUploader *)uploader didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(CK2AuthChallengeDisposition, NSURLCredential *))completionHandler;

@optional
- (void)uploader:(CKUploader *)uploader didAddTransferRecord:(CKTransferRecord *)record;
@required
- (void)uploader:(CKUploader *)uploader didBeginUploadToPath:(NSString *)path;

- (void)uploader:(CKUploader *)uploader appendString:(NSString *)string toTranscript:(CK2TranscriptType)transcript;

@optional
- (BOOL)uploader:(CKUploader *)uploader shouldProceedAfterError:(NSError *)error;

@end

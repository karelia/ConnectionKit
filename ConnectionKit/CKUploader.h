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
    CKUploadingOptions  _options;
    
    CK2FileManager      *_fileManager;
    NSMutableArray      *_queue;
    NSMutableDictionary *_recordsByOperation;
    
    CKTransferRecord    *_rootRecord;
    CKTransferRecord    *_baseRecord;
    
    BOOL    _invalidated;
    BOOL    _suspended;
    
    id <CKUploaderDelegate> _delegate;
}

/**
 File permissions are supplied by curl_curl_newFilePermissions. Supply a
 non-`nil` value if you want something different, or override
 `-posixPermissionsForPath:isDirectory:`
 */
+ (CKUploader *)uploaderWithRequest:(NSURLRequest *)request
                            options:(CKUploadingOptions)options
                           delegate:(id <CKUploaderDelegate>)delegate;

@property (nonatomic, copy, readonly) NSURLRequest *baseRequest;
@property (nonatomic, assign, readonly) CKUploadingOptions options;
@property (nonatomic, retain, readonly) id <CKUploaderDelegate> delegate; // retained until invalidated

- (CKTransferRecord *)uploadFileAtURL:(NSURL *)url toPath:(NSString *)path;
- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)path;
- (void)removeItemAtURL:(NSURL *)url __attribute((nonnull));
- (void)removeFileAtPath:(NSString *)path;

/**
 The underlying `CK2FileOperation`s that are in the queue.
 */
- (NSArray *)operations;

@property (nonatomic, retain, readonly) CKTransferRecord *rootTransferRecord;
@property (nonatomic, retain, readonly) CKTransferRecord *baseTransferRecord;

- (void)finishOperationsAndInvalidate;    // will disconnect once all files are uploaded
- (void)invalidateAndCancel;             // bails out as quickly as possible


#pragma mark Suspending Operations
@property (nonatomic, getter=isSuspended) BOOL suspended;


#pragma mark Permissions
// The permissions given to uploaded files
- (NSNumber *)posixPermissionsForPath:(NSString *)path isDirectory:(BOOL)directory;


@end


@protocol CKUploaderDelegate <NSObject>

- (void)uploader:(CKUploader *)uploader didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(CK2AuthChallengeDisposition, NSURLCredential *))completionHandler;

@optional
- (void)uploader:(CKUploader *)uploader didAddTransferRecord:(CKTransferRecord *)record;
@required
- (void)uploader:(CKUploader *)uploader didBeginUploadToPath:(NSString *)path;

- (void)uploader:(CKUploader *)uploader appendString:(NSString *)string toTranscript:(CK2TranscriptType)transcript;

@optional
- (void)uploader:(CKUploader *)uploader transferRecord:(CKTransferRecord *)record shouldProceedAfterError:(NSError *)error completionHandler:(void (^)(BOOL proceed))completionHandler;

- (void)uploader:(CKUploader *)uploader transferRecord:(CKTransferRecord *)record
                                      didWriteBodyData:(int64_t)bytesSent
                                     totalBytesWritten:(int64_t)totalBytesSent
                             totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToSend;

- (void)uploader:(CKUploader *)uploader transferRecord:(CKTransferRecord *)record
                                  didCompleteWithError:(NSError *)error;

- (void)uploaderDidBecomeInvalid:(CKUploader *)uploader;

- (void)uploader:(CKUploader *)uploader didFailWithError:(NSError *)error;  // never called any more

@end

//
//  CK2FileOperation.h
//  Connection
//
//  Created by Mike on 22/03/2013.
//
//

#import "CK2FileManager.h"

@class CK2Protocol;


typedef NS_ENUM(NSInteger, CK2FileOperationState) {
    CK2FileOperationStateRunning = 0,                     /* The operation is currently being serviced by the file manager */
    CK2FileOperationStateSuspended = 1,                   /* The operation is yet to start. */
    CK2FileOperationStateCanceling = 2,                   /* The operation has been told to cancel and will complete shortly. */
    CK2FileOperationStateCompleted = 3,                   /* The operation has completed and the file manager will receive no more delegate notifications */
};


@class CK2FileOperationCallbacks;

/**
 All @properties are KVO-compliant.
*/
@interface CK2FileOperation : NSObject <NSCopying>  // retains self when copying
{
  @private
    CK2FileManager  *_manager;
    NSURL           *_originalURL;
    NSString        *_descriptionForErrors;
    dispatch_queue_t    _queue;
    
    CK2Protocol *_protocol;
    CK2FileOperationCallbacks   *_callbacks;
    
    void    (^_completionBlock)(NSError *);
    void    (^_enumerationBlock)(NSURL *);
    NSURL   *_localURL;
    
    int64_t _bytesWritten;
    int64_t _bytesExpectedToWrite;
    CK2ProgressBlock    _progressBlock;
    
    // Temporary hack which gets us to fire off extra directory creating requests should the main op fail
    BOOL    _createIntermediateDirectories;
    
    CK2FileOperationState   _state;
    NSError                 *_error;
}

/**
 @return a deep copy of the original connection request.
 
 You can think of this as the "primary" URL for a given operation. Normally this is fairly obvious:
 if uploading, it's the URL being uploaded to. When we come to support downloads, it's the URL being
 downloaded from.
 
 This can potentially get a bit tricky doing something like renaming/moving a file; in which case,
 this URL will be that of the _source_ file.
 
 ConnectionKit doesn't currently support redirects, but were it to, this URL would remain constant
 and we'd likely introduce a new `currentURL` property for retrieving the redirected URL if need be.
 */
@property (readonly, copy) NSURL *originalURL;

/**
 * Number of body bytes already written.
 *
 * Excludes any headers, such as in HTTP messages, or FTP control connection.
 */
@property (readonly) int64_t countOfBytesWritten;

/**
 * Number of body bytes we expect to write.
 *
 * Excludes any headers, such as in HTTP messages, or FTP control connection.
 */
@property (readonly) int64_t countOfBytesExpectedToWrite;

/**
 * `-cancel` returns immediately, but marks an operation as being canceled.
 * The operation will signal its completion handler with an
 * error value of `{ NSURLErrorDomain, NSURLErrorCancelled }`.  In some
 * cases, the operation may signal other work before it acknowledges the
 * cancelation.
 */
- (void)cancel;

/**
 * The current state of the operation.
 */
@property (readonly) CK2FileOperationState state;

/**
 * The error, if any. Also delivered to completion handler.
 * This property will be `nil` in the event that no error occured.
 */
@property (readonly, copy) NSError *error;

/**
 Sets an operation going if it hasn't already.
 */
- (void)resume;

@end

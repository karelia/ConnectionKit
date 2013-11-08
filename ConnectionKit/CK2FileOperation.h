//
//  CK2FileOperation.h
//  Connection
//
//  Created by Mike on 22/03/2013.
//
//

#import "CK2FileManager.h"


@class CK2Protocol;
@interface CK2FileOperation : NSObject
{
  @private
    CK2FileManager  *_manager;
    NSURL           *_URL;
    NSString        *_descriptionForErrors;
    dispatch_queue_t    _queue;
    
    CK2Protocol     *_protocol;
    
    void    (^_completionBlock)(NSError *);
    void    (^_enumerationBlock)(NSURL *);
    NSURL   *_localURL;
    
    BOOL        _cancelled;
    NSError     *_error;
}

/**
 * `-cancel` returns immediately, but marks an operation as being canceled.
 * The operation will signal its completion handler with an
 * error value of `{ NSURLErrorDomain, NSURLErrorCancelled }`.  In some
 * cases, the operation may signal other work before it acknowledges the
 * cancelation.
 */
- (void)cancel;

/**
 * The error, if any. Also delivered to completion handler.
 * This property will be `nil` in the event that no error occured.
 */
@property (readonly, copy) NSError *error;

@end

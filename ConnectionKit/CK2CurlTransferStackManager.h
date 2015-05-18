//
//  CK2CurlTransferStackManager.h
//  Connection
//
//  Created by Mike on 23/03/2015.
//
//

#import <CURLHandle/CURLHandle.h>


/**
 This is a little wrapper around a CURLTransferStack. We use it to tie each CK2FileManager to a
 transfer stack, and invalidate that stack when appropriate.
 */
@interface CK2CurlTransferStackManager : NSObject {
    CURLTransferStack   *_transferStack;
}

/**
 The manager automatically creates a transfer stack for itself
 */
@property(nonatomic, readonly) CURLTransferStack *transferStack;

@end

//
//  CK2CurlTransferStackManager.m
//  Connection
//
//  Created by Mike on 23/03/2015.
//
//

#import "CK2CurlTransferStackManager.h"

@implementation CK2CurlTransferStackManager

- (instancetype)init {
    if (self = [super init]) {
        _transferStack = [CURLTransferStack transferStackWithDelegate:nil delegateQueue:nil];
    }
    return self;
}

- (void)dealloc {
    // We're being torn down, so figure now is the time to invalidate transfer stack. Crude, but
    // there you go.
    [self.transferStack finishTransfersAndInvalidate];
    
    [super dealloc];
}

@synthesize transferStack = _transferStack;

@end

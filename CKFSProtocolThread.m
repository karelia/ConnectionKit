//
//  CKFSProtocolThread.m
//  ConnectionKit
//
//  Created by Mike on 16/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKFSProtocolThread.h"


@implementation CKFSProtocolThread

static NSThread *sFSProtocolThread;

+ (void)initialize
{
    if (!sFSProtocolThread)
    {
        sFSProtocolThread = [[CKFSProtocolThread alloc] init];
        [sFSProtocolThread start];
    }
}

+ (NSThread *)FSProtocolThread
{
    return sFSProtocolThread;
}

- (void)main
{
    // No need to do anything!
}

@end

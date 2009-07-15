//
//  CK_AsyncOperation.m
//  ConnectionKit
//
//  Created by Mike on 15/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CK_AsyncOperation.h"


@implementation CK_AsyncOperation

- (void)start
{
    [self willChangeValueForKey:@"isExecuting"];
    _isExecuting = YES;
    [self didChangeValueForKey:@"isExecuting"];
    
    [self main];
}

- (BOOL)isFinished { return _isFinished; }

- (BOOL)isExecuting { return _isExecuting; }

- (BOOL)isConcurrent { return YES; }

- (void)operationDidFinish
{
    // Mark as finished etc.
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    _isExecuting = NO;
    _isFinished = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

@end

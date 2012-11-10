//
//  CK2QueueProxy.m
//  Connection
//
//  Created by Mike on 10/11/2012.
//
//

#import "CK2QueueProxy.h"

@implementation CK2QueueProxy

- (id)initWithOperationQueue:(NSOperationQueue *)queue;
{
    return [self initWithDispatchBlock:^(void(^block)(void)) {
        [queue addOperationWithBlock:block];
    }];
}

- (id)initWithDispatchQueue:(dispatch_queue_t)queue;
{
    return [self initWithDispatchBlock:^(void(^block)(void)) {
        dispatch_async(queue, block);
    }];
}

- (id)initWithDispatchBlock:(void (^)(void(^block)(void)))block;
{
    if (self = [self init])
    {
        _dispatchBlock = [block copy];
    }
    return self;
}

- (void)addOperationWithBlock:(void (^)(void))block;
{
    _dispatchBlock(block);
}

@end

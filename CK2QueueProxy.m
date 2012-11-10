//
//  CK2QueueProxy.m
//  Connection
//
//  Created by Mike on 10/11/2012.
//
//

#import "CK2QueueProxy.h"

@implementation CK2QueueProxy

+ (instancetype)currentQueue;
{
    // Create a block that submits blocks to what looks the best match to be the current queue
    NSOperationQueue *queue = [NSOperationQueue currentQueue];
    if (queue)
    {
        return [[[self alloc] initWithOperationQueue:queue] autorelease];
    }
    else
    {
        dispatch_queue_t queue = dispatch_get_current_queue();
        NSAssert(queue, @"dispatch_get_current_queue unexpectedly claims there is no current queue");
        return [[[self alloc] initWithDispatchQueue:queue] autorelease];
    }
}

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

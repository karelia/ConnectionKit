/*-*- Mode: ObjC; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4  -*-*/
/*
 * InterThreadMessaging -- InterThreadMessaging.m
 * Created by toby on Tue Jun 19 2001.
 *
 */

#import <pthread.h>
#import "InterThreadMessaging.h"


/* There are four types of messages that can be posted between threads: a
   notification to be posted to the default notification centre and selectors
   to be performed with a varying number of arguments.  (I was tempted to
   implement all three in terms of performSelector:withObject:withObject:
   and passing in nil for the empty arguments, but then it occurred to me
   that perhaps the receiver has overridden performSelector: and
   performSelector:withObject:.  So I think I must disambiguate between
   them all.) */

typedef enum ConnectionInterThreadMessageType ConnectionInterThreadMessageType;
enum ConnectionInterThreadMessageType
{
    kITMPostNotification = 1,
    kITMPerformSelector0Args,
    kITMPerformSelector1Args,
    kITMPerformSelector2Args
};


/* The message contents are carried between threads in this struct.  The
   struct is allocated in the sending thread and freed in the receiving thread.
   It is carried between the threads in an NSPortMessage - the NSPortMessage
   contains a single NSData argument, which is a wrapper around the pointer to
   this struct. */

typedef struct ConnectionInterThreadMessage ConnectionInterThreadMessage;
struct ConnectionInterThreadMessage
{
    ConnectionInterThreadMessageType type;
    union {
        NSNotification *notification;
        struct {
            SEL selector;
            id receiver;
            id arg1;
            id arg2;
        } sel;
    } data;
};

@interface NSThread (ConnectionSecretStuff)
- (NSRunLoop *) runLoop;
@end

/* Each thread is associated with an NSPort.  This port is used to deliver
   messages to the target thread. */

static NSMapTable *pThreadMessagePorts = NULL;
static pthread_mutex_t pGate = { 0 };

@interface ConnectionInterThreadManager : NSObject
+ (void) threadDied:(NSNotification *)notification;
+ (void) handlePortMessage:(NSPortMessage *)msg;
@end

static void
ConnectionCreateMessagePortForThread (NSThread *thread, NSRunLoop *runLoop)
{
    NSPort *port;

    assert(nil != thread);
    assert(nil != runLoop);
	if (!pThreadMessagePorts)
	{
		[ConnectionInterThreadManager class];
	}
    assert(NULL != pThreadMessagePorts);

    pthread_mutex_lock(&pGate);

    port = NSMapGet(pThreadMessagePorts, thread);
    if (nil == port) {
        port = [[NSPort allocWithZone:NULL] init];
        [port setDelegate:[ConnectionInterThreadManager class]];
        [port scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
        NSMapInsertKnownAbsent(pThreadMessagePorts, thread, port);

        /* Transfer ownership of this port to the map table. */
        [port release];
    }

    pthread_mutex_unlock(&pGate);
}

static NSPort *
ConnectionMessagePortForThread (NSThread *thread)
{
    NSPort *port;

    assert(nil != thread);
	if (!pThreadMessagePorts)
	{
		[ConnectionInterThreadManager class];
	}
    assert(NULL != pThreadMessagePorts);

    pthread_mutex_lock(&pGate);
    port = NSMapGet(pThreadMessagePorts, thread);
    pthread_mutex_unlock(&pGate);

	if (nil == port)
	{
		ConnectionCreateMessagePortForThread(thread,
											 [thread runLoop]);
		pthread_mutex_lock(&pGate);
		port = NSMapGet(pThreadMessagePorts, thread);
		pthread_mutex_unlock(&pGate);
	}
	
    if (nil == port) {
        [NSException raise:NSInvalidArgumentException
                     format:@"Thread %@ is not prepared to receive "
                            @"inter-thread messages.  You must invoke "
                            @"+prepareForConnectionInterThreadMessages first.", thread];
    }

    return port;
}

static void
ConnectionRemoveMessagePortForThread (NSThread *thread, NSRunLoop *runLoop)
{
    NSPort *port;

    assert(nil != thread);
	if (!pThreadMessagePorts)
	{
		[ConnectionInterThreadManager class];
	}
    assert(NULL != pThreadMessagePorts);

    pthread_mutex_lock(&pGate);
    
    port = (NSPort *) NSMapGet(pThreadMessagePorts, thread);
    if (nil != port) {
        [port removeFromRunLoop:runLoop forMode:NSDefaultRunLoopMode];
        NSMapRemove(pThreadMessagePorts, thread);
    }

    pthread_mutex_unlock(&pGate);
}

@implementation NSThread (ConnectionInterThreadMessaging)

+ (void) prepareForConnectionInterThreadMessages
{
    /* Force the class initialization. */
    [ConnectionInterThreadManager class];

    ConnectionCreateMessagePortForThread([NSThread currentThread],
                               [NSRunLoop currentRunLoop]);
}

@end

@implementation ConnectionInterThreadManager

+ (void) initialize
{
    /* Create the mutex - this should be invoked by the Objective-C runtime
       (in a thread-safe manner) before any one can use this module, so I
       don't think I need to worry about race conditions here. */
    if (nil == pThreadMessagePorts) {
        pthread_mutex_init(&pGate, NULL);

        pThreadMessagePorts =
            NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks,
                             NSObjectMapValueCallBacks, 0);

        [[NSNotificationCenter defaultCenter]
            addObserver:[self class]
            selector:@selector(threadDied:)
            name:NSThreadWillExitNotification
            object:nil];
    }
}

+ (void) threadDied:(NSNotification *)notification
{
    NSThread *thread;
    NSRunLoop *runLoop;

    thread = [notification object];
    runLoop = [thread runLoop];
    if (nil != runLoop) {
        ConnectionRemoveMessagePortForThread(thread, [thread runLoop]);
    }
}

+ (void) handlePortMessage:(NSPortMessage *)portMessage
{
    ConnectionInterThreadMessage *msg;
    NSArray *components;
    NSData *data;

    components = [portMessage components];
    assert(1 == [components count]);

    data = [components objectAtIndex:0];
    msg = *((ConnectionInterThreadMessage **) [data bytes]);
    
    switch (msg->type)
    {
        case kITMPostNotification:
            [[NSNotificationCenter defaultCenter]
                postNotification:msg->data.notification];
            [msg->data.notification release];
            break;

        case kITMPerformSelector0Args:
            [msg->data.sel.receiver performSelector:msg->data.sel.selector];
            [msg->data.sel.receiver release];
            break;

        case kITMPerformSelector1Args:
            [msg->data.sel.receiver performSelector:msg->data.sel.selector
                                    withObject:msg->data.sel.arg1];
            [msg->data.sel.receiver release];
            [msg->data.sel.arg1 release];
            break;

        case kITMPerformSelector2Args:
            [msg->data.sel.receiver performSelector:msg->data.sel.selector
                                    withObject:msg->data.sel.arg1
                                    withObject:msg->data.sel.arg2];
            [msg->data.sel.receiver release];
            [msg->data.sel.arg1 release];
            [msg->data.sel.arg2 release];
            break;

        default:
            assert(0);
    }

    free(msg);
}

@end





static void
ConnectionPostMessage (ConnectionInterThreadMessage *message, NSThread *thread, NSDate *limitDate)
{
    NSPortMessage *portMessage;
    NSMutableArray *components;
    NSPort *port;
    NSData *data;
    BOOL retval;

    if (nil == thread) { thread = [NSThread currentThread]; }
    port = ConnectionMessagePortForThread(thread);
    assert(nil != port);

    data = [[NSData alloc] initWithBytes:&message length:sizeof(void *)];
    components = [[NSMutableArray alloc] initWithObjects:&data count:1];
    portMessage = [[NSPortMessage alloc] initWithSendPort:port
                                         receivePort:nil
                                         components:components];

    if (nil == limitDate) { limitDate = [NSDate distantFuture]; }
    retval = [portMessage sendBeforeDate:limitDate];
    [portMessage release];
    [components release];
    [data release];

    if (!retval) {
        [NSException raise:NSPortTimeoutException
                     format:@"Can't send message to thread %@: timeout "
                            @"before date %@", thread, limitDate];
    }
}

static void
ConnectionPerformSelector (ConnectionInterThreadMessageType type, SEL selector, id receiver,
                 id object1, id object2, NSThread *thread, NSDate *limitDate)
{
    ConnectionInterThreadMessage *msg;

    assert(NULL != selector);
    
    if (nil != receiver) {
        msg = (ConnectionInterThreadMessage *) malloc(sizeof(struct ConnectionInterThreadMessage));
        bzero(msg, sizeof(struct ConnectionInterThreadMessage));
        msg->type = type;
        msg->data.sel.selector = selector;
        msg->data.sel.receiver = [receiver retain];
        msg->data.sel.arg1 = [object1 retain];
        msg->data.sel.arg2 = [object2 retain];

        ConnectionPostMessage(msg, thread, limitDate);
    }
}

static void
ConnectionPostNotification (NSNotification *notification, NSThread *thread,
                  NSDate *limitDate)
{
    ConnectionInterThreadMessage *msg;

    assert(nil != notification);
    
    msg = (ConnectionInterThreadMessage *) malloc(sizeof(struct ConnectionInterThreadMessage));
    bzero(msg, sizeof(struct ConnectionInterThreadMessage));
    msg->type = kITMPostNotification;
    msg->data.notification = [notification retain];

    ConnectionPostMessage(msg, thread, limitDate);
}






@implementation NSObject (ConnectionInterThreadMessaging)

- (void) performSelector:(SEL)selector
         inThread:(NSThread *)thread
{
    ConnectionPerformSelector(kITMPerformSelector0Args, selector, self, nil, nil,
                    thread, nil);
}

- (void) performSelector:(SEL)selector
         inThread:(NSThread *)thread
         beforeDate:(NSDate *)limitDate
{
    ConnectionPerformSelector(kITMPerformSelector0Args, selector, self, nil, nil,
                    thread, limitDate);
}

- (void) performSelector:(SEL)selector
         withObject:(id)object
         inThread:(NSThread *)thread
{
    ConnectionPerformSelector(kITMPerformSelector1Args, selector, self, object, nil,
                    thread, nil);
}

- (void) performSelector:(SEL)selector
         withObject:(id)object
         inThread:(NSThread *)thread
         beforeDate:(NSDate *)limitDate
{
    ConnectionPerformSelector(kITMPerformSelector1Args, selector, self, object, nil,
                    thread, limitDate);
}

- (void) performSelector:(SEL)selector
         withObject:(id)object1
         withObject:(id)object2
         inThread:(NSThread *)thread
{
    ConnectionPerformSelector(kITMPerformSelector2Args, selector, self, object1, object2,
                    thread, nil);
}

- (void) performSelector:(SEL)selector
         withObject:(id)object1
         withObject:(id)object2
         inThread:(NSThread *)thread
         beforeDate:(NSDate *)limitDate
{
    ConnectionPerformSelector(kITMPerformSelector2Args, selector, self, object1, object2,
                    thread, limitDate);
}

@end



@implementation NSNotificationCenter (ConnectionInterThreadMessaging)

- (void) postNotification:(NSNotification *)notification
         inThread:(NSThread *)thread
{
    ConnectionPostNotification(notification, thread, nil);
}

- (void) postNotification:(NSNotification *)notification
         inThread:(NSThread *)thread
         beforeDate:(NSDate *)limitDate
{
    ConnectionPostNotification(notification, thread, limitDate);
}

- (void) postNotificationName:(NSString *)name
         object:(id)object
         inThread:(NSThread *)thread
{
    NSNotification *notification;
    
    notification = [NSNotification notificationWithName:name
                                   object:object
                                   userInfo:nil];
    ConnectionPostNotification(notification, thread, nil);
}

- (void) postNotificationName:(NSString *)name
         object:(id)object
         inThread:(NSThread *)thread
         beforeDate:(NSDate *)limitDate
{
    NSNotification *notification;
    
    notification = [NSNotification notificationWithName:name
                                   object:object
                                   userInfo:nil];
    ConnectionPostNotification(notification, thread, limitDate);
}

- (void) postNotificationName:(NSString *)name
         object:(id)object
         userInfo:(NSDictionary *)userInfo
         inThread:(NSThread *)thread
{
    NSNotification *notification;
    
    notification = [NSNotification notificationWithName:name
                                   object:object
                                   userInfo:userInfo];
    ConnectionPostNotification(notification, thread, nil);
}

- (void) postNotificationName:(NSString *)name
         object:(id)object
         userInfo:(NSDictionary *)userInfo
         inThread:(NSThread *)thread
         beforeDate:(NSDate *)limitDate
{
    NSNotification *notification;
    
    notification = [NSNotification notificationWithName:name
                                   object:object
                                   userInfo:userInfo];
    ConnectionPostNotification(notification, thread, limitDate);
}

@end



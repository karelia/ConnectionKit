/*-*- Mode: ObjC; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4  -*-*/
/*
 * InterThreadMessaging -- InterThreadMessaging.h
 * Created by toby on Tue Jun 19 2001.
 *
 * A low-cost-but-not-quite-as-general alternative to D.O.
 *
 */

#import <Foundation/Foundation.h>


@interface NSThread (ConnectionInterThreadMessaging)

/* The inter-thread messaging category methods use NSPorts to deliver messages
   between threads.  In order to receive an inter-thread message, the receiver
   must both (1) be running a run loop; and (2) be monitoring this port in its
   run loop.  You must call this method from the context of the thread you wish
   to prepare for inter-thread messages (which is why these are class methods).

   Before a thread can receive any inter-thread messages, it must invoke one
   of the following methods to prepare the thread and its run loop to receive
   these messages.  In order to process a message from another thread, the
   receiving thread must, of course, be running its run loop. */

+ (void) prepareForConnectionInterThreadMessages; // in NSDefaultRunLoopMode

@end



/* Invoke in the specified thread a method on an object.  The target
   thread must have been readied for inter-thread messages by invoking
   +prepareForConnectionInterThreadMessages.  It must be running its run loop in
   order to receive the messages.

   In some situations, a sender may be able to blast messages to an object
   faster than they can be processed in the target thread.  To prevent things
   from spiraling out of control, the underlying NSPorts implement a throtling
   mechanism in the form of a fixed queue size.  When this queue is filled, all
   further messages are rejected until until a message has been pulled off the
   queue.  The sender may specify a limit date; if the queue is full, the
   sender will block until this limit date expires or until space is made in
   the queue.  An NSPortTimeoutException exception is thrown if the limit date
   expires (or if no limit date is specified) before the message can be
   delivered.

   There is one very important point to watch out for: to prevent heinously
   difficult to debug memory smashers, the receing object and all of its
   arguments are retained in the context of the sending thread.  When the
   message has been delivered in the target thread, these objects are auto-
   released IN THE CONTEXT OF THE TARGET THREAD.  Thus, it is possible for
   the objects to be deallocated in a thread different from the one they were
   allocated in.  (In general, you don't need to worry about simple/immutable
   objects, such as NSString, NSData, etc.) */

@interface NSObject (ConnectionInterThreadMessaging)

- (void) performSelector:(SEL)selector
         inThread:(NSThread *)thread;	// before date [NSDate distantFuture]

- (void) performSelector:(SEL)selector
         inThread:(NSThread *)thread
         beforeDate:(NSDate *)limitDate;

- (void) performSelector:(SEL)selector
         withObject:(id)object
         inThread:(NSThread *)thread;	// before date [NSDate distantFuture]

- (void) performSelector:(SEL)selector
         withObject:(id)object
         inThread:(NSThread *)thread
         beforeDate:(NSDate *)limitDate;

- (void) performSelector:(SEL)selector
         withObject:(id)object1
         withObject:(id)object2
         inThread:(NSThread *)thread;	// before date [NSDate distantFuture]

- (void) performSelector:(SEL)selector
         withObject:(id)object1
         withObject:(id)object2
         inThread:(NSThread *)thread
         beforeDate:(NSDate *)limitDate;

@end




/* Post a notification in the specified thread.  The target thread must
   have been readied for inter-thread messages by sending itself the
   +prepareForConnectionInterThreadMessages.  It must be running its run loop in
   order to receive the messages.

   In some situations, a sender may be able to blast messages to an object
   faster than they can be processed in the target thread.  To prevent things
   from spiraling out of control, the underlying NSPorts implement a throtling
   mechanism in the form of a fixed queue size.  When this queue is filled, all
   further messages are rejected until until a message has been pulled off the
   queue.  The sender may specify a limit date; if the queue is full, the
   sender will block until this limit date expires or until space is made in
   the queue.  An NSPortTimeoutException exception is thrown if the limit date
   expires (or if no limit date is specified) before the message can be
   delivered.

   There is one very important point to watch out for: to prevent heinously
   difficult to debug memory smashers, the notification object (and
   consequently the userInfo dictionary) are retained in the context of
   the sending thread.  When the message has been delivered in the target
   thread, the notification object is auto-released IN THE CONTEXT OF THE
   TARGET THREAD.  Thus, it is possible for objects to be deallocated in a
   thread different from the one they were allocated in.  (In general, you
   don't need to worry about simple/immutable objects, such as NSString,
   NSData, etc.) */

@interface NSNotificationCenter (ConnectionInterThreadMessaging)

- (void) postNotification:(NSNotification *)notification
         inThread:(NSThread *)thread;	// before date [NSDate distantFuture]

- (void) postNotification:(NSNotification *)notification
         inThread:(NSThread *)thread
         beforeDate:(NSDate *)limitDate;

- (void) postNotificationName:(NSString *)name
         object:(id)object
         inThread:(NSThread *)thread;	// before date [NSDate distantFuture]

- (void) postNotificationName:(NSString *)name
         object:(id)object
         inThread:(NSThread *)thread
         beforeDate:(NSDate *)limitDate;

- (void) postNotificationName:(NSString *)name
         object:(id)object
         userInfo:(NSDictionary *)userInfo
         inThread:(NSThread *)thread;	// before date [NSDate distantFuture]

- (void) postNotificationName:(NSString *)name
         object:(id)object
         userInfo:(NSDictionary *)userInfo
         inThread:(NSThread *)thread
         beforeDate:(NSDate *)limitDate;

@end


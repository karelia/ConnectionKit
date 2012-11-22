/* 
 Copyright (c) 2004-2006 Karelia Software. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Karelia Software nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 */

#import <Foundation/Foundation.h>

@interface NSObject ( Connection )

- (NSString *)shortDescription;

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

- (void) performSelector:(SEL)selector
              withObject:(id)object
                inThread:(NSThread *)thread;	// before date [NSDate distantFuture]


@end

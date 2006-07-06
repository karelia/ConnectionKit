//
//  ConnectionThreadManager.h
//  Connection
//
//  Created by Greg Hulands on 4/07/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface ConnectionThreadManager : NSObject 
{
	NSLock			*myLock;
	NSMutableArray	*myTasks;
	
	NSPort			*myPort;
	NSThread		*myBgThread;
	id				myTarget;
}

+ (id)defaultManager;
- (id)prepareWithInvocationTarget:(id)target;

@end

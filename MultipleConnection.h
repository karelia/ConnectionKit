//
//  MultipleConnection.h
//  FTPConnection
//
//  Created by Greg Hulands on 9/01/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AbstractQueueConnection.h"

/* 
	A mutliple connection is where you can have different types of connections
	that all need to transfer the exact same set of data. It will coordinate
	all the connections and provide delegate notifications as if it were a single
	connection. This class does not register itself as it is a wrapper class and
	does not service any one particular protocol and therefore is used programmatically.
*/

@interface MultipleConnection : AbstractQueueConnection 
{
	NSMutableArray *_connections;
}

// Designated initializer
- (id)init;

- (void)addConnection:(id<AbstractConnectionProtocol>)connection;
- (void)removeConnection:(id<AbstractConnectionProtocol>)connection;
- (NSArray *)connections;

@end

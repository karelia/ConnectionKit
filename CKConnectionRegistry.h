//
//  CKConnectionRegistry.h
//  Connection
//
//  Created by Mike on 05/12/2008.
//  Copyright 2008 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CKConnectionProtocol.h"


@interface CKConnectionRegistry : NSObject
{
    @private
    NSMutableDictionary *_connectionClassesByName;
    NSMutableDictionary *_connectionClassesByURLScheme;
}

+ (CKConnectionRegistry *)sharedConnectionRegistry;

#pragma mark Connection class registration
- (Class <CKConnection>)connectionClassForURLScheme:(NSString *)URLScheme;
- (Class <CKConnection>)connectionClassForName:(NSString *)connectionName;

/*!
 @method registerClass:forURLScheme:
 @abstract Registers a connection class.
 @discussion The connection's name is automatically registered for you.
 @param connectionClass The class implementing the CKConnection protocol to register.
 @param URLScheme Optional. The URL scheme to register the connection for. Call this method agin if you need to register more than one URL scheme.
 */
- (void)registerClass:(Class <CKConnection>)connectionClass forName:(NSString *)name URLScheme:(NSString *)URLScheme;

- (CKConnectionRequest *)connectionRequestForName:(NSString *)name host:(NSString *)host port:(NSNumber *)port;

#pragma mark Creating a connection

/*!
 @method connectionWithRequest:delegate:
 @abstract Locates the connection class that corresponds with the URL and then creates one.
 @param request The request to create a connection for.
 @param delegate The initial delegate for the connection.
 @result An initialized connection, or nil if no suitable class could be found.
 */
- (id <CKConnection>)connectionWithRequest:(CKConnectionRequest *)request;

// These 2 methods are for compatibility with legacy code
- (id <CKConnection>)connectionWithName:(NSString *)name host:(NSString *)host port:(NSNumber *)port;
- (id <CKConnection>)connectionWithName:(NSString *)name host:(NSString *)host port:(NSNumber *)port user:(NSString *)username password:(NSString *)password error:(NSError **)error;

@end

//
//  CKConnectionRegistry.m
//  Connection
//
//  Created by Mike on 05/12/2008.
//  Copyright 2008 Karelia Software. All rights reserved.
//

#import "CKConnectionRegistry.h"

#import "CKAbstractConnection.h"

#import "NSURL+Connection.h"


@implementation CKConnectionRegistry

+ (CKConnectionRegistry *)sharedConnectionRegistry
{
    static CKConnectionRegistry *result;
    if (!result)
    {
        result = [[CKConnectionRegistry alloc] init];
    }
    
    return result;
}

- (id)init
{
    if (self = [super init])
    {
        _connectionClassesByProtocol = [[NSMutableDictionary alloc] init];
        _connectionClassesByURLScheme = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_connectionClassesByURLScheme release];
    [_connectionClassesByProtocol release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark Class Registration

- (void)registerClass:(Class <CKConnection>)connectionClass forProtocol:(CKProtocol)protocol URLScheme:(NSString *)URLScheme
{
    [_connectionClassesByProtocol setObject:connectionClass forKey:[NSNumber numberWithInt:protocol]];
    
    if (URLScheme)
        [_connectionClassesByURLScheme setObject:connectionClass forKey:URLScheme];
}

- (Class <CKConnection>)connectionClassForURLScheme:(NSString *)URLScheme
{
    return [_connectionClassesByURLScheme objectForKey:URLScheme];
}

- (Class <CKConnection>)connectionClassForProtocol:(CKProtocol)protocol
{
    return [_connectionClassesByProtocol objectForKey:[NSNumber numberWithInt:protocol]];
}

- (CKConnectionRequest *)connectionRequestForProtocol:(CKProtocol)protocol host:(NSString *)host port:(NSNumber *)port
{
    Class connectionClass = [self connectionClassForProtocol:protocol];
    
    NSURL *URL = [[NSURL alloc] initWithScheme:[[connectionClass URLSchemes] objectAtIndex:0]
                                          host:host
                                          port:port
                                          user:nil
                                      password:nil];
    
    CKConnectionRequest *result = [CKConnectionRequest requestWithURL:URL];
    [URL release];
    return result;
}

#pragma mark -
#pragma mark Connection Creation

- (id <CKConnection>)connectionWithRequest:(CKConnectionRequest *)request
{
    Class class = [self connectionClassForURLScheme:[[request URL] scheme]];
    
    id <CKConnection> result = nil;
    if (class)
    {
        result = [[[class alloc] initWithRequest:request] autorelease];
    }
    
    return result;
}

- (id <CKConnection>)connectionForProtocol:(CKProtocol)protocol host:(NSString *)host port:(NSNumber *)port
{
	return [self connectionForProtocol:protocol host:host port:port user:nil password:nil error:nil];
}

- (id <CKConnection>)connectionForProtocol:(CKProtocol)protocol
									  host:(NSString *)host
									  port:(NSNumber *)port
									  user:(NSString *)username
								  password:(NSString *)password
									 error:(NSError **)error
{
    Class class = [self connectionClassForProtocol:protocol];
    
    id <CKConnection> result = nil;
    if (class)
    {
        NSURL *URL = [[NSURL alloc] initWithScheme:[[class URLSchemes] objectAtIndex:0]
                                              host:host
                                              port:port
                                              user:username
                                          password:password];
        
        result = [[[class alloc] initWithRequest:[CKConnectionRequest requestWithURL:URL]] autorelease];
        [URL release];
    }
                      
    if (!result && error)
	{
		NSError *err = [NSError errorWithDomain:CKConnectionErrorDomain
										   code:CKConnectionNoConnectionsAvailable
									   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(
																																@"No connection available for requested connection type", @"failed to find a connection class"),
												 NSLocalizedDescriptionKey,
												 [(*error) localizedDescription],
												 NSLocalizedRecoverySuggestionErrorKey,	// some additional context
												 nil]];
		*error = err;
	}
	
    return result;
}

@end

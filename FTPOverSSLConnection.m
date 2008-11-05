//
//  FTPOverSSLConnection.m
//  FTPConnection
//
//  Created by Greg Hulands on 7/12/05.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "FTPOverSSLConnection.h"


@implementation FTPOverSSLConnection

+ (void)load	// registration of this class
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *port = [NSDictionary dictionaryWithObjectsAndKeys:@"990", ACTypeValueKey, ACPortTypeKey, ACTypeKey, nil];
	NSDictionary *url = [NSDictionary dictionaryWithObjectsAndKeys:@"ftps://", ACTypeValueKey, ACURLTypeKey, ACTypeKey, nil];
	[AbstractConnection registerConnectionClass:[FTPOverSSLConnection class] forTypes:[NSArray arrayWithObjects:port, url, nil]];
	[pool release];
}

+ (NSString *)name
{
	return @"FTP over SSL";
}

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
{
	FTPOverSSLConnection *c = [[FTPOverSSLConnection alloc] initWithHost:host
																	port:port
																username:username
																password:password];
	return [c autorelease];
}

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
{
	if (self = [super initWithHost:host port:port username:username password:password]) {
		_ssl = SSLVersionNegotiated;
	}
	return self;
}

- (void)dealloc
{
	
	[super dealloc];
}

#pragma mark -
#pragma mark SSL Specific

- (void)setSSLVersion:(SSLVersion)version
{
	_ssl = version;
}

- (SSLVersion)sslVersion
{
	return _ssl;
}

#pragma mark -
#pragma mark Connection Overrides

- (void)connect
{
	[self emptyCommandQueue];
	
	NSHost *host = [NSHost hostWithName:_connectionHost];
	if(!host){
		//if ([AbstractConnection debugEnabled])
			NSLog(@"Cannot find the host: %@", _connectionHost);
		
        if (_flags.error)
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"Host Unavailable", @"Host Unavailable"), NSLocalizedDescriptionKey,
									  _connectionHost, ConnectionHostKey, nil];
			NSError *error = [NSError errorWithDomain:ConnectionErrorDomain code:EHOSTUNREACH userInfo:userInfo];
			[_forwarder connection:self didReceiveError:error];
		}
		
		
		return;
	}
	/* If the host has multiple names it can screw up the order in the list of name */
	if ([[host names] count] > 1) {
#warning Applying KVC Hack
		[host setValue:[NSArray arrayWithObject:_connectionHost] forKey:@"names"];
	}
	
	int connectionPort = [_connectionPort intValue];
	if (0 == connectionPort)
	{
		connectionPort = 990;	// standard FTP over SSL control port
	}
	[self closeStreams];		// make sure streams are closed before opening/allocating new ones
	[NSStream getStreamsToHost:host
						  port:connectionPort
				   inputStream:&_receiveStream
				  outputStream:&_sendStream];
	[_receiveStream retain];	// the above objects are created autorelease; we have to retain them
	[_sendStream retain];
	
	//set the SSL Version
	switch (_ssl) {
		case SSLVersion2: 
			[_receiveStream setProperty:NSStreamSocketSecurityLevelSSLv2 forKey:NSStreamSocketSecurityLevelKey];
			[_sendStream setProperty:NSStreamSocketSecurityLevelSSLv2 forKey:NSStreamSocketSecurityLevelKey];
			break;
		case SSLVersion3:
			[_receiveStream setProperty:NSStreamSocketSecurityLevelSSLv3 forKey:NSStreamSocketSecurityLevelKey];
			[_sendStream setProperty:NSStreamSocketSecurityLevelSSLv3 forKey:NSStreamSocketSecurityLevelKey];
			break;
		case SSLVersionTLS:
			[_receiveStream setProperty:NSStreamSocketSecurityLevelTLSv1 forKey:NSStreamSocketSecurityLevelKey];
			[_sendStream setProperty:NSStreamSocketSecurityLevelTLSv1 forKey:NSStreamSocketSecurityLevelKey];
			break;
		case SSLVersionNegotiated:
			[_receiveStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
			[_sendStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
			break;
	}
	
	if(!_receiveStream && _sendStream){
		//if ([AbstractConnection debugEnabled])
			NSLog(@"Cannot create a stream for the host: %@", _connectionHost);
		
		if (_flags.error)
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  LocalizedStringInConnectionKitBundle(@"Stream Unavailable", @"Error creating stream"), NSLocalizedDescriptionKey,
									  _connectionHost, ConnectionHostKey, nil];
			NSError *error = [NSError errorWithDomain:ConnectionErrorDomain code:EHOSTUNREACH userInfo:userInfo];
			[_forwarder connection:self didReceiveError:error];
		}
		return;
	}
	[self sendPortMessage:CONNECT];	// finish the job -- scheduling in the runloop -- in the background thread
}

- (void)openDataStreamsToHost:(NSHost *)aHost port:(int)aPort
{
	[NSStream getStreamsToHost:aHost
						  port:aPort
				   inputStream:&_dataReceiveStream
				  outputStream:&_dataSendStream];
	[_dataReceiveStream retain];
	[_dataSendStream retain];
	
	//set the SSL Version
	switch (_ssl) {
		case SSLVersion2: 
			[_dataReceiveStream setProperty:NSStreamSocketSecurityLevelSSLv2 forKey:NSStreamSocketSecurityLevelKey];
			[_dataSendStream setProperty:NSStreamSocketSecurityLevelSSLv2 forKey:NSStreamSocketSecurityLevelKey];
			break;
		case SSLVersion3:
			[_dataReceiveStream setProperty:NSStreamSocketSecurityLevelSSLv3 forKey:NSStreamSocketSecurityLevelKey];
			[_dataSendStream setProperty:NSStreamSocketSecurityLevelSSLv3 forKey:NSStreamSocketSecurityLevelKey];
			break;
		case SSLVersionTLS:
			[_dataReceiveStream setProperty:NSStreamSocketSecurityLevelTLSv1 forKey:NSStreamSocketSecurityLevelKey];
			[_dataSendStream setProperty:NSStreamSocketSecurityLevelTLSv1 forKey:NSStreamSocketSecurityLevelKey];
			break;
		case SSLVersionNegotiated:
			[_dataReceiveStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
			[_dataSendStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
			break;
	}
	
	[_dataReceiveStream setDelegate:self];
	[_dataSendStream setDelegate:self];
	
	[_dataReceiveStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_dataSendStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	
	[_dataReceiveStream open];
	[_dataSendStream open];
}

@end

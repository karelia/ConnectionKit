/*
 Copyright (c) 2004-2006, Greg Hulands <ghulands@mac.com>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
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


#import "CKHTTPConnection.h"

#import "CKHTTPRequest.h"
#import "CKHTTPResponse.h"
#import "ConnectionThreadManager.h"
#import "DAVResponse.h"
#import "NSData+Connection.h"
#import "NSString+Connection.h"
#import "NSObject+Connection.h"
#import "RegexKitLite.h"

enum {
	HTTPSentGenericRequestState = 32012
};

NSString *CKHTTPConnectionErrorDomain = @"CKHTTPConnectionErrorDomain";

@implementation CKHTTPConnection

+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password
				 error:(NSError **)error
{
	CKHTTPConnection *c = [[self alloc] initWithHost:host
                                                port:port
                                            username:username
                                            password:password
											   error:error];
	return [c autorelease];
}

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password
			 error:(NSError **)error
{
	if (!port || [port isEqualToString:@""])
	{
		port = @"80";
	}
	
	if ((self = [super initWithHost:host port:port username:username password:password error:error]))
	{
		myResponseBuffer = [[NSMutableData data] retain];
		if (username && password)
		{
			myDigestNonceCount = 0;
			NSData *authData = [[NSString stringWithFormat:@"%@:%@", username, password] dataUsingEncoding:NSUTF8StringEncoding];
			//We use Basic by default
			myBasicAuthorization = [[NSString stringWithFormat:@"Basic %@", [authData base64Encoding]] retain];
		}
	}
	return self;
}

- (void)dealloc
{
	[myCurrentRequest release];
	[myResponseBuffer release];
	[myBasicAuthorization release];
	
	[myDigestNonce release];
	[myDigestOpaque release];
	[myDigestRealm release];
	
	[super dealloc];
}

+ (NSString *)urlScheme
{
	return @"http";
}

- (void)sendError:(NSString *)error code:(int)code
{
	NSError *err = [NSError errorWithDomain:CKHTTPConnectionErrorDomain 
									   code:code 
								   userInfo:[NSDictionary dictionaryWithObject:error forKey:NSLocalizedDescriptionKey]];
	if (_flags.error)
	{
		[_forwarder connection:self didReceiveError:err];
	}
}

- (void)sendRequest:(CKHTTPRequest *)request
{
	ConnectionCommand *cmd = [ConnectionCommand command:request 
											 awaitState:ConnectionIdleState 
											  sentState:HTTPSentGenericRequestState 
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
}

#pragma mark -
#pragma mark Stream Overrides

- (void)setDelegate:(id)delegate
{
	myHTTPFlags.didReceiveData = [delegate respondsToSelector:@selector(connection:didReceiveDataOfLength:)];
	myHTTPFlags.didReceiveResponse = [delegate respondsToSelector:@selector(connection:didReceiveResponse:)];
	myHTTPFlags.didSendDataOfLength = [delegate respondsToSelector:@selector(connection:didSendDataOfLength:)];
	
	[super setDelegate:delegate];
}

- (void)threadedConnect
{
	//Reset Digest Authentication
	myDigestNonceCount = 0;
	[myDigestNonce release];
	[myDigestOpaque release];
	[myDigestRealm release];
	myHTTPFlags.didFailAttemptedDigestAuthentication = NO;
	
	[super threadedConnect];
	[self setState:ConnectionIdleState];
}

- (void)processReceivedData:(NSData *)data
{
	[myResponseBuffer appendData:data];
	
	if (![self processBufferWithNewData:data])
	{
		return;
	}
	NSRange responseRange;
	if ([data length] > 0)
	{
		responseRange = [CKHTTPResponse canConstructResponseWithData:myResponseBuffer];
		if (responseRange.location == NSNotFound)
		{
			return;
		}
	}
	else
	{
		responseRange = NSMakeRange(0, [myResponseBuffer length]);
	}
	NSData *packetData = [myResponseBuffer subdataWithRange:responseRange];
	CKHTTPResponse *response = [CKHTTPResponse responseWithRequest:myCurrentRequest data:packetData];
	[myResponseBuffer setLength:0];
	[self closeStreams];
		
	KTLog(ProtocolDomain, KTLogDebug, @"HTTP Received: %@", [response shortDescription]);
	
	if ([self transcript])
	{
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", [response description]] 
																  attributes:[AbstractConnection receivedAttributes]] autorelease]];
		[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", [response formattedResponse]] 
																  attributes:[AbstractConnection dataAttributes]] autorelease]];
	}
	
	if ([response code] == 401)
	{
		BOOL prefersDigest = ([[self propertyForKey:@"CKPrefersHTTPDigestAuthorization"] boolValue]);
		//Send bad password if we don't prefer digest, or if we do and we failed at it.
		if (myBasicAuthorization != nil && (!prefersDigest || (prefersDigest && myHTTPFlags.didFailAttemptedDigestAuthentication)))
		{
			// the user or password supplied is bad
			if (_flags.badPassword)
			{
				[_forwarder connectionDidSendBadPassword:self];
				if (_flags.didDisconnect)
					[_forwarder connection:self didDisconnectFromHost:[self host]];
			}
		}
		else
		{			
			if ([self transcript])
			{
				[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"Connection needs Authorization\n"] 
																		  attributes:[AbstractConnection sentAttributes]] autorelease]];
			}
			// need to append authorization
			NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
			NSString *auth = [[response headerForKey:@"WWW-Authenticate"] stringByTrimmingCharactersInSet:ws];
			
			//Auth Method
			NSRange rangeOfFirstWhitespace = [auth rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
			NSString *authMethod = (rangeOfFirstWhitespace.location != NSNotFound) ? [auth substringToIndex:rangeOfFirstWhitespace.location] : nil;
			
			//If we already tried, mark it.
			myHTTPFlags.didFailAttemptedDigestAuthentication = (prefersDigest && myDigestNonce && myDigestRealm && myDigestOpaque);
			
			if ([authMethod isEqualToString:@"Basic"] || myHTTPFlags.didFailAttemptedDigestAuthentication)
			{
				NSData *authData = [[NSString stringWithFormat:@"%@:%@", [self username], [self password]] dataUsingEncoding:NSUTF8StringEncoding];
				[myBasicAuthorization autorelease];
				myBasicAuthorization = [[NSString stringWithFormat:@"Basic %@", [authData base64Encoding]] retain];

				//resend the request with auth
				[self sendCommand:myCurrentRequest];
				return;
			}
			else if ([authMethod isEqualToString:@"Digest"] && prefersDigest)
			{
				//Realm
				NSString *realmMatchingString = [auth stringByMatching:@"realm=\"[^\"]+\""]; //This is	realm="blahblahblah"
				[myDigestRealm autorelease];
				myDigestRealm = [[[realmMatchingString stringByMatching:@"\"[^\"]+"] substringFromIndex:1] retain];
				
				//Nonce
				NSString *nonceMatchingString = [auth stringByMatching:@"nonce=\"[^\"]+\""]; //This is	nonce="blahblahblah"
				[myDigestNonce autorelease];
				myDigestNonce = [[[nonceMatchingString stringByMatching:@"\"[^\"]+"] substringFromIndex:1] retain];
				
				//Opaque
				NSString *opaqueMatchingString = [auth stringByMatching:@"opaque=\"[^\"]+\""]; //This is	opaque="blahblahblah"
				[myDigestOpaque autorelease];
				myDigestOpaque = [[[opaqueMatchingString stringByMatching:@"\"[^\"]+"] substringFromIndex:1] retain];				
				
				//resend the request with auth
				[self sendCommand:myCurrentRequest];
				return;				
			}
			else
			{
				if ([self transcript])
				{
					[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"CKHTTPConnection could not authenticate!\n"] 
																			  attributes:[AbstractConnection sentAttributes]] autorelease]];
				}
				@throw [NSException exceptionWithName:NSInternalInconsistencyException
											   reason:@"Failed at Basic and Digest Authentication"
											 userInfo:nil];
			}
		}
	}
	
	[myCurrentRequest release];
	myCurrentRequest = nil;
	
	[self processResponse:response];
	if ([response code] == 401)
		[self setState:ConnectionNotConnectedState];
}

- (BOOL)processBufferWithNewData:(NSData *)data
{
	return YES;
}

- (void)processResponse:(CKHTTPResponse *)response
{
	[myCurrentRequest autorelease];
	myCurrentRequest = nil;
	
	if (myHTTPFlags.didReceiveResponse)
	{
		[(NSObject *)_forwarder connection:self didReceiveResponse:response];
	}
	[self setState:ConnectionIdleState];
}

- (void)sendCommand:(id)command
{
	if ([command isKindOfClass:[CKHTTPRequest class]])
	{
		CKHTTPRequest *req = [(CKHTTPRequest *)command retain];
		[myCurrentRequest release];
		myCurrentRequest = req;
				
		if (myHTTPFlags.isInReconnection)
		{
			[self performSelector:@selector(sendCommand:) withObject:command afterDelay:0.2];
			return;
		}
		if (myHTTPFlags.needsReconnection || _sendStream == nil || _receiveStream == nil)
		{
			myHTTPFlags.needsReconnection = NO;
			myHTTPFlags.isInReconnection = YES;
			[self openStreamsToPort:[[self port] intValue]];
			[self scheduleStreamsOnRunLoop];
			
			[self performSelector:@selector(sendCommand:) withObject:command afterDelay:0.2];
			return;
		}
		
		//make sure we set the host name and set anything else which is needed
		[req setHeader:[self host] forKey:@"Host"];
		[req setHeader:@"close" forKey:@"Connection"]; // was Keep-Alive
		[req setHeader:@"trailers" forKey:@"TE"];
		
		[self setAuthenticationWithRequest:req];
		
		NSData *packet = [req serialized];
		
		if ([self transcript])
		{
			[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", [req description]] 
																	  attributes:[AbstractConnection sentAttributes]] autorelease]];
		}
		
		[self initiatingNewRequest:req withPacket:packet];
		
		KTLog(ProtocolDomain, KTLogDebug, @"HTTP Sending: %@", [[packet subdataWithRange:NSMakeRange(0,[req headerLength])] descriptionAsUTF8String]);
		[self sendData:packet];
	}
	else 
	{
		//we are an invocation
		NSInvocation *inv = (NSInvocation *)command;
		[inv invoke];
	}
}

- (void)initiatingNewRequest:(CKHTTPRequest *)request withPacket:(NSData *)packet
{
	
}

- (void)setAuthenticationWithRequest:(CKHTTPRequest *)request
{
	NSString *authorization = nil;
	BOOL prefersDigest = ([[self propertyForKey:@"CKPrefersHTTPDigestAuthorization"] boolValue]);
	
	if (myBasicAuthorization && (!prefersDigest || (prefersDigest && myHTTPFlags.didFailAttemptedDigestAuthentication)))
		authorization = myBasicAuthorization;
	else if ((myDigestRealm || myDigestOpaque || myDigestNonce) && prefersDigest)
	{
		if (!myDigestNonce)
			myDigestNonce = @"";
		if (!myDigestOpaque)
			myDigestOpaque = @"";
		if (!myDigestRealm)
			myDigestRealm = @"";
		
		//See http://en.wikipedia.org/wiki/Digest_access_authentication for the naming conventions used here.
		NSString *HA1 = [[NSString stringWithFormat:@"%@:%@:%@", [self username], myDigestRealm, [self password]] md5Hash];
		NSString *HA2 = [[NSString stringWithFormat:@"%@:%@", [request method], [request uri]] md5Hash];
		
		myDigestNonceCount++;
		NSString *nonceCounterString = [NSString stringWithFormat:@"%08x", myDigestNonceCount];
		//As far as I understand, the cnonce is a client-specified value. See http://greenbytes.de/tech/webdav/rfc2617.html#rfc.iref.c.7
		NSString *cnonceString = @"0a4f113b";
		NSString *qopString = @"auth";		
		//HA1:nonce:nc:cnonce:qop:HA2
		NSString *response = [[NSString stringWithFormat:@"%@:%@:%@:%@:%@:%@", HA1, myDigestNonce, nonceCounterString, cnonceString, qopString, HA2] md5Hash];
		
		NSMutableString *tempAuth = [NSMutableString string];
		[tempAuth appendFormat:@"Digest username=\"%@\"", [self username]];
		[tempAuth appendFormat:@", realm=\"%@\"", myDigestRealm];
		[tempAuth appendFormat:@", nonce=\"%@\"", myDigestNonce];
		[tempAuth appendFormat:@", uri=\"%@\"", [request uri]];
		[tempAuth appendFormat:@", qop=\"%@\"", qopString];
		[tempAuth appendFormat:@", nc=\"%@\"", nonceCounterString];
		[tempAuth appendFormat:@", cnonce=\"%@\"", cnonceString];
		[tempAuth appendFormat:@", response=\"%@\"", response];
		[tempAuth appendFormat:@", opaque=\"%@\"", myDigestOpaque];
		authorization = [NSString stringWithString:tempAuth];
	}
	if (authorization)
		[request setHeader:authorization forKey:@"Authorization"];
}

#pragma mark -
#pragma mark Stream Overrides

- (void)handleReceiveStreamEvent:(NSStreamEvent)theEvent
{
	switch (theEvent) 
	{
		case NSStreamEventEndEncountered: 
		{
			KTLog(InputStreamDomain, KTLogDebug, @"Stream Closed");
			// we don't want to notify the delegate we were disconnected as we want to appear to be a persistent connection
			[self closeStreams];
			myHTTPFlags.needsReconnection = YES;
			if (myCurrentRequest && [_sendBuffer length] > 0)
			{
				[self sendCommand:myCurrentRequest];
			}
			
			break;
		}
		case NSStreamEventOpenCompleted:
		{
			if (!_flags.isConnected)
			{
				myHTTPFlags.isInReconnection = NO;
				myHTTPFlags.finishedReconnection = YES;
			}
			[super handleReceiveStreamEvent:theEvent];
			break;
		}
		default:
			[super handleReceiveStreamEvent:theEvent];
	}
}

- (void)handleSendStreamEvent:(NSStreamEvent)theEvent
{
	switch (theEvent) 
	{
		case NSStreamEventEndEncountered: 
		{
			KTLog(OutputStreamDomain, KTLogDebug, @"Stream Closed");
			// we don't want to notify the delegate we were disconnected as we want to appear to be a persistent connection
			[self closeStreams];
			myHTTPFlags.needsReconnection = YES;
			if (myCurrentRequest && [_sendBuffer length] > 0)
			{
				[self sendCommand:myCurrentRequest];
			}
			break;
		}
		case NSStreamEventOpenCompleted:
		{
			if (_flags.isConnected)
			{
				myHTTPFlags.isInReconnection = NO;
				myHTTPFlags.finishedReconnection = YES;
			}
			[super handleSendStreamEvent:theEvent];
			break;
		}
		default:
			[super handleSendStreamEvent:theEvent];
	}
}

- (void)stream:(id<OutputStream>)stream sentBytesOfLength:(unsigned)length
{
	if (myHTTPFlags.didSendDataOfLength)
	{
		[_forwarder connection:self didSendDataOfLength:length];
	}
}

- (void)stream:(id<InputStream>)stream readBytesOfLength:(unsigned)length
{
	if (myHTTPFlags.didReceiveData)
	{
		[_forwarder connection:self didReceiveDataOfLength:length];
	}
}

@end
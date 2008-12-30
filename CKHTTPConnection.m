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
#import "CKConnectionThreadManager.h"
#import "CKDAVResponse.h"
#import "NSData+Connection.h"
#import "NSString+Connection.h"
#import "NSObject+Connection.h"
#import "RegexKitLite.h"

enum {
	HTTPSentGenericRequestState = 32012
};

NSString *CKHTTPConnectionErrorDomain = @"CKHTTPConnectionErrorDomain";


@interface CKHTTPConnection (Authentication) 
@end


#pragma mark -


@implementation CKHTTPConnection

#pragma mark -

+ (NSArray *)URLSchemes { return [NSArray arrayWithObject:@"http"]; }

+ (NSInteger)defaultPort { return 80; }

- (id)initWithURL:(NSURL *)URL
{
	if ((self = [super initWithURL:URL]))
	{
		myResponseBuffer = [[NSMutableData data] retain];
	}
	
	return self;
}

- (void)dealloc
{
	[myCurrentRequest release];
	[myResponseBuffer release];
	[_basicAccessAuthorizationHeader release];
	[_currentAuthenticationChallenge release];
	
	[_currentDigestNonce release];
	[_currentDigestOpaque release];
	[_currentDigestRealm release];
	
	[super dealloc];
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
	CKConnectionCommand *cmd = [CKConnectionCommand command:request 
											 awaitState:CKConnectionIdleState 
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
	_digestNonceCount = 0;
	[_currentDigestNonce release];  _currentDigestNonce = nil;
	[_currentDigestOpaque release]; _currentDigestOpaque = nil;
	[_currentDigestRealm release];  _currentDigestRealm = nil;
	
	[super threadedConnect];
	[self setState:CKConnectionIdleState];
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
		
	KTLog(CKProtocolDomain, KTLogDebug, @"HTTP Received: %@", [response shortDescription]);
	
	if (_flags.transcript)
	{
		[self appendString:[NSString stringWithFormat:@"%@\n", [response description]] toTranscript:CKTranscriptReceived];
		[self appendString:[NSString stringWithFormat:@"%@\n", [response formattedResponse]] toTranscript:CKTranscriptData];
	}
	
	if ([response code] == 401)
	{		
		if (_flags.transcript)
		{
			[self appendString:[NSString stringWithFormat:@"Connection needs Authorization\n"] toTranscript:CKTranscriptSent];
		}
		// need to append authorization
		NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
		NSString *auth = [[response headerForKey:@"WWW-Authenticate"] stringByTrimmingCharactersInSet:ws];
		
		//Auth Method
		NSRange rangeOfFirstWhitespace = [auth rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString *authMethod = (rangeOfFirstWhitespace.location != NSNotFound) ? [auth substringToIndex:rangeOfFirstWhitespace.location] : nil;
		
		
		// Throw away any old authentication info
		[_basicAccessAuthorizationHeader release];
		_basicAccessAuthorizationHeader = nil;
			
		
		// Store info needed for digest-based authentication if it's available
		if ([authMethod isEqualToString:@"Digest"])
		{
			//Realm
			NSString *realmMatchingString = [auth stringByMatching:@"realm=\"[^\"]+\""]; //This is	realm="blahblahblah"
			[_currentDigestRealm autorelease];
			_currentDigestRealm = [[[realmMatchingString stringByMatching:@"\"[^\"]+"] substringFromIndex:1] retain];
			
			//Nonce
			NSString *nonceMatchingString = [auth stringByMatching:@"nonce=\"[^\"]+\""]; //This is	nonce="blahblahblah"
			[_currentDigestNonce autorelease];
			_currentDigestNonce = [[[nonceMatchingString stringByMatching:@"\"[^\"]+"] substringFromIndex:1] retain];
			
			//Opaque
			NSString *opaqueMatchingString = [auth stringByMatching:@"opaque=\"[^\"]+\""]; //This is	opaque="blahblahblah"
			[_currentDigestOpaque autorelease];
			_currentDigestOpaque = [[[opaqueMatchingString stringByMatching:@"\"[^\"]+"] substringFromIndex:1] retain];				
		}
		
		
		// Ask the delegate to authenticate
		if ([authMethod isEqualToString:@"Basic"])
		{
			[self authenticateConnectionWithMethod:NSURLAuthenticationMethodHTTPBasic];
			return;
		}
		else if ([authMethod isEqualToString:@"Digest"])
		{
			[self authenticateConnectionWithMethod:NSURLAuthenticationMethodHTTPDigest];
			return;
		}
		else
		{
			if (_flags.transcript)
			{
				[self appendString:[NSString stringWithFormat:@"CKHTTPConnection could not authenticate!\n"] toTranscript:CKTranscriptSent];
			}
			@throw [NSException exceptionWithName:NSInternalInconsistencyException
										   reason:@"Failed at Basic and Digest Authentication"
										 userInfo:nil];
		}
	}
    else
    {
        // We're currently authenticated, so reset the failure counter
        _authenticationFailureCount = 0;
    }
	
	[myCurrentRequest release];
	myCurrentRequest = nil;
	
	[self processResponse:response];
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
	[self setState:CKConnectionIdleState];
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
			[self openStreamsToPort:[self port]];
			[self scheduleStreamsOnRunLoop];
			
			[self performSelector:@selector(sendCommand:) withObject:command afterDelay:0.2];
			return;
		}
		
		//make sure we set the host name and set anything else which is needed
		[req setHeader:[[self URL] host] forKey:@"Host"];
		[req setHeader:@"close" forKey:@"Connection"]; // was Keep-Alive
		[req setHeader:@"trailers" forKey:@"TE"];
		
		[self setAuthenticationWithRequest:req];
		
		NSData *packet = [req serialized];
		
		if (_flags.transcript)
		{
			[self appendString:[NSString stringWithFormat:@"%@\n", [req description]] toTranscript:CKTranscriptSent];
		}
		
		[self initiatingNewRequest:req withPacket:packet];
		
		KTLog(CKProtocolDomain, KTLogDebug, @"HTTP Sending: %@", [[packet subdataWithRange:NSMakeRange(0,[req headerLength])] descriptionAsUTF8String]);
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
	if (_basicAccessAuthorizationHeader)
	{
		[request setHeader:_basicAccessAuthorizationHeader forKey:@"Authorization"];
	}
}

#pragma mark -
#pragma mark Stream Overrides

- (void)handleReceiveStreamEvent:(NSStreamEvent)theEvent
{
	switch (theEvent) 
	{
		case NSStreamEventEndEncountered: 
		{
			KTLog(CKInputStreamDomain, KTLogDebug, @"Stream Closed");
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
			KTLog(CKOutputStreamDomain, KTLogDebug, @"Stream Closed");
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

#pragma mark -
#pragma mark Authentication

- (void)authenticateConnectionWithMethod:(NSString *)authenticationMethod
{
	// Create authentication challenge object
	NSURLProtectionSpace *protectionSpace = [[NSURLProtectionSpace alloc] initWithHost:[[self URL] host]
																				  port:[self port]
																			  protocol:[[self URL] scheme]
																				 realm:nil
																  authenticationMethod:authenticationMethod];
	
	[_currentAuthenticationChallenge release];
	_currentAuthenticationChallenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:protectionSpace
																				 proposedCredential:[self proposedCredentialForProtectionSpace:protectionSpace]
																			   previousFailureCount:_authenticationFailureCount
																					failureResponse:nil
																							  error:nil
																							 sender:self];
	
	[protectionSpace release];
	
	[self didReceiveAuthenticationChallenge:_currentAuthenticationChallenge];
	
	// Prepare for another failure
	_authenticationFailureCount++;
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge == _currentAuthenticationChallenge)
    {
        [_currentAuthenticationChallenge release];  _currentAuthenticationChallenge = nil;
        [self disconnect];
    }
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	if (challenge == _currentAuthenticationChallenge)
    {
		[_currentAuthenticationChallenge release];  _currentAuthenticationChallenge = nil;
        
        if (_flags.error)
        {
            [self sendError:@"" code:401];  // TODO: The error should include the response string from the server
        }
        
        // Move onto the next command
        [self setState:CKConnectionIdleState];
	}
}

/*  Retry the request, this time with authentication information.
 */
- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge != _currentAuthenticationChallenge)	return;
	[_currentAuthenticationChallenge release];  _currentAuthenticationChallenge = nil;
    
	
	
	// Use digest-based authentication if supported
	if (_currentDigestRealm || _currentDigestOpaque || _currentDigestNonce)
	{
		NSString *digestNonce = (_currentDigestNonce) ? _currentDigestNonce : @"";
        NSString *digestOpaque = (_currentDigestOpaque) ? _currentDigestOpaque : @"";
        NSString *digestRealm = (_currentDigestRealm) ? _currentDigestRealm : @"";
		
		//See http://en.wikipedia.org/wiki/Digest_access_authentication for the naming conventions used here.
		NSString *HA1 = [[NSString stringWithFormat:@"%@:%@:%@", [credential user], digestRealm, [credential password]] md5Hash];
		NSString *HA2 = [[NSString stringWithFormat:@"%@:%@", [myCurrentRequest method], [myCurrentRequest uri]] md5Hash];
		
		_digestNonceCount++;
		NSString *nonceCounterString = [NSString stringWithFormat:@"%08x", _digestNonceCount];
		//As far as I understand, the cnonce is a client-specified value. See http://greenbytes.de/tech/webdav/rfc2617.html#rfc.iref.c.7
		NSString *cnonceString = @"0a4f113b";
		NSString *qopString = @"auth";		
		//HA1:nonce:nc:cnonce:qop:HA2
		NSString *response = [[NSString stringWithFormat:@"%@:%@:%@:%@:%@:%@", HA1, digestNonce, nonceCounterString, cnonceString, qopString, HA2] md5Hash];
		
		NSMutableString *tempAuth = [[NSMutableString alloc] init];
		[tempAuth appendFormat:@"Digest username=\"%@\"", [credential user]];
		[tempAuth appendFormat:@", realm=\"%@\"", digestRealm];
		[tempAuth appendFormat:@", nonce=\"%@\"", digestNonce];
		[tempAuth appendFormat:@", uri=\"%@\"", [myCurrentRequest uri]];
		[tempAuth appendFormat:@", qop=\"%@\"", qopString];
		[tempAuth appendFormat:@", nc=\"%@\"", nonceCounterString];
		[tempAuth appendFormat:@", cnonce=\"%@\"", cnonceString];
		[tempAuth appendFormat:@", response=\"%@\"", response];
		[tempAuth appendFormat:@", opaque=\"%@\"", digestOpaque];
		
		NSString *authorization = [tempAuth copy];
		[tempAuth release];
		
		[myCurrentRequest setHeader:authorization forKey:@"Authorization"];
		[authorization release];
	}
	
	// Basic HTTP authentication
	else
    {
        // Store the new credential
		NSString *authString = [[NSString alloc] initWithFormat:@"%@:%@", [credential user], [credential password]];
		NSData *authData = [authString dataUsingEncoding:NSUTF8StringEncoding];
		[authString release];
		
		NSAssert(!_basicAccessAuthorizationHeader, @"_basicAccessAuthorizationHeader is not nil. It should be reset to nil straight after failing authentication");
		_basicAccessAuthorizationHeader = [[NSString alloc] initWithFormat:@"Basic %@", [authData base64Encoding]];
    }
	
	
	// Resend the request with authentication.
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] sendCommand:myCurrentRequest];
}


@end


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
#import "CKHTTPResponse.h"
#import "CKHTTPRequest.h"
#import "ConnectionThreadManager.h"
#import "DAVResponse.h"
#import "NSData+Connection.h"

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
	if ((self = [super initWithHost:host port:port username:username password:password error:error]))
	{
		myResponseBuffer = [[NSMutableData data] retain];
		if (username && password)
		{
			NSData *authData = [[NSString stringWithFormat:@"%@:%@", username, password] dataUsingEncoding:NSUTF8StringEncoding];
			myAuthorization = [[NSString stringWithFormat:@"Basic %@", [authData base64Encoding]] retain];
		}
	}
	return self;
}

- (void)dealloc
{
	[myCurrentRequest release];
	[myResponseBuffer release];
	[myAuthorization release];
	
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
	myHTTPFlags.didReceiveData = [delegate respondsToSelector:@selector(connection:didReceiveData:)];
	myHTTPFlags.didReceiveResponse = [delegate respondsToSelector:@selector(connection:didReceiveResponse:)];
	myHTTPFlags.didSendDataOfLength = [delegate respondsToSelector:@selector(connection:didSendDataOfLength:)];
	
	[super setDelegate:delegate];
}

- (void)threadedConnect
{
	[super threadedConnect];
	_flags.isConnected = YES;
	[self setState:ConnectionIdleState];
	if (_flags.didConnect)
	{
		[_forwarder connection:self didConnectToHost:[self host]];
	}
}

- (void)processReceivedData:(NSData *)data
{	
	[myResponseBuffer appendData:data];
	if ([self processBufferWithNewData:data])
	{
		NSRange responseRange = [CKHTTPResponse canConstructResponseWithData:myResponseBuffer];
		if (responseRange.location != NSNotFound)
		{
			NSData *packetData = [myResponseBuffer subdataWithRange:responseRange];
			CKHTTPResponse *response = [CKHTTPResponse responseWithRequest:myCurrentRequest data:packetData];
			[myResponseBuffer setLength:0];
			[self closeStreams];
			
			[myCurrentRequest release];
			myCurrentRequest = nil;
			
			KTLog(ProtocolDomain, KTLogDebug, @"HTTP Received: %@", response);
			
			if ([self transcript])
			{
				[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", [response description]] 
																		  attributes:[AbstractConnection receivedAttributes]] autorelease]];
				[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", [response formattedResponse]] 
																		  attributes:[AbstractConnection dataAttributes]] autorelease]];
			}
			
			if ([response code] == 401)
			{
				if (myAuthorization != nil)
				{
					// the user or password supplied is bad
					if (_flags.badPassword)
					{
						[_forwarder connectionDidSendBadPassword:self];
						[self setState:ConnectionNotConnectedState];
						if (_flags.didDisconnect)
						{
							[_forwarder connection:self didDisconnectFromHost:[self host]];
						}
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
					NSCharacterSet *quote = [NSCharacterSet characterSetWithCharactersInString:@"\""];
					NSString *auth = [[response headerForKey:@"WWW-Authenticate"] stringByTrimmingCharactersInSet:ws];
					NSScanner *scanner = [NSScanner scannerWithString:auth];
					NSString *authMethod = nil;
					NSString *realm = nil;
					[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&authMethod];
					[scanner scanUpToString:@"Realm\"" intoString:nil];
					[scanner scanUpToCharactersFromSet:quote intoString:&realm];
					
					if ([authMethod isEqualToString:@"Basic"])
					{
						NSString *authString = [NSString stringWithFormat:@"%@:%@", [self username], [self password]];
						NSData *authData = [authString dataUsingEncoding:NSUTF8StringEncoding];
						[myAuthorization autorelease];
						myAuthorization = [[authData base64Encoding] retain];
						//resend the request with auth
						[self sendCommand:myCurrentRequest];
						return;
					}
					else
					{
						if ([self transcript])
						{
							[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"CKHTTPConnection only supports Basic Authentication!\n"] 
																					  attributes:[AbstractConnection sentAttributes]] autorelease]];
						}
						@throw [NSException exceptionWithName:NSInternalInconsistencyException
													   reason:@"Only Basic Authentication is supported at the moment"
													 userInfo:nil];
					}
				}
			}
			[self processResponse:response];
		}
	}
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
		[_forwarder connection:self didReceiveResponse:response];
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
		[req setHeader:@"Keep-Alive" forKey:@"Connection"];
		
		[self setAuthenticationWithRequest:req];
		
		NSData *packet = [req serialized];
		
		if ([self transcript])
		{
			[self appendToTranscript:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", [req description]] 
																	  attributes:[AbstractConnection sentAttributes]] autorelease]];
		}
		
		[self initiatingNewRequest:req withPacket:packet];
		
		KTLog(ProtocolDomain, KTLogDebug, @"HTTP Sending: %@", [[packet subdataWithRange:NSMakeRange(0,[req headerLength])] descriptionAsString]);
		
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
	if (myAuthorization)
	{
		[request setHeader:myAuthorization forKey:@"Authorization"];
	}
}

#pragma mark -
#pragma mark Abstract Connection Protocol

- (void)httpDisconnect
{
	[self closeStreams];
	if (_flags.didDisconnect)
	{
		[_forwarder connection:self didDisconnectFromHost:[self host]];
	}
	[self setState:ConnectionNotConnectedState];
}

- (void)disconnect
{
	NSInvocation *inv = [NSInvocation invocationWithSelector:@selector(httpDisconnect)
													  target:self
												   arguments:[NSArray array]];
	ConnectionCommand *cmd = [ConnectionCommand command:inv
											 awaitState:ConnectionIdleState
											  sentState:ConnectionSentQuitState
											  dependant:nil
											   userInfo:nil];
	[self queueCommand:cmd];
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




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

- (id)initWithRequest:(CKConnectionRequest *)request
{
	if ((self = [super initWithRequest:request]))
	{
		myResponseBuffer = [[NSMutableData data] retain];
	}
	
	return self;
}

- (void)dealloc
{
	[myCurrentRequest release];
	[myResponseBuffer release];
	[_currentAuthenticationChallenge release];
	if (_currentAuth) CFRelease(_currentAuth);
	[_basicAccessAuthorizationHeader release];
    
	[super dealloc];
}

- (void)sendError:(NSString *)error code:(int)code
{
	NSError *err = [NSError errorWithDomain:CKHTTPConnectionErrorDomain 
									   code:code 
								   userInfo:[NSDictionary dictionaryWithObject:error forKey:NSLocalizedDescriptionKey]];
	[[self client] connectionDidReceiveError:err];
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
	
	[[self client] appendString:[response description] toTranscript:CKTranscriptReceived];
	[[self client] appendString:[response formattedResponse] toTranscript:CKTranscriptData];
	
	
	if ([response code] == 401)
	{		
		[[self client] appendString:@"Connection needs Authorization" toTranscript:CKTranscriptSent];
		
		
        CFHTTPMessageRef saneResponse = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, FALSE);
        
        BOOL validData = CFHTTPMessageAppendBytes(saneResponse, [packetData bytes], [packetData length]);
        NSAssert(validData, @"Authorization request that CKResponse could handle, but CFHTTPMessage could not");
        
        NSURL *baseURL = [[self request] URL];
        NSURL *URL = [NSURL URLWithString:[[myCurrentRequest uri] encodeLegally] relativeToURL:baseURL];
        CFURLRef absoluteURL = (CFURLRef)[URL absoluteURL];  
        _CFHTTPMessageSetResponseURL(saneResponse, absoluteURL);    // bug in CFHTTPMessage requires this to be used when working with CFHTTPMessageCreateEmpty
        
        
        _currentAuth = CFHTTPAuthenticationCreateFromResponse(kCFAllocatorDefault, saneResponse);
        CFStreamError error;
        NSAssert(CFHTTPAuthenticationIsValid(_currentAuth, &error), @"Response does not contain valid authentication info");
        
        CFRelease(saneResponse);
        
        
        
        // Ask the delegate to authenticate. Unfortunately, we have no means for coping with something like NTLM authentication, which CFHTTP prefers. The only solution right now is to fallback onto private API that forces Digest or Basic auth.
        if (_CFHTTPAuthenticationSetPreferredScheme(_currentAuth, kCFHTTPAuthenticationSchemeDigest))
		{
			[self authenticateConnectionWithMethod:NSURLAuthenticationMethodHTTPDigest];
			return;
		}
		else if (_CFHTTPAuthenticationSetPreferredScheme(_currentAuth, kCFHTTPAuthenticationSchemeBasic))
		{
			[self authenticateConnectionWithMethod:NSURLAuthenticationMethodHTTPBasic];
			return;
		}
		else
		{
			[[self client] appendString:@"CKHTTPConnection could not authenticate!" toTranscript:CKTranscriptSent];
			
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
		[req setHeader:[[[self request] URL] host] forKey:@"Host"];
		[req setHeader:@"close" forKey:@"Connection"]; // was Keep-Alive
		[req setHeader:@"trailers" forKey:@"TE"];
		
		[self setAuthenticationWithRequest:req];
		
		NSData *packet = [req serialized];
		
		[[self client] appendString:[req description] toTranscript:CKTranscriptSent];
		
		
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
			if (!_isConnected)
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
			if (_isConnected)
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
}

- (void)stream:(id<InputStream>)stream readBytesOfLength:(unsigned)length
{
}

#pragma mark -
#pragma mark Authentication

- (void)authenticateConnectionWithMethod:(NSString *)authenticationMethod
{
	// Create authentication challenge object
	NSURLProtectionSpace *protectionSpace = [[NSURLProtectionSpace alloc] initWithHost:[[[self request] URL] host]
																				  port:[self port]
																			  protocol:[[[self request] URL] scheme]
																				 realm:nil
																  authenticationMethod:authenticationMethod];
	
	[_currentAuthenticationChallenge release];
	_currentAuthenticationChallenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:protectionSpace
																				 proposedCredential:[self proposedCredential]
																			   previousFailureCount:_authenticationFailureCount
																					failureResponse:nil
																							  error:nil
																							 sender:self];
	
	[protectionSpace release];
	
	[[self client] connectionDidReceiveAuthenticationChallenge:_currentAuthenticationChallenge];
	
	// Prepare for another failure
	_authenticationFailureCount++;
}

/*  MobileMe overrides this to fetch the user's account
 */
- (NSURLCredential *)proposedCredential
{
    return nil;
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge == _currentAuthenticationChallenge)
    {
        [_currentAuthenticationChallenge release];  _currentAuthenticationChallenge = nil;
    }
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	if (challenge == _currentAuthenticationChallenge)
    {
		[_currentAuthenticationChallenge release];  _currentAuthenticationChallenge = nil;
        
        [self sendError:@"" code:401];  // TODO: The error should include the response string from the server
        
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
    if ([[[challenge protectionSpace] authenticationMethod] isEqualToString:NSURLAuthenticationMethodHTTPDigest])
	{
		NSData *serializedRequest = [myCurrentRequest serialized];
        
        CFHTTPMessageRef saneRequest = CFHTTPMessageCreateEmpty(NULL, YES);
        BOOL success = CFHTTPMessageAppendBytes(saneRequest, [serializedRequest bytes], [serializedRequest length]);
        NSAssert(success, @"Invalid request data");
        
        CFStreamError error;
        success = CFHTTPMessageApplyCredentials(saneRequest,
                                                _currentAuth,
                                                 (CFStringRef)[credential user],
                                                 (CFStringRef)[credential password],
                                                 &error);
        NSAssert(success, @"Could not apply credential to request");
        
        CFStringRef authorization = CFHTTPMessageCopyHeaderFieldValue(saneRequest, CFSTR("Authorization"));
		
        CFRelease(saneRequest);
        

		[myCurrentRequest setHeader:(NSString *)authorization forKey:@"Authorization"];
		CFRelease(authorization);
	}
	
	// Basic HTTP authentication
    else if ([[[challenge protectionSpace] authenticationMethod] isEqualToString:NSURLAuthenticationMethodHTTPBasic])
    {
        // Store the new credential
		NSString *authString = [[NSString alloc] initWithFormat:@"%@:%@", [credential user], [credential password]];
		NSData *authData = [authString dataUsingEncoding:NSUTF8StringEncoding];
		[authString release];
		
		NSAssert(!_basicAccessAuthorizationHeader, @"_basicAccessAuthorizationHeader is not nil. It should be reset to nil straight after failing authentication");
		_basicAccessAuthorizationHeader = [[NSString alloc] initWithFormat:@"Basic %@", [authData base64Encoding]];
    }
    
    CFRelease(_currentAuth);    _currentAuth = NULL;
	
	
	// Resend the request with authentication.
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] sendCommand:myCurrentRequest];
}


@end


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
#import "CKDAVUploadFileResponse.h"
#import "NSURL+Connection.h"

enum {
	HTTPSentGenericRequestState = 32012
};

NSString *CKHTTPConnectionErrorDomain = @"CKHTTPConnectionErrorDomain";


@interface CKHTTPConnection (Authentication) 
/**
	@method _digestAuthorizationStringForRequest:
	@abstract Creates a digest authorization string for the given request, if possible.
	@param request The request to create a digest authorization stirng for. May not be nil.
	@result The digest authorization string.
 */
- (NSString *)_digestAuthorizationHeaderForRequest:(CKHTTPRequest *)request;
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
	[_basicAccessAuthorizationHeader release];
	if (_currentAuth)
		CFRelease(_currentAuth);
	
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
	//Reset Digest Authentication
	[super threadedConnect];
	[[self client] connectionDidOpenAtPath:@"/" error:nil];
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
			return;
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
	
	[[self client] appendLine:[[response description] stringByAppendingString:@"\n"] toTranscript:CKTranscriptReceived];
	
	//If we're 401 and an upload, don't print the response (i.e., failed) , since we're going to send an authorization.
	if ([response code] != 401 || ![response isKindOfClass:[CKDAVUploadFileResponse class]])
		[[self client] appendLine:[[response formattedResponse] stringByAppendingString:@"\n"] toTranscript:CKTranscriptData];
	
	
	if ([response code] == 401)
	{		
		[[self client] appendLine:@"Connection needs Authorization" toTranscript:CKTranscriptSent];
		
		CFHTTPMessageRef saneResponse = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, FALSE);
		
		BOOL validData = CFHTTPMessageAppendBytes(saneResponse, [packetData bytes], [packetData length]);
		NSAssert(validData, @"Authorization request that CKResponse could handle, but CFMessage could not");
		
		NSURL *baseURL = [[self request] URL];
		NSURL *URL = [NSURL URLWithString:[[myCurrentRequest uri] encodeLegally] relativeToURL:baseURL];
		CFURLRef absoluteURL = (CFURLRef)[URL absoluteURL];
		_CFHTTPMessageSetResponseURL(saneResponse, absoluteURL);	//bug in CFHTTPMessage requires this to be used when working with CFHTTPMessageCreateEmpty
		
		_currentAuth = CFHTTPAuthenticationCreateFromResponse(kCFAllocatorDefault, saneResponse);
		CFStreamError error;
		NSAssert(CFHTTPAuthenticationIsValid(_currentAuth, &error), @"Response does not contain valid authentication info");
		NSAssert(CFHTTPAuthenticationRequiresUserNameAndPassword(_currentAuth), @"CKHTTPConnection only supports username and password authentication");
		NSAssert(!CFHTTPAuthenticationRequiresAccountDomain(_currentAuth), @"CKHTTPConnection does not support domain authentication");
		
		CFRelease(saneResponse);
		
		// Ask the delegate to authenticate
		NSString *authMethod = [(NSString *)CFHTTPAuthenticationCopyMethod(_currentAuth) autorelease];
		if ([authMethod isEqualToString:@"Basic"])
		{
			[self _authenticateConnectionWithMethod:NSURLAuthenticationMethodHTTPBasic];
			return;
		}
		else if ([authMethod isEqualToString:@"Digest"])
		{
			[self _authenticateConnectionWithMethod:NSURLAuthenticationMethodHTTPDigest];
			return;
		}
		else
		{
			[[self client] appendLine:@"CKHTTPConnection could not authenticate!" toTranscript:CKTranscriptSent];
			
			@throw [NSException exceptionWithName:NSInternalInconsistencyException
										   reason:@"Failed at Basic and Digest Authentication"
										 userInfo:nil];
		}
	}
	//"forbidden" indicates a failure of authentication.
	else if ([response code] != 403)
    {
        // We're currently authenticated, so reset the failure counter
		_hasAttemptedAuthentication = NO;
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
		
		BOOL isAuthenticated = [self setAuthenticationWithRequest:req];
		[[self client] appendString:[[req description] stringByAppendingString:@"\n"] toTranscript:CKTranscriptSent];
		
		NSData *headerPacket = [req serializedHeader];

		[self initiatingNewRequest:req withPacket:headerPacket];
		
		KTLog(CKProtocolDomain, KTLogDebug, @"HTTP Sending: %@", [headerPacket descriptionAsUTF8String]);
		
		//Send the header
		[self sendData:headerPacket];
		
		//Send the actual content if there is any. We only do this if we've got some authentication (otherwise we're sending for no reason)
		if (isAuthenticated && [req contentLength] > 0)
			[self sendData:[req content]];
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

- (BOOL)setAuthenticationWithRequest:(CKHTTPRequest *)request
{
	//Do we already have an authentication header? If so, leave it in tact.
	if ([request headerForKey:@"Authorization"])
		return YES;
	
	NSString *authorizationString = nil;

	NSString *digestAuthorizationString = [self _digestAuthorizationHeaderForRequest:request];
	if (digestAuthorizationString)
		authorizationString = digestAuthorizationString;
	else if (_basicAccessAuthorizationHeader)
		authorizationString = _basicAccessAuthorizationHeader;
	
	if (authorizationString)
	{
		[request setHeader:authorizationString forKey:@"Authorization"];
		return YES;
	}
	
	return NO;
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
			
			[_sendBufferLock lock];
			BOOL sendBufferQueueIsEmpty = [_sendBufferQueue count] == 0;
			[_sendBufferLock unlock];
			if (myCurrentRequest && !sendBufferQueueIsEmpty)
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
			
			if ([self state] == CKConnectionNotConnectedState)
				[self setState:CKConnectionIdleState];
			
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
			
			[_sendBufferLock lock];
			BOOL sendBufferQueueIsEmpty = [_sendBufferQueue count] == 0;
			[_sendBufferLock unlock];
			if (myCurrentRequest && !sendBufferQueueIsEmpty)
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
			
			if ([self state] == CKConnectionNotConnectedState)
				[self setState:CKConnectionIdleState];
			
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

- (void)_authenticateConnectionWithMethod:(NSString *)authenticationMethod
{
	//If we've already attempted authentication, our we don't have a user and a password, fail.
	BOOL canAttemptAuthentication = (!_hasAttemptedAuthentication && [[[self request] URL] user] && [[[self request] URL] originalUnescapedPassword]);
	if (!canAttemptAuthentication)
	{
		//Authentication information is wrong. Send an error and disconnect.
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:LocalizedStringInConnectionKitBundle(@"The connection failed to be authenticated properly. Check the username and password.", @"Authentication Failed"), NSLocalizedDescriptionKey, nil];
		NSError *error = [NSError errorWithDomain:CKHTTPConnectionErrorDomain code:0 userInfo:userInfo];
		[[self client] connectionDidOpenAtPath:nil error:error];
		
		[self disconnect];
		
		return;
	}
	
	//If we're using basic authorization, store the authorization header.
	if ([authenticationMethod isEqualToString:NSURLAuthenticationMethodHTTPBasic])
    {
        // Store the new credential
		NSString *username = [[[self request] URL] user];
		NSString *password = [[[self request] URL] originalUnescapedPassword];
		
		NSString *authString = [[NSString alloc] initWithFormat:@"%@:%@", username, password];
		NSData *authData = [authString dataUsingEncoding:NSUTF8StringEncoding];
		[authString release];
		
		NSAssert(!_basicAccessAuthorizationHeader, @"_basicAccessAuthorizationHeader is not nil. It should be reset to nil straight after failing authentication");
		_basicAccessAuthorizationHeader = [[NSString alloc] initWithFormat:@"Basic %@", [authData base64Encoding]];
    }
	
	//We only do this once.
	_hasAttemptedAuthentication = YES;
		
	// Resend the request with authentication.
	[[[CKConnectionThreadManager defaultManager] prepareWithInvocationTarget:self] sendCommand:myCurrentRequest];	
}

- (NSString *)_digestAuthorizationHeaderForRequest:(CKHTTPRequest *)request
{
	NSParameterAssert(request);
	if (!_currentAuth)
		return nil;
	
	NSData *serializedRequest = [request serializedHeader];
	CFHTTPMessageRef saneRequest = CFHTTPMessageCreateEmpty(NULL, YES);
	BOOL success = CFHTTPMessageAppendBytes(saneRequest, [serializedRequest bytes], [serializedRequest length]);
	NSAssert(success, @"Invalid request data");
	
	CFStreamError error;
	success = CFHTTPMessageApplyCredentials(saneRequest,
											_currentAuth, 
											(CFStringRef)[[[self request] URL] user],
											(CFStringRef)[[[self request] URL] originalUnescapedPassword],
											&error);
	NSAssert(success, @"Could not apply credential to request");
	
	CFStringRef authorizationHeader = CFHTTPMessageCopyHeaderFieldValue(saneRequest, CFSTR("Authorization"));
	CFRelease(saneRequest);
	
	return [(NSString *)authorizationHeader autorelease];
}


@end


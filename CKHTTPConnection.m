//
//  CKHTTPConnection.m
//  Connection
//
//  Created by Mike on 17/03/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKHTTPConnection.h"

#import "CKConnectionAuthentication.h"


// There is no public API for creating an NSHTTPURLResponse. The only way to create one then, is to
// have a private subclass that others treat like a standard NSHTTPURLResponse object. Framework
// code can instantiate a CKHTTPURLResponse object directly. Alternatively, there is a public
// convenience method +[NSHTTPURLResponse responseWithURL:HTTPMessage:]
@interface CKHTTPURLResponse : NSHTTPURLResponse
{
    @private
    NSInteger       _statusCode;
    NSDictionary    *_headerFields;
}

- (id)initWithURL:(NSURL *)URL HTTPMessage:(CFHTTPMessageRef)message;
@end


@interface CKHTTPAuthenticationChallenge : NSURLAuthenticationChallenge
{
    CFHTTPAuthenticationRef _HTTPAuthentication;
}

- (id)initWithResponse:(CFHTTPMessageRef)response
    proposedCredential:(NSURLCredential *)credential
  previousFailureCount:(NSInteger)failureCount
       failureResponse:(NSHTTPURLResponse *)URLResponse
                sender:(id <NSURLAuthenticationChallengeSender>)sender;

- (CFHTTPAuthenticationRef)CFHTTPAuthentication;

@end


@interface CKHTTPConnection ()
- (CFHTTPMessageRef)HTTPRequest;
- (NSInputStream *)HTTPStream;

- (void)start;
- (id <CKHTTPConnectionDelegate>)delegate;
@end


@interface CKHTTPConnection (Authentication) <NSURLAuthenticationChallengeSender>
- (CKHTTPAuthenticationChallenge *)currentAuthenticationChallenge;
@end


#pragma mark -


@implementation CKHTTPConnection

#pragma mark  Init & Dealloc

+ (CKHTTPConnection *)connectionWithRequest:(NSURLRequest *)request delegate:(id <CKHTTPConnectionDelegate>)delegate
{
    return [[[self alloc] initWithRequest:request delegate:delegate] autorelease];
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id <CKHTTPConnectionDelegate>)delegate;
{
    NSParameterAssert(request);
    
    if (self = [super init])
    {
        _delegate = delegate;
        
        // Kick off the connection
        _HTTPRequest = [request CFHTTPMessage];
        CFRetain(_HTTPRequest);
        
        [self start];
    }
    
    return self;
}

- (void)dealloc
{
    CFRelease(_HTTPRequest);
    NSAssert(!_HTTPStream, @"Deallocating HTTP connection while stream still exists");
    NSAssert(!_authenticationChallenge, @"HTTP connection deallocated mid-authentication");
    
    [super dealloc];
}

#pragma mark Accessors

- (CFHTTPMessageRef)HTTPRequest { return _HTTPRequest; }

- (NSInputStream *)HTTPStream { return _HTTPStream; }

- (NSInputStream *)stream { return (NSInputStream *)[self HTTPStream]; }

- (id <CKHTTPConnectionDelegate>)delegate { return _delegate; }

/*  CFNetwork provides no callback API for upload progress, so clients must request it themselves.
 */
- (NSUInteger)lengthOfDataSent
{
    return [[[self stream]
             propertyForKey:(NSString *)kCFStreamPropertyHTTPRequestBytesWrittenCount]
            unsignedIntValue];
}

#pragma mark Status handling

- (void)start
{
    NSAssert(!_HTTPStream, @"Connection already started");
    
    _HTTPStream = (NSInputStream *)CFReadStreamCreateForHTTPRequest(NULL, [self HTTPRequest]);
    [_HTTPStream setDelegate:self];
    [_HTTPStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_HTTPStream open];
}

- (void)_cancelStream
{
    // Support method to cancel the HTTP stream, but not change the delegate. Used for:
    //  A) Cancelling the connection
    //  B) Waiting to restart the connection while authentication takes place
    //  C) Restarting the connection after an HTTP redirect
    [_HTTPStream close];
    [_HTTPStream release];  _HTTPStream = nil;
}

- (void)cancel
{
    // Cancel the stream and stop the delegate receiving any more info
    [self _cancelStream];
    _delegate = nil;
}

- (void)stream:(NSInputStream *)theStream handleEvent:(NSStreamEvent)streamEvent
{
    NSParameterAssert(theStream == [self stream]);
    
    
    
    switch (streamEvent)
    {
            
        case NSStreamEventErrorOccurred:    // Report an error in the stream as the operation failing
            [[self delegate] HTTPConnection:self didFailWithError:[theStream streamError]];
            break;
            
            
            
        case NSStreamEventEndEncountered:   // Report the end of the stream to the delegate
            [[self delegate] HTTPConnectionDidFinishLoading:self];
            break;
    
        
        case NSStreamEventHasBytesAvailable:
        {
            // Handle the response as soon as it's available
            if (!_haveReceivedResponse)
            {
                CFHTTPMessageRef response = (CFHTTPMessageRef)[theStream propertyForKey:(NSString *)kCFStreamPropertyHTTPResponseHeader];
                if (CFHTTPMessageIsHeaderComplete(response))
                {
                    // Construct a NSURLResponse object from the HTTP message
                    NSURL *URL = [theStream propertyForKey:(NSString *)kCFStreamPropertyHTTPFinalURL];
                    NSHTTPURLResponse *URLResponse = [NSHTTPURLResponse responseWithURL:URL HTTPMessage:response];
                    
                    
                    // If the response was an authentication failure, try to request fresh credentials.
                    if ([URLResponse statusCode] == 401 || [URLResponse statusCode] == 407)
                    {
                        // Cancel any further loading and ask the delegate for authentication
                        [self _cancelStream];
                        
                        NSAssert(![self currentAuthenticationChallenge],
                                 @"Authentication challenge received while another is in progress");
                        
                        _authenticationChallenge = [[CKHTTPAuthenticationChallenge alloc] initWithResponse:response
                                                                                        proposedCredential:nil
                                                                                      previousFailureCount:_authenticationAttempts
                                                                                           failureResponse:URLResponse
                                                                                                    sender:self];
                        
                        if ([self currentAuthenticationChallenge])
                        {
                            _authenticationAttempts++;
                            [[self delegate] HTTPConnection:self didReceiveAuthenticationChallenge:[self currentAuthenticationChallenge]];
                            
                            return; // Stops the delegate being sent a response recevied message
                        }
                    }
                    
                    
                    // By reaching this point, the response was not a valid request for authentication,
                    // so go ahead and report it
                    _haveReceivedResponse = YES;
                    [[self delegate] HTTPConnection:self didReceiveResponse:URLResponse];
                }
            }
            
            
            // Report any data loaded to the delegate
            if ([theStream hasBytesAvailable])
            {
                NSMutableData *data = [[NSMutableData alloc] initWithCapacity:1024];
                while ([theStream hasBytesAvailable])
                {
                    uint8_t buf[1024];
                    NSUInteger len = [theStream read:buf maxLength:1024];
                    [data appendBytes:(const void *)buf length:len];
                }
                
                [[self delegate] HTTPConnection:self didReceiveData:data];
            }
        }
    }
}

@end


@implementation CKHTTPConnection (Authentication)

- (CKHTTPAuthenticationChallenge *)currentAuthenticationChallenge { return _authenticationChallenge; }

- (void)_finishCurrentAuthenticationChallenge
{
    [_authenticationChallenge autorelease]; // we still want to work with the challenge for a moment
    _authenticationChallenge = nil;
}

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSParameterAssert(challenge == [self currentAuthenticationChallenge]);
    [self _finishCurrentAuthenticationChallenge];
    
    // Retry the request, this time with authentication
    CFHTTPAuthenticationRef HTTPAuthentication = [(CKHTTPAuthenticationChallenge *)challenge CFHTTPAuthentication];
    CFHTTPMessageApplyCredentials([self HTTPRequest],
                                  HTTPAuthentication,
                                  (CFStringRef)[credential user],
                                  (CFStringRef)[credential password],
                                  NULL);
    [self start];
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSParameterAssert(challenge == [self currentAuthenticationChallenge]);
    [self _finishCurrentAuthenticationChallenge];
    
    // Just return the authentication response to the delegate
    [[self delegate] HTTPConnection:self didReceiveResponse:(NSHTTPURLResponse *)[challenge failureResponse]];
    [[self delegate] HTTPConnectionDidFinishLoading:self];
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSParameterAssert(challenge == [self currentAuthenticationChallenge]);
    [self _finishCurrentAuthenticationChallenge];
    
    // Treat like a -cancel message
    [self cancel];
}

@end


#pragma mark -


@implementation NSURLRequest (CKHTTPConnectionAdditions)

+ (id)requestWithURL:(NSURL *)URL HTTPMethod:(NSString *)HTTPMethod
{
    // The callers need not know that the returned object is actually mutable
    return [NSMutableURLRequest requestWithURL:URL HTTPMethod:HTTPMethod];
}

- (CFHTTPMessageRef)CFHTTPMessage
{
    CFHTTPMessageRef result = CFHTTPMessageCreateRequest(NULL,
                                                         (CFStringRef)[self HTTPMethod],
                                                         (CFURLRef)[self URL],
                                                         kCFHTTPVersion1_1);
    [(NSObject *)result autorelease];
    
    NSDictionary *HTTPHeaderFields = [self allHTTPHeaderFields];
    NSEnumerator *HTTPHeaderFieldsEnumerator = [HTTPHeaderFields keyEnumerator];
    NSString *aHTTPHeaderField;
    while (aHTTPHeaderField = [HTTPHeaderFieldsEnumerator nextObject])
    {
        CFHTTPMessageSetHeaderFieldValue(result,
                                         (CFStringRef)aHTTPHeaderField,
                                         (CFStringRef)[HTTPHeaderFields objectForKey:aHTTPHeaderField]);
    }
    
    NSData *body = [self HTTPBody];
    if (body)
    {
        CFHTTPMessageSetBody(result, (CFDataRef)body);
    }
    
    return result;
}

@end


@implementation NSMutableURLRequest (CKHTTPConnectionAdditions)

+ (id)requestWithURL:(NSURL *)URL HTTPMethod:(NSString *)HTTPMethod
{
    // A better implementation than the superclass's as callers are expecting a mutable object in return
    return [[[self alloc] initWithURL:URL HTTPMethod:HTTPMethod] autorelease];
}

- (id)initWithURL:(NSURL *)URL HTTPMethod:(NSString *)HTTPMethod
{
    if (self = [self initWithURL:URL])
    {
        if (HTTPMethod)
        {
            [self setHTTPMethod:HTTPMethod];
        }
    }
    
    return self;
}

@end


#pragma mark -


@implementation NSHTTPURLResponse (CKHTTPConnectionAdditions)

+ (NSHTTPURLResponse *)responseWithURL:(NSURL *)URL HTTPMessage:(CFHTTPMessageRef)message
{
    return [[[CKHTTPURLResponse alloc] initWithURL:URL HTTPMessage:message] autorelease];
}

@end


@implementation CKHTTPURLResponse

- (id)initWithURL:(NSURL *)URL HTTPMessage:(CFHTTPMessageRef)message
{
    _headerFields = (NSDictionary *)CFHTTPMessageCopyAllHeaderFields(message);
    
    NSString *MIMEType = nil;
    NSInteger contentLength = [[_headerFields objectForKey:@"Content-Length"] intValue];
    NSString *encoding = nil;
    
    if (self = [super initWithURL:URL MIMEType:MIMEType expectedContentLength:contentLength textEncodingName:encoding])
    {
        _statusCode = CFHTTPMessageGetResponseStatusCode(message);
    }
    return self;
}
    
- (void)dealloc
{
    [_headerFields release];
    [super dealloc];
}

- (NSDictionary *)allHeaderFields { return _headerFields;  }

- (NSInteger)statusCode { return _statusCode; }

@end


#pragma mark -


@implementation CKHTTPAuthenticationChallenge

/*  Returns nil if the ref is not suitable
 */
- (id)initWithResponse:(CFHTTPMessageRef)response
    proposedCredential:(NSURLCredential *)credential
  previousFailureCount:(NSInteger)failureCount
       failureResponse:(NSHTTPURLResponse *)URLResponse
                sender:(id <NSURLAuthenticationChallengeSender>)sender
{
    NSParameterAssert(response);
    
    
    // Try to create an authentication object from the response
    _HTTPAuthentication = CFHTTPAuthenticationCreateFromResponse(NULL, response);
    if (![self CFHTTPAuthentication])
    {
        [self release];
        return nil;
    }
    
    
    // NSURLAuthenticationChallenge only handles user and password
    if (!CFHTTPAuthenticationIsValid([self CFHTTPAuthentication], NULL))
    {
        [self release];
        return nil;
    }
    
    if (!CFHTTPAuthenticationRequiresUserNameAndPassword([self CFHTTPAuthentication]))
    {
        [self release];
        return nil;
    }
    
    
    // Fail if we can't retrieve decent protection space info
    NSArray *authenticationDomains = (NSArray *)CFHTTPAuthenticationCopyDomains([self CFHTTPAuthentication]);
    NSURL *URL = [authenticationDomains lastObject];
    [authenticationDomains release];
    if (!URL || ![URL host])
    {
        [self release];
        return nil;
    }
    
    
    // Fail for an unsupported authentication method
    CFStringRef CFAuthenticationMethod = CFHTTPAuthenticationCopyMethod([self CFHTTPAuthentication]);
    NSString *authenticationMethod;
    if ([(NSString *)CFAuthenticationMethod isEqualToString:(NSString *)kCFHTTPAuthenticationSchemeBasic])
    {
        authenticationMethod = NSURLAuthenticationMethodHTTPBasic;
    }
    else if ([(NSString *)CFAuthenticationMethod isEqualToString:(NSString *)kCFHTTPAuthenticationSchemeDigest])
    {
        authenticationMethod = NSURLAuthenticationMethodHTTPDigest;
    }
    else
    {
        [self release]; // unsupport authentication scheme
        return nil;
    }
    CFRelease(CFAuthenticationMethod);
    
    
    // Initialise
    CFStringRef realm = CFHTTPAuthenticationCopyRealm([self CFHTTPAuthentication]);
    
    NSURLProtectionSpace *protectionSpace = [[NSURLProtectionSpace alloc] initWithHost:[URL host]
                                                                                  port:([URL port] ? [[URL port] intValue] : 80)
                                                                              protocol:[URL scheme]
                                                                                 realm:(NSString *)realm
                                                                  authenticationMethod:authenticationMethod];
    CFRelease(realm);
    
    self = [self initWithProtectionSpace:protectionSpace
                      proposedCredential:credential
                    previousFailureCount:failureCount
                         failureResponse:URLResponse
                                   error:nil
                                  sender:sender];
    
    
    // Tidy up
    [protectionSpace release];
    return self;
}

- (void)dealloc
{
    CFRelease(_HTTPAuthentication);
    [super dealloc];
}

- (CFHTTPAuthenticationRef)CFHTTPAuthentication { return _HTTPAuthentication; }

@end

            

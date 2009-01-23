//
//  CKWebDAVProtocol.m
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKWebDAVProtocol.h"

#import "NSURLAuthentication+ConnectionKit.h"


@interface CKWebDAVProtocol (Private)
- (void)processResponse:(CFHTTPMessageRef)response;
@end


@implementation CKWebDAVProtocol

+ (BOOL)canInitWithConnectionRequest:(CKConnectionRequest *)request;
{
    NSURL *URL = [request URL];
    
    NSString *scheme = [URL scheme];
    if (scheme && [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
    {
        NSString *host = [URL host];
        if (host && ![host isEqualToString:@""])
        {
            return YES;
        }
    }
    
    return NO;
}

#pragma mark -
#pragma mark Connection

- (void)startConnection
{
    // WebDAV is built atop HTTP requests, not a connection stream. So, pretend we've connected
    // We could adjust this in the future by sending an exploratory request like Transmit does
    [[self client] protocol:self didStartConnectionAtPath:[[[self request] URL] path]];
}

- (void)stopConnection
{
    CFReadStreamClose(_HTTPStream);
}


- (void)uploadData:(NSData *)data toPath:(NSString *)path
{
    _status = CKWebDAVProtocolStatusUploading;
    
    
    // Send a PUT request with the data
    NSURL *URL = [[NSURL alloc] initWithString:path relativeToURL:[[self request] URL]];
    CFHTTPMessageRef request = CFHTTPMessageCreateRequest(NULL, CFSTR("PUT"), (CFURLRef)URL, kCFHTTPVersion1_1);
    [URL release];
    
    
    // Include MIME type
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                            (CFStringRef)[path pathExtension],
                                                            NULL);
    CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);	
    if (!MIMEType || [(NSString *)MIMEType length] == 0)
    {
        // if this list grows, consider using a dictionary of corrected UTI to MIME mappings instead
        if ([(NSString *)UTI isEqualToString:@"public.css"])
        {
            MIMEType = CFSTR("text/css");
        }
        else if ([(NSString *)UTI isEqualToString:(NSString *)kUTTypeICO])
        {
            MIMEType = CFSTR("image/vnd.microsoft.icon");
        }
        else
        {
            MIMEType = CFSTR("application/octet-stream");
        }
    }
    CFRelease(UTI);
    
    CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Content-Type"), MIMEType);
    CFRelease(MIMEType);
    
    
    // Include data
    CFHTTPMessageSetBody(request, (CFDataRef)data);
    
    
    // Send the request
    [self startHTTPRequest:request];
    CFRelease(request);
}

- (void)createDirectoryAtPath:(NSString *)path
{
    _status = CKWebDAVProtocolStatusCreatingDirectory;
    
    
    // Send a MKCOL request
    NSURL *URL = [[NSURL alloc] initWithString:path relativeToURL:[[self request] URL]];
    CFHTTPMessageRef request = CFHTTPMessageCreateRequest(NULL, CFSTR("MKCOL"), (CFURLRef)URL, kCFHTTPVersion1_1);
    [URL release];
    
    
    // Send the request
    [self startHTTPRequest:request];
    CFRelease(request);
}

- (void)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath
{
    _status = CKWebDAVProtocolStatusMovingItem;
    
    
    // Send a MOVE request
    NSURL *fromURL = [[NSURL alloc] initWithString:fromPath relativeToURL:[[self request] URL]];
    CFHTTPMessageRef request = CFHTTPMessageCreateRequest(NULL, CFSTR("MOVE"), (CFURLRef)fromURL, kCFHTTPVersion1_1);
    [fromURL release];
    
    
    // The destination is a request header
    NSURL *toURL = [[NSURL alloc] initWithString:toPath relativeToURL:[[self request] URL]];
    CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Destination"), (CFStringRef)[toURL absoluteString]);
    [toURL release];
    
    
    // Send the request
    [self startHTTPRequest:request];
    CFRelease(request);
}

- (void)deleteItemAtPath:(NSString *)path
{
    _status = CKWebDAVProtocolStatusDeletingItem;
    
    
    // Send a DELETE request
    NSURL *URL = [[NSURL alloc] initWithString:path relativeToURL:[[self request] URL]];
    CFHTTPMessageRef request = CFHTTPMessageCreateRequest(NULL, CFSTR("DELETE"), (CFURLRef)URL, kCFHTTPVersion1_1);
    [URL release];
    
    
    // Send the request
    [self startHTTPRequest:request];
    CFRelease(request);
}

- (void)stopCurrentOperation
{
    _status = CKWebDAVProtocolStatusIdle;
    CFReadStreamClose(_HTTPStream);
}


/*  These methods send the appropriate message to the client, and tidy up ivars
 */

- (void)_cleanUpIVarsAfterOperation
{
    NSAssert(CFReadStreamGetStatus(_HTTPStream) == kCFStreamStatusClosed, @"Connection has not closed yet");
    
    _status = CKWebDAVProtocolStatusIdle;
    
    CFRelease(_HTTPRequest);    _HTTPRequest = NULL;
    CFRelease(_HTTPStream);     _HTTPStream = NULL;
    _hasProcessedHTTPResponse = NO;
    
    if (_authenticationRef)
    {
        CFRelease(_authenticationRef);      _authenticationRef = NULL;
    }
    [_authenticationChallenge release];     _authenticationChallenge = nil;
}

- (void)finishOperation
{
    [self _cleanUpIVarsAfterOperation];
    [[self client] protocolCurrentOperationDidFinish:self];
}

- (void)failOperationWithError:(NSError *)error
{
    [self _cleanUpIVarsAfterOperation];
    [[self client] protocol:self currentOperationDidFailWithError:error];
}

#pragma mark -
#pragma mark Stream

/*  Creates and schedules a read stream for the request. Both the request and stream are stored as
 *  ivars so they can be managed as they progress.
 */
- (void)startHTTPRequest:(CFHTTPMessageRef)request;
{
    NSAssert(!_HTTPRequest, @"Attempting to start an HTTP request while another is still stored");
    NSAssert(!_HTTPStream, @"Attempting to start an HTTP request while a response is stored");
    
    
    _HTTPRequest = request;
    CFRetain(_HTTPRequest);
    
    _HTTPStream = CFReadStreamCreateForHTTPRequest(NULL, request);
    [(NSInputStream *)_HTTPStream setDelegate:self];
    [(NSInputStream *)_HTTPStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    NSAssert(CFReadStreamOpen(_HTTPStream), @"Opening the HTTP stream failed");
}

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent
{
    switch (streamEvent)
    {
        case NSStreamEventHasBytesAvailable:
        {
            // Create and handle response if we haven't had one yet
            if (!_hasProcessedHTTPResponse)
            {
                CFHTTPMessageRef response = (CFHTTPMessageRef)CFReadStreamCopyProperty(_HTTPStream, kCFStreamPropertyHTTPResponseHeader);
                
                // Is the response complete? If not, carry on
                if (CFHTTPMessageIsHeaderComplete(response))
                {
                    _hasProcessedHTTPResponse = YES;
                    
                    CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(response);
                    if (statusCode == 401 || statusCode == 407)
                    {
                        // Cancel the stream
                        //[(NSStream *)_HTTPStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
                        CFReadStreamClose(_HTTPStream); // According to the docs this should remove it from any run loops
                        
                        
                        // If the request failed authentication, ask the client for some
                        _authenticationRef = CFHTTPAuthenticationCreateFromResponse(NULL, response);
                        NSAssert(_authenticationRef, @"Connection failed authentication, but contains no valid authentication information");
                        
                        
                        NSInteger failureCount = (_authenticationChallenge) ? [_authenticationChallenge previousFailureCount] + 1 : 0;
                        
                        [_authenticationChallenge release];
                        NSError *error = nil;
                        _authenticationChallenge = [[NSURLAuthenticationChallenge alloc] initWithHTTPAuthenticationRef:_authenticationRef
                                                                                                    proposedCredential:nil
                                                                                                  previousFailureCount:failureCount
                                                                                                                sender:self
                                                                                                                 error:&error];
                        
                        if (_authenticationChallenge)
                        {
                            [[self client] protocol:self didReceiveAuthenticationChallenge:_authenticationChallenge];
                        }
                        else
                        {
                            // This error could be more verbose!
                            if (!error) error = [NSError errorWithHTTPResponse:response];
                            [self failOperationWithError:error];
                        }
                        
                        return;
                        break;
                    }
                    else
                    {
                        [self processResponse:response];
                    }
                }
                
                CFRelease(response);
            }
            
            
            // Report data to the delegate
            if (_status == CKWebDAVProtocolStatusDownload)
            {
                CFIndex numBytes;
                const UInt8 *buffer = CFReadStreamGetBuffer(_HTTPStream, 0, &numBytes);
                if (buffer && numBytes)
                {
                    NSData *data = [[NSData alloc] initWithBytes:buffer length:numBytes];
                    [[self client] protocol:self didLoadData:data];
                    [data release];
                }
                else
                {
                    // We're finished reading.
                    CFReadStreamClose(_HTTPStream);
                    [self finishOperation];
                }
            }
        }
            break;
            
            
        case NSStreamEventErrorOccurred:
            // TODO: report stream error
            break;
    }
}


/*  Processes the response to send the right delegate messages.
 */
- (void)processResponse:(CFHTTPMessageRef)response
{
	CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(response);
    BOOL    continueLoading = NO;   // Its only for successful downloads and directory listings that we're interested
    
    
    // It's quite likely there's an error. Make handling it easy
    BOOL    result = NO;
    NSString *localizedErrorDescription = nil;
    int errorCode = CKConnectionErrorUnknown;
    NSMutableDictionary *errorUserInfo = [NSMutableDictionary dictionary];
    
    
    
    
    
    // Handle the response
    KTLog(CKProtocolDomain, KTLogDebug, @"%@", response);
	switch (_status)
	{
		case CKWebDAVProtocolStatusListingDirectory:
		{
			/*
            NSError *error = nil;
			NSString *localizedDescription = nil;
			NSArray *contents = [NSArray array];
			switch ([dav code])
			{
				case 200:
				case 207: //multi-status
				{
					contents = [dav directoryContents];
					[self cacheDirectory:[dav path] withContents:contents];
					break;
				}
				case 404:
				{		
					localizedDescription = [NSString stringWithFormat: @"%@: %@", LocalizedStringInConnectionKitBundle(@"There is no WebDAV access to the directory", @"No WebDAV access to the specified path"), [dav path]];
					break;
				}
				default: 
				{
					localizedDescription = LocalizedStringInConnectionKitBundle(@"Unknown Error Occurred", @"WebDAV Error");
					break;
				}
			}
			
            if (localizedDescription)
            {
                NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                          localizedDescription, NSLocalizedDescriptionKey,
                                          [dav path], NSFilePathErrorKey,
                                          [dav className], @"DAVResponseClass", nil];				
                error = [NSError errorWithDomain:WebDAVErrorDomain code:[dav code] userInfo:userInfo];
            }
            NSString *dirPath = [dav path];
            if ([dirPath hasSuffix:@"/"])
                dirPath = [dirPath substringToIndex:[dirPath length] - 1];				
            [[self client] connectionDidReceiveContents:contents ofDirectory:dirPath error:error];
            
			[self setState:CKConnectionIdleState];*/
			break;
		}
		case CKWebDAVProtocolStatusCreatingDirectory:
		{
			switch (statusCode)
			{
				case 201: 
                case 405:   // The directory already exists. Considering this effectively a success for now
				    result = YES;
					break;
									
				case 403:
					errorCode = CKConnectionErrorNoPermissionsToReadFile;
                    localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"The server does not allow the creation of directories at the current location", @"WebDAV Create Directory Error");
                    //we fake the directory exists as this is usually the case if it is the root directory
					[errorUserInfo setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
					break;
				
                case 409:
					errorCode = CKConnectionErrorFileDoesNotExist;
                    localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"An intermediate directory does not exist and needs to be created before the current directory", @"WebDAV Create Directory Error");
					break;
				
				case 415:
					localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"The body of the request is not supported", @"WebDAV Create Directory Error");
					break;
				
				case 507:
					errorCode = CKConnectionErrorInsufficientStorage;
                    localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"Insufficient storage space available", @"WebDAV Create Directory Error");
					break;
				
				default: 
					localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"An unknown error occured", @"WebDAV Create Directory Error");
					break;
			}
			
            break;
		}
		case CKWebDAVProtocolStatusUploading:
		{
			switch (statusCode)
			{
				case 201:
                    result = YES;
                    break;
                    
                case 409:
					errorCode = CKConnectionErrorFileDoesNotExist;
                    localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"Parent Folder does not exist", @"WebDAV Uploading Error");
					break;
				
				default:
					break;
			}
                        
			break;
		}
		case CKWebDAVProtocolStatusDeletingItem:
		{
			switch (statusCode)
			{
				case 200:
				case 201:
				case 204:
					result = YES;
					break;
				
				default:
					localizedErrorDescription = [NSString stringWithFormat:@"%@", LocalizedStringInConnectionKitBundle(@"Failed to delete file", @"WebDAV File Deletion Error")]; 
					break;
			}
			
            break;
		}
		case CKWebDAVProtocolStatusMovingItem:
		{
			
			break;
		}
		default:
            break;
	}
    
    
    // Stop loading if possible
    if (!continueLoading)
    {
        CFReadStreamClose(_HTTPStream); // The stream handling code will release ivars etc. later
        
        if (result)
        {
            [self finishOperation];
        }
        else
        {
            NSError *underlyingError = [[NSError alloc] initWithHTTPResponse:response];
            
            [errorUserInfo setObject:underlyingError forKey:NSUnderlyingErrorKey];
            [errorUserInfo setObject:localizedErrorDescription forKey:NSLocalizedDescriptionKey];
            
            NSError *error = [[NSError alloc] initWithDomain:CKConnectionErrorDomain code:errorCode userInfo:errorUserInfo];
            [underlyingError release];
            
            [self failOperationWithError:error];
            [error release];
        }
    }
}

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    // Retry the request, this time with authentication
    _hasProcessedHTTPResponse = NO;
    
    NSAssert(CFHTTPMessageApplyCredentials(_HTTPRequest,
                                           _authenticationRef,
                                           (CFStringRef)[credential user],
                                           (CFStringRef)[credential password],
                                           NULL), @"Couldn't apply authentication credentials");
    
    CFRelease(_HTTPStream);
    _HTTPStream = CFReadStreamCreateForHTTPRequest(NULL, _HTTPRequest);
    
    [(NSInputStream *)_HTTPStream setDelegate:self];
    [(NSInputStream *)_HTTPStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    CFReadStreamOpen(_HTTPStream);
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [[self client] protocol:self currentOperationDidFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                                                      code:NSURLErrorUserAuthenticationRequired
                                                                                  userInfo:nil]];
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [[self client] protocol:self currentOperationDidFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                                                      code:NSURLErrorUserCancelledAuthentication
                                                                                  userInfo:nil]];
}

@end


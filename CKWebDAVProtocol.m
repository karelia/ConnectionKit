//
//  CKWebDAVProtocol.m
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKWebDAVProtocol.h"

#import "CKConnectionAuthentication.h"
#import "CKError.h"

#import "CKAbstractConnection.h"    // For KTLog. Remove dependency when possible


@interface CKWebDAVProtocol ()
- (void)currentOperationDidFinish:(BOOL)didFinish error:(NSError *)error;
@end


@implementation CKWebDAVProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request;
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
    _status = CKWebDAVProtocolStatusOpening;
    
    // The server needs to respond to an OPTIONS request confirming it supports WebDAV
    NSURL *URL = [[self request] URL];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setHTTPMethod:@"OPTIONS"];
    
    [self startOperationWithRequest:request];
    [request release];
}

- (void)stopConnection
{
    [_HTTPConnection cancel];
}

- (void)downloadContentsOfFileAtPath:(NSString *)remotePath
{
    _status = CKWebDAVProtocolStatusDownload;
    [super downloadContentsOfFileAtPath:remotePath];
}

- (void)uploadData:(NSData *)data toPath:(NSString *)path
{
    _status = CKWebDAVProtocolStatusUploading;
    
    [super uploadData:data toPath:path];
}

- (void)fetchContentsOfDirectoryAtPath:(NSString *)path
{
    _status = CKWebDAVProtocolStatusListingDirectory;
    
    
    // Send a PROPFIND request
    NSString *directoryPath = [path stringByAppendingString:@"/"];  // TODO: Handle the path like a proper POSIX one which could have any number of trailing slashes
    NSURL *URL = [[NSURL alloc] initWithString:directoryPath relativeToURL:[[self request] URL]];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setHTTPMethod:@"PROPFIND"];
    [request setValue:@"1" forHTTPHeaderField:@"Depth"];
    [URL release];
    
    
    
    // Send the request
    [self startOperationWithRequest:request];
    [request release];
}

- (void)createDirectoryAtPath:(NSString *)path
{
    _status = CKWebDAVProtocolStatusCreatingDirectory;
    
    
    // Send a MKCOL request
    NSURL *URL = [[NSURL alloc] initWithString:path relativeToURL:[[self request] URL]];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setHTTPMethod:@"MKCOL"];
    [URL release];
    
    
    // Send the request
    [self startOperationWithRequest:request];
    [request release];
}

- (void)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath
{
    _status = CKWebDAVProtocolStatusMovingItem;
    
    
    // Send a MOVE request
    NSURL *fromURL = [[NSURL alloc] initWithString:fromPath relativeToURL:[[self request] URL]];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:fromURL];
    [request setHTTPMethod:@"MOVE"];
    [fromURL release];
    
    
    // The destination is a request header
    NSURL *toURL = [[NSURL alloc] initWithString:toPath relativeToURL:[[self request] URL]];
    [request setValue:[toURL absoluteString] forHTTPHeaderField:@"Destination"];
    [toURL release];
    
    
    // Send the request
    [self startOperationWithRequest:request];
    [request release];
}

- (void)deleteItemAtPath:(NSString *)path
{
    _status = CKWebDAVProtocolStatusDeletingItem;
    [super deleteItemAtPath:path];
}

- (void)stopCurrentOperation
{
    _status = CKWebDAVProtocolStatusIdle;
    [_HTTPConnection cancel];
}

- (void)currentOperationDidFinish:(BOOL)didFinish error:(NSError *)error
{
    CKWebDAVProtocolStatus oldStatus = _status;
    _status = CKWebDAVProtocolStatusIdle;
    
    [_HTTPConnection cancel];       // definitely don't want to hear from it any more!
    
    [_HTTPConnection autorelease];  // autorelease otherwise the connection can be deallocated in
    _HTTPConnection = nil;          // the middle of sending a delegate method
    
    
    if (oldStatus == CKWebDAVProtocolStatusOpening)
    {
        if (didFinish)
        {
            [[self client] FSProtocol:self didOpenConnectionWithCurrentDirectoryPath:nil];
        }
        else
        {
            [[self client] FSProtocol:self didFailWithError:error];
        }
    }
    else
    {
        if (didFinish)
        {
            [[self client] FSProtocolDidFinishCurrentOperation:self];
        }
        else
        {
            [[self client] FSProtocol:self currentOperationDidFailWithError:error];
        }
    }
}

#pragma mark -
#pragma mark HTTP Connection

/*  Convenience method for 
+ (NSMutableURLRequest *)URLRequestWithURL:(NSURL *)URL HTTPMethod:(NSString *)httpMethod;
{
    
}
*/

/*  Creates and schedules an HTTP connection for the request.
 */
- (void)startOperationWithRequest:(NSURLRequest *)request
{
    NSAssert(!_HTTPConnection, @"Attempting to start an HTTP request while a response is stored");
    _HTTPConnection = [[CKHTTPConnection alloc] initWithRequest:request delegate:self];
}

- (void)HTTPConnection:(CKHTTPConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [[self client] FSProtocol:self didReceiveAuthenticationChallenge:challenge];
}

- (void)HTTPConnection:(CKHTTPConnection *)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    // Ignore for now
}

- (void)HTTPConnection:(CKHTTPConnection *)connection didReceiveResponse:(NSHTTPURLResponse *)response;
{
    // It's quite likely there's an error. Make handling it easy
    BOOL result = NO;
    NSString *localizedErrorDescription = nil;
    int errorCode = CKErrorUnknown;
    NSMutableDictionary *errorUserInfo = [NSMutableDictionary dictionary];
    
    
    
    
    
    // Handle the response
    switch (_status)
    {
        case CKWebDAVProtocolStatusOpening:
        {
            NSDictionary *headers = [response allHeaderFields];
            if ([headers objectForKey:@"DAV"] || [headers objectForKey:@"Dav"])
            {
                result = YES;
            }
            else
            {
                errorCode = CKErrorBadServerResponse;
                localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"The requested resource does not support WebDAV", "Error starting WebDAV connection");
            }
            
            break;
        }
        
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
            result = NO;
            break;
        }
        case CKWebDAVProtocolStatusCreatingDirectory:
        {
            switch ([response statusCode])
            {
                case 201: 
                case 405:   // The directory already exists. Considering this effectively a success for now
                    result = YES;
                    break;
                    
                case 403:
                    errorCode = CKErrorNoPermissionsToReadFile;
                    localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"The server does not allow the creation of directories at the current location", @"WebDAV Create Directory Error");
                    //we fake the directory exists as this is usually the case if it is the root directory
                    [errorUserInfo setObject:[NSNumber numberWithBool:YES] forKey:ConnectionDirectoryExistsKey];
                    break;
                    
                case 409:
                    errorCode = CKErrorFileDoesNotExist;
                    localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"An intermediate directory does not exist and needs to be created before the current directory", @"WebDAV Create Directory Error");
                    break;
                    
                case 415:
                    localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"The body of the request is not supported", @"WebDAV Create Directory Error");
                    break;
                    
                case 507:
                    errorCode = CKErrorDataLengthExceedsMaximum;
                    localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"Insufficient storage space available", @"WebDAV Create Directory Error");
                    break;
            }
            
            break;
        }
            
        case CKWebDAVProtocolStatusDownload:
        {
            switch ([response statusCode])
            {
                case 200:
                    result = YES;
                    return; // Download requests must handle the full body of the response
                    break;
            }
            break;
        }
            
        case CKWebDAVProtocolStatusUploading:
        {
            switch ([response statusCode])
            {
                case 201:
                    result = YES;
                    break;
                    
                case 409:
                    errorCode = CKErrorFileDoesNotExist;
                    localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"Parent Folder does not exist", @"WebDAV Uploading Error");
                    break;
                    
                default:
                    break;
            }
            
            break;
        }
            
        case CKWebDAVProtocolStatusDeletingItem:
        {
            switch ([response statusCode])
            {
                case 200:
                case 201:
                case 204:
                    result = YES;
                    break;
                    
                default:
                    localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"Failed to delete file", @"WebDAV File Deletion Error"); 
                    break;
            }
            
            break;
        }
        case CKWebDAVProtocolStatusMovingItem:
        {
            switch ([response statusCode])
            {
                case 201:
                    result = YES;
                    break;
                    
                default:
                    localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"The file could not be moved", @"WebDAV move error");
                    break;
            }
            break;
        }
        default:
            break;
    }
    
    
    // We have enough data, so finish up the connection and report
    NSError *error = nil;
    if (!result)
    {
        [errorUserInfo setObject:response forKey:CKErrorURLResponseErrorKey];
        
        if (!localizedErrorDescription) localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"An unknown error occured", @"Unknown connection error");
        [errorUserInfo setObject:localizedErrorDescription forKey:NSLocalizedDescriptionKey];
        
        error = [NSError errorWithDomain:CKErrorDomain code:errorCode userInfo:errorUserInfo];
    }
    
    [self currentOperationDidFinish:result error:error];
}

- (void)HTTPConnection:(CKHTTPConnection *)connection didReceiveData:(NSData *)data
{
    [[self client] FSProtocol:self didDownloadData:data];
}

- (void)HTTPConnectionDidFinishLoading:(CKHTTPConnection *)connection
{
    // If we reach this point, an operation requiring full data to be downloaded has finished
    [self currentOperationDidFinish:YES error:nil];
}

- (void)HTTPConnection:(CKHTTPConnection *)connection didFailWithError:(NSError *)error
{
    // If the HTTP connection failed, the file operation almost certainly did
    // TODO: Should we be coercing the error to CKErrorDomain?
    [self currentOperationDidFinish:NO error:error];
}

@end


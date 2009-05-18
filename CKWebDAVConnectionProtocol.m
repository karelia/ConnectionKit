//
//  CKWebDAVProtocol.m
//  Marvel
//
//  Created by Mike on 18/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKWebDAVConnectionProtocol.h"

#import "CKConnectionAuthentication.h"
#import "CKConnectionError.h"

#import "CKAbstractConnection.h"    // For KTLog. Remove dependency when possible


@interface CKWebDAVConnectionProtocol ()
- (void)startHTTPRequest:(NSURLRequest *)request;
- (void)currentOperationDidFinish:(BOOL)didFinish error:(NSError *)error;
@end


@implementation CKWebDAVConnectionProtocol

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
    [[self client] connectionProtocol:self didOpenConnectionWithCurrentDirectoryPath:[[[self request] URL] path]];
}

- (void)stopConnection
{
    [_HTTPConnection cancel];
}

- (void)downloadContentsOfFileAtPath:(NSString *)remotePath
{
    _status = CKWebDAVProtocolStatusDownload;
    
    
    // Downloads are just simple GET requests
    NSURL *URL = [[NSURL alloc] initWithString:remotePath relativeToURL:[[self request] URL]];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:URL];
    [URL release];
    
    
    // Start the request
    [self startHTTPRequest:request];
    [request release];
}

- (void)uploadData:(NSData *)data toPath:(NSString *)path
{
    _status = CKWebDAVProtocolStatusUploading;
    
    
    // Send a PUT request with the data
    NSURL *URL = [[NSURL alloc] initWithString:path relativeToURL:[[self request] URL]];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL HTTPMethod:@"PUT"];
    [URL release];
    
    
    // Include MIME type
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                            (CFStringRef)[path pathExtension],
                                                            NULL);
    NSString *MIMEType = [(NSString *)UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType) autorelease];	
    if (!MIMEType || [MIMEType length] == 0)
    {
        // if this list grows, consider using a dictionary of corrected UTI to MIME mappings instead
        if ([(NSString *)UTI isEqualToString:@"public.css"])
        {
            MIMEType = @"text/css";
        }
        else if ([(NSString *)UTI isEqualToString:(NSString *)kUTTypeICO])
        {
            MIMEType = @"image/vnd.microsoft.icon";
        }
        else
        {
            MIMEType = @"application/octet-stream";
        }
    }
    CFRelease(UTI);
    
    [request setValue:MIMEType forHTTPHeaderField:@"Content-Type"];
    
    
    // Include data
    [request setHTTPBody:data];
    
    
    // Send the request
    [self startHTTPRequest:request];
    [request release];
}

- (void)createDirectoryAtPath:(NSString *)path
{
    _status = CKWebDAVProtocolStatusCreatingDirectory;
    
    
    // Send a MKCOL request
    NSURL *URL = [[NSURL alloc] initWithString:path relativeToURL:[[self request] URL]];
    NSURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL HTTPMethod:@"MKCOL"];
    [URL release];
    
    
    // Send the request
    [self startHTTPRequest:request];
    [request release];
}

- (void)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath
{
    _status = CKWebDAVProtocolStatusMovingItem;
    
    
    // Send a MOVE request
    NSURL *fromURL = [[NSURL alloc] initWithString:fromPath relativeToURL:[[self request] URL]];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:fromURL HTTPMethod:@"MOVE"];
    [fromURL release];
    
    
    // The destination is a request header
    NSURL *toURL = [[NSURL alloc] initWithString:toPath relativeToURL:[[self request] URL]];
    [request setValue:[toURL absoluteString] forHTTPHeaderField:@"Destination"];
    [toURL release];
    
    
    // Send the request
    [self startHTTPRequest:request];
    [request release];
}

- (void)deleteItemAtPath:(NSString *)path
{
    _status = CKWebDAVProtocolStatusDeletingItem;
    
    
    // Send a DELETE request
    NSURL *URL = [[NSURL alloc] initWithString:path relativeToURL:[[self request] URL]];
    NSURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL HTTPMethod:@"DELETE"];
    [URL release];
    
    
    // Send the request
    [self startHTTPRequest:request];
    [request release];
}

- (void)stopCurrentOperation
{
    _status = CKWebDAVProtocolStatusIdle;
    [_HTTPConnection cancel];
}

- (void)currentOperationDidFinish:(BOOL)didFinish error:(NSError *)error
{
    _status = CKWebDAVProtocolStatusIdle;
    
    [_HTTPConnection cancel];       // definitely don't want to hear from it any more!
    
    [_HTTPConnection autorelease];  // autorelease otherwise the connection can be deallocated in
    _HTTPConnection = nil;          // the middle of sending a delegate method
    
    if (didFinish)
    {
        [[self client] connectionProtocolDidFinishCurrentOperation:self];
    }
    else
    {
        [[self client] connectionProtocol:self currentOperationDidFailWithError:error];
    }
}

#pragma mark -
#pragma mark HTTP Connection

/*  Creates and schedules an HTTP connection for the request.
 */
- (void)startHTTPRequest:(NSURLRequest *)request
{
    NSAssert(!_HTTPConnection, @"Attempting to start an HTTP request while a response is stored");
    _HTTPConnection = [[CKHTTPConnection alloc] initWithRequest:request delegate:self];
}

- (void)HTTPConnection:(CKHTTPConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [[self client] connectionProtocol:self didReceiveAuthenticationChallenge:challenge];
}

- (void)HTTPConnection:(CKHTTPConnection *)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [[self client] connectionProtocol:self didCancelAuthenticationChallenge:challenge];
}

- (void)HTTPConnection:(CKHTTPConnection *)connection didReceiveResponse:(NSHTTPURLResponse *)response;
{
    // It's quite likely there's an error. Make handling it easy
    BOOL    result = NO;
    NSString *localizedErrorDescription = nil;
    int errorCode = CKConnectionErrorUnknown;
    NSMutableDictionary *errorUserInfo = [NSMutableDictionary dictionary];
    
    
    
    
    
    // Handle the response
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
            switch ([response statusCode])
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
                    errorCode = CKConnectionErrorDataLengthExceedsMaximum;
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
        [errorUserInfo setObject:response forKey:CKConnectionErrorURLResponseErrorKey];
        
        if (!localizedErrorDescription) localizedErrorDescription = LocalizedStringInConnectionKitBundle(@"An unknown error occured", @"Unknown connection error");
        [errorUserInfo setObject:localizedErrorDescription forKey:NSLocalizedDescriptionKey];
        
        error = [NSError errorWithDomain:CKConnectionErrorDomain code:errorCode userInfo:errorUserInfo];
    }
    
    [self currentOperationDidFinish:result error:error];
}

- (void)HTTPConnection:(CKHTTPConnection *)connection didReceiveData:(NSData *)data
{
    [[self client] connectionProtocol:self didDownloadData:data];
}

- (void)HTTPConnectionDidFinishLoading:(CKHTTPConnection *)connection
{
    // If we reach this point, an operation requiring full data to be downloaded has finished
    [self currentOperationDidFinish:YES error:nil];
}

- (void)HTTPConnection:(CKHTTPConnection *)connection didFailWithError:(NSError *)error
{
    // If the HTTP connection failed, the file operation almost certainly did
    // TODO: Should we be coercing the error to CKConnectionErrorDomain?
    [self currentOperationDidFinish:NO error:error];
}

@end


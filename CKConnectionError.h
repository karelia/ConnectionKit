//
//  CKConnectionError.h
//  Connection
//
//  Created by Mike on 22/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//
//  All the errors that ConnectionKit defines for connections/operations to fail with


#import <Foundation/Foundation.h>


extern NSString * const CKConnectionErrorDomain;


/*!
 @enum CKConnection-related Error Codes
 @abstract Constants used by NSError to indicate errors in the CKConnection error domain
 @discussion The majority of these match up to their CKConnectionError equivalents. Otherwise,
 they should be documented here.
 */
enum
{
    CKConnectionErrorUnknown =                          NSURLErrorUnknown,                  // -1       // Should never happen, but if it does the underlying error should provide more detail
    CKConnectionErrorCancelled =                        NSURLErrorCancelled,                // -999
    
    // Communication errors
    CKConnectionErrorBadURL =                           NSURLErrorBadURL,                   // -1000
    CKConnectionErrorTimedOut =                         NSURLErrorTimedOut,
    CKConnectionErrorUnsupportedURL =                   NSURLErrorUnsupportedURL,
    CKConnectionErrorCannotFindHost =                   NSURLErrorCannotFindHost,
    CKConnectionErrorCannotConnectToHost =              NSURLErrorCannotConnectToHost,
    CKConnectionErrorNetworkConnectionLost =            NSURLErrorNetworkConnectionLost,
    CKConnectionErrorDNSLookupFailed =                  NSURLErrorDNSLookupFailed,
    CKConnectionErrorHTTPTooManyRedirects =             NSURLErrorHTTPTooManyRedirects,                 // Do we need this one? Should we instead allow infinite redirects as long as we don't get into a loop?
    CKConnectionErrorResourceUnavailable =              NSURLErrorResourceUnavailable,                  // Do we need this one?
    CKConnectionErrorNotConnectedToInternet =           NSURLErrorNotConnectedToInternet,
    CKConnectionErrorRedirectToNonExistentLocation =    NSURLErrorRedirectToNonExistentLocation,
    CKConnectionErrorBadServerResponse =                NSURLErrorBadServerResponse,                    // Do we need this one?
    CKConnectionErrorUserCancelledAuthentication =      NSURLErrorUserCancelledAuthentication,
    CKConnectionErrorUserAuthenticationRequired =       NSURLErrorUserAuthenticationRequired,
    CKConnectionErrorZeroByteResource =                 NSURLErrorZeroByteResource,                     // Do we need this one?
    
    // Remote file system errors
    CKConnectionErrorFileDoesNotExist =                 NSURLErrorFileDoesNotExist,         // -1100    // e.g. Trying to download a file that does not exist, or uploading into a directory that does not exist
    CKConnectionErrorFileIsDirectory =                  NSURLErrorFileIsDirectory,
    CKConnectionErrorNoPermissionsToReadFile =          NSURLErrorNoPermissionsToReadFile,              // I'm thinking this should be a more general "No permission" as it applies to stuff like creating a directory
    CKConnectionErrorInsufficientStorage =              -1104,                                          // There's no space left on the server
    
    // Secure connection errors
    CKConnectionErrorSecureConnectionFailed =           NSURLErrorSecureConnectionFailed,   // -1200
    CKConnectionErrorServerCertificateHasBadDate =      NSURLErrorServerCertificateHasBadDate,
    CKConnectionErrorServerCertificateUntrusted =       NSURLErrorServerCertificateUntrusted,
    CKConnectionErrorServerCertificateHasUnknownRoot =  NSURLErrorServerCertificateHasUnknownRoot,
    CKConnectionErrorServerCertificateNotYetValid =     NSURLErrorServerCertificateNotYetValid,
	CKConnectionErrorClientCertificateRejected =        NSURLErrorClientCertificateRejected,
    
    //CKConnectionErrorCannotLoadFromNetwork =          NSURLErrorCannotLoadFromNetwork,    // -2000    //Pretty certain we don't need this as it pertains to the cache
    
    // Download and local file I/O errors
    CKConnectionErrorCannotCreateFile =                 NSURLErrorCannotCreateFile,         // -3000
    CKConnectionErrorCannotOpenFile =                   NSURLErrorCannotOpenFile,
    CKConnectionErrorCannotCloseFile =                  NSURLErrorCannotCloseFile,
    CKConnectionErrorCannotWriteToFile =                NSURLErrorCannotWriteToFile,
    CKConnectionErrorCannotRemoveFile =                 NSURLErrorCannotRemoveFile,                     // Do we need this one?
    CKConnectionErrorCannotMoveFile =                   NSURLErrorCannotMoveFile,                       // Do we need this one?
    CKConnectionErrorDownloadDecodingFailedMidStream =  NSURLErrorDownloadDecodingFailedMidStream,      // Do we need this one?
    CKConnectionErrorDownloadDecodingFailedToComplete = NSURLErrorDownloadDecodingFailedToComplete,     // Do we need this one?
};



@interface NSError (ConnectionKit)

+ (NSError *)errorWithHTTPResponse:(CFHTTPMessageRef)response;
- (id)initWithHTTPResponse:(CFHTTPMessageRef)response;

//+ (NSError *)errorWithHTTPURLResponse:(NSHTTPURLResponse *)response;
//- (id)initWithHTTPURLResponse:(NSHTTPURLResponse *)response;
@end


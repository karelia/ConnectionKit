//
//  CKError.h
//  Connection
//
//  Created by Mike on 22/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//
//  All the errors that ConnectionKit defines for connections/operations to fail with


#import <Foundation/Foundation.h>


// Predefined domain for all CKConnection errors
extern NSString *const CKErrorDomain;

/*!
 @const CKErrorURLResponseErrorKey
 @abstract The NSError userInfo dictionary key used to store and retrieve the NSURLResponse that was interpreted as an error.
 */
extern NSString *const CKErrorURLResponseErrorKey;


/*!
 @enum CKConnection-related Error Codes
 @abstract Constants used by NSError to indicate errors in the CKConnection error domain
 @discussion The majority of these match up to their CKError equivalents. Otherwise,
 they should be documented here.
 */
enum
{
    CKErrorUnknown =                          NSURLErrorUnknown,                  // -1       // Should never happen, but if it does the underlying error should provide more detail
    CKErrorCancelled =                        NSURLErrorCancelled,                // -999
    
    // Communication errors
    CKErrorBadURL =                           NSURLErrorBadURL,                   // -1000
    CKErrorTimedOut =                         NSURLErrorTimedOut,
    CKErrorUnsupportedURL =                   NSURLErrorUnsupportedURL,
    CKErrorCannotFindHost =                   NSURLErrorCannotFindHost,
    CKErrorCannotConnectToHost =              NSURLErrorCannotConnectToHost,
    CKErrorNetworkConnectionLost =            NSURLErrorNetworkConnectionLost,
    CKErrorDNSLookupFailed =                  NSURLErrorDNSLookupFailed,
    CKErrorHTTPTooManyRedirects =             NSURLErrorHTTPTooManyRedirects,                 // Do we need this one? Should we instead allow infinite redirects as long as we don't get into a loop?
    CKErrorResourceUnavailable =              NSURLErrorResourceUnavailable,                  // Do we need this one?
    CKErrorNotConnectedToInternet =           NSURLErrorNotConnectedToInternet,
    CKErrorRedirectToNonExistentLocation =    NSURLErrorRedirectToNonExistentLocation,
    CKErrorBadServerResponse =                NSURLErrorBadServerResponse,                    // Do we need this one? Using it at the moment to signify a server isn't WebDAV-compliant. What happens if you try to do an HTTP GET from a non-HTTP server?
    CKErrorUserCancelledAuthentication =      NSURLErrorUserCancelledAuthentication,
    CKErrorUserAuthenticationRequired =       NSURLErrorUserAuthenticationRequired,
    CKErrorZeroByteResource =                 NSURLErrorZeroByteResource,                     // Do we need this one?
    
    // Remote file system errors
    CKErrorFileDoesNotExist =                 NSURLErrorFileDoesNotExist,         // -1100    // e.g. Trying to download a file that does not exist, or uploading into a directory that does not exist
    CKErrorFileIsDirectory =                  NSURLErrorFileIsDirectory,
    CKErrorNoPermissionsToReadFile =          NSURLErrorNoPermissionsToReadFile,              // I'm thinking this should be a more general "No permission" as it applies to stuff like creating a directory
#if MAC_OS_X_VERSION_10_5 <= MAC_OS_X_VERSION_MAX_ALLOWED                                               // There's no space left on the server
    CKErrorDataLengthExceedsMaximum =         NSURLErrorDataLengthExceedsMaximum,             
#else
    CKErrorDataLengthExceedsMaximum =         -1103,
#endif
    
    // Secure connection errors
    CKErrorSecureConnectionFailed =           NSURLErrorSecureConnectionFailed,   // -1200
    CKErrorServerCertificateHasBadDate =      NSURLErrorServerCertificateHasBadDate,
    CKErrorServerCertificateUntrusted =       NSURLErrorServerCertificateUntrusted,
    CKErrorServerCertificateHasUnknownRoot =  NSURLErrorServerCertificateHasUnknownRoot,
    CKErrorServerCertificateNotYetValid =     NSURLErrorServerCertificateNotYetValid,
	CKErrorClientCertificateRejected =        NSURLErrorClientCertificateRejected,
    
    //CKErrorCannotLoadFromNetwork =          NSURLErrorCannotLoadFromNetwork,    // -2000    //Pretty certain we don't need this as it pertains to the cache
    
    // Download and local file I/O errors
    CKErrorCannotCreateFile =                 NSURLErrorCannotCreateFile,         // -3000
    CKErrorCannotOpenFile =                   NSURLErrorCannotOpenFile,
    CKErrorCannotCloseFile =                  NSURLErrorCannotCloseFile,
    CKErrorCannotWriteToFile =                NSURLErrorCannotWriteToFile,
    CKErrorCannotRemoveFile =                 NSURLErrorCannotRemoveFile,                     // Do we need this one?
    CKErrorCannotMoveFile =                   NSURLErrorCannotMoveFile,                       // Do we need this one?
    CKErrorDownloadDecodingFailedMidStream =  NSURLErrorDownloadDecodingFailedMidStream,      // Do we need this one?
    CKErrorDownloadDecodingFailedToComplete = NSURLErrorDownloadDecodingFailedToComplete,     // Do we need this one?
};


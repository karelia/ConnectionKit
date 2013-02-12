//
//  CK2FileManager
//  Connection
//
//  Created by Mike on 08/10/2012.
//
//  Usage:
//  Much like NSFileManager, alloc + init your own instance. Likely you'll want to give it a delegate so can handle authentication challenges. Then just use the instance methods to perform your desired file operations.
//  An opaque object is returned from each "worker" method that represents the file operation being performed. You can hang onto this token and pass it to -cancelOperation:
//

#import <Foundation/Foundation.h>

#import "CKConnectionProtocol.h"


extern NSString * const CK2FileMIMEType;


@protocol CK2FileManagerDelegate;


@interface CK2FileManager : NSObject
{
  @private
    id <CK2FileManagerDelegate> _delegate;
    NSMutableDictionary         *_cachedCredentials;
}

#pragma mark Discovering Directory Contents

// NSFileManager is poorly documented in this regard, but according to 10.6's release notes, an empty array for keys means to include nothing, whereas nil means to include "a standard set" of values. We try to do much the same by handling nil to fill in all reasonable values the connection hands us as part of doing a directory listing. If you want more specifics, supply your own keys array
// In order to supply resource values, have to work around rdar://problem/11069131 by returning a custom NSURL subclass. Can't guarantee therefore that they will work correctly with the CFURL APIs. So far in practice the only incompatibility I've found is CFURLHasDirectoryPath() always returning NO
- (id)contentsOfDirectoryAtURL:(NSURL *)url
    includingPropertiesForKeys:(NSArray *)keys
                       options:(NSDirectoryEnumerationOptions)mask
             completionHandler:(void (^)(NSArray *contents, NSError *error))block;

// More advanced version of directory listing
//  * listing results are delivered as they arrive over the wire, if possible
//  * FIRST result is the directory itself, with relative path resolved if possible
//  * MIGHT do true recursion of the directory tree in future, so include NSDirectoryEnumerationSkipsSubdirectoryDescendants for stable results
//
// All docs for -contentsOfDirectoryAtURL:… should apply here too
- (id)enumerateContentsOfURL:(NSURL *)url
  includingPropertiesForKeys:(NSArray *)keys
                     options:(NSDirectoryEnumerationOptions)mask
                  usingBlock:(void (^)(NSURL *url))block
           completionHandler:(void (^)(NSError *error))completionBlock;

extern NSString * const CK2URLSymbolicLinkDestinationKey; // The destination URL of a symlink


#pragma mark Creating Items

/*  In all these methods, we refer to "opening attributes". They apply *only* if the server supports supplying specific attributes at creation time. In practice at present this should give:
 *
 *  FTP:    opening attributes are ignored
 *  SFTP:   Only NSFilePosixPermissions is used, and some servers choose to ignore it
 *  WebDAV: Only CK2FileMIMEType is supported
 *  file:   The full suite of attributes supported by NSFileManager should be available, but *only* for directories
 *
 *  If you particularly care about setting permissions on a remote server then, a follow up call to -setResourceValues:… is needed.
 */

- (id)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes completionHandler:(void (^)(NSError *error))handler;

- (id)createFileAtURL:(NSURL *)url contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(void (^)(NSUInteger bytesWritten))progressBlock completionHandler:(void (^)(NSError *error))handler;

- (id)createFileAtURL:(NSURL *)destinationURL withContentsOfURL:(NSURL *)sourceURL withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(void (^)(NSUInteger bytesWritten))progressBlock completionHandler:(void (^)(NSError *error))handler;


#pragma mark Deleting Items
// Attempts to remove the file or directory at the specified URL. At present all protocols support deleting files, but when deleting directories:
//
//  file:               Recursively deletes directories if possible
//  Everything else:    Supports files only
- (id)removeItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;


#pragma mark Getting and Setting Attributes
// It is up to the protocol used to decide precisely how it wants to handle the attributes and any errors. In practice at present that should mean:
//
//  FTP:    Only NSFilePosixPermissions is supported, and not by all servers
//  SFTP:   Only NSFilePosixPermissions is supported
//  WebDAV: No attributes are supported
//  file:   Behaves the same as NSFileManager
- (id)setAttributes:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;


#pragma mark Cancelling Operations
// If an operation is cancelled, the completion handler will be called with a NSURLErrorCancelled error.
- (void)cancelOperation:(id)operation;


#pragma mark Delegate
// Delegate methods are delivered on an arbitrary queue/thread. Your code needs to be threadsafe to handle that.
// Changing delegate might mean you still receive messages shortly after the change. Not ideal I know!
@property(assign) id <CK2FileManagerDelegate> delegate;


#pragma mark URLs
// These two methods take into account the specifics of different URL schemes. e.g. for the same relative path, but different base schemes:
//  http://example.com/relative/path
//  ftp://example.com/relative/path
//  sftp://example.com/~/relative/path
//
// Takes care of the file URL bug on 10.6
//
// NOTE: +URLWithPath:relativeToURL: tends to return relative URLs. You may well find it preferable to call -absoluteURL on the result in your app to keep things simple
//
+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;

/*!
 @method         canHandleURL:
 
 @abstract
 Performs a "preflight" operation that performs some speculative checks to see if a URL has a suitable protocol registered to handle it.
 
 @discussion
 The result of this method is valid only as long as no protocols are registered or unregistered, and as long as the request is not mutated (if the request is mutable). Hence, clients should be prepared to handle failures even if they have performed request preflighting by calling this method.
 
 @param
 url     The URL to preflight.
 
 @result
 YES         if it is likely that the given request can be used to
 perform a file operation and the associated I/O can be
 started
 */
+ (BOOL)canHandleURL:(NSURL *)url;

@end


@protocol CK2FileManagerDelegate <NSObject>
// Delegate methods are delivered on an arbitrary queue/thread. Your code needs to be threadsafe to handle that.
@optional

// If left unimplemented, -performDefaultHandlingForAuthenticationChallenge: will be called
- (void)fileManager:(CK2FileManager *)manager didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript;

@end


#pragma mark -


@interface NSURL (ConnectionKit)
- (BOOL)ck2_isFTPURL;   // YES if the scheme is ftp or ftps
@end
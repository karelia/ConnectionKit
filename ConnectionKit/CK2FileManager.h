//
//  CK2FileManager
//  Connection
//
//  Created by Mike on 08/10/2012.
//

#import <Foundation/Foundation.h>


typedef void (^CK2ProgressBlock)(NSUInteger bytesWritten, NSUInteger previousAttemptCount);


extern NSString * const CK2FileMIMEType;


typedef NS_ENUM(NSInteger, CK2DirectoryEnumerationOptions) {
    CK2DirectoryEnumerationIncludesDirectory = 1L << 31,    // see directory methods below for details
};


@protocol CK2FileManagerDelegate;


/**
 ConnectionKit's equivalent of NSFileManager
 All operations are asynchronous, including ones on the local file system.
 Supports remote file servers, currently over FTP, SFTP and WebDAV.
 "Worker" methods return an opaque object which you can pass to -cancelOperation: if needed.
 Allocate and initialise as many file managers as you wish; there is no +defaultManager method
 Provide a file manager with a delegate to handle authentication in the same fashion as NSURLConnection
 Behind the scenes, ConnectionKit takes care of creating as many connections to
 servers as are needed. This means you can perform multiple operations at once,
 but please avoid performing too many at once as that could easily upset a
 server.
*/

@interface CK2FileManager : NSObject
{
  @private
    id <CK2FileManagerDelegate> _delegate;
}

#pragma mark Discovering Directory Contents

/**
 Performs a shallow search of the specified directory and returns URLs for the contained items.
 
 This method performs a shallow search of the directory and therefore does not traverse symbolic links or return the contents of any subdirectories. This method also does not return URLs for the current directory (“.”), parent directory (“..”) but it can return hidden files (files that begin with a period character)
 
 The order of the files in the returned array generally follows that returned by the server, which is likely undefined.
 
 Paths are standardized if possible (i.e. case is corrected if needed, and relative paths resolved).
 
 @param url for the directory whose contents you want to enumerate.
 @param keys to try and include from the server. Pass nil to get a default set. Include NSURLParentDirectoryURLKey to get 
 @param mask of options. In addition to NSDirectoryEnumerationOptions, accepts CK2DirectoryEnumerationIncludesDirectory
 @param block called with URLs, each of which identifies a file, directory, or symbolic link. If the directory contains no entries, the array is empty. If an error occurs, contents is nil and error should be non-nil.
 */
- (id)contentsOfDirectoryAtURL:(NSURL *)url
    includingPropertiesForKeys:(NSArray *)keys
                       options:(NSDirectoryEnumerationOptions)mask
             completionHandler:(void (^)(NSArray *contents, NSError *error))block;

/**
 Block-based enumeration of directory contents
 
 If possible, listing results are delivered as they arrive over the wire. This
 makes it possible that the operation fails mid-way, having received only some
 of the total directory contents.
 
 All docs for -contentsOfDirectoryAtURL:… should apply here too
  
 @param url for the directory whose contents you want to enumerate.
 @param keys to try and include from the server. Pass nil to get a default set. Include NSURLParentDirectoryURLKey to get
 @param mask of options. In addition to NSDirectoryEnumerationOptions, accepts CK2DirectoryEnumerationIncludesDirectory. Not all protocols support deep enumeration at present, so it is recommended you include NSDirectoryEnumerationSkipsSubdirectoryDescendants for now.
 @param block is called for each URL encountered.
 @param completionBlock is called once enumeration finishes or fails. A non-nil error indicates failure.
 */
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

/*  Many servers will overwrite an existing file at the target URL, but not all
 *  I don't believe any servers support overwriting a directory without first removing it
 */

- (id)createFileAtURL:(NSURL *)url contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *error))handler;

// It's at the discretion of individual protocol implementations, but generally file uploads should avoid reading the whole thing into memory at once
- (id)createFileAtURL:(NSURL *)destinationURL withContentsOfURL:(NSURL *)sourceURL withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *error))handler;


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

// To retrieve attributes, instead perform a listing of the *parent* directory, and pick out resource properties from the returned URLs that you're interested in


#pragma mark Cancelling Operations
// If an operation is cancelled, the completion handler will be called with a NSURLErrorCancelled error.
- (void)cancelOperation:(id)operation;


#pragma mark Delegate
// Delegate methods are delivered on an arbitrary queue/thread. Your code needs to be threadsafe to handle that.
// Changing delegate might mean you still receive messages shortly after the change. Not ideal I know!
@property(assign) id <CK2FileManagerDelegate> delegate;


@end


@interface CK2FileManager (URLs)

// These two methods take into account the specifics of different URL schemes. e.g. for the same relative path, but different base schemes:
//  http://example.com/relative/path
//  ftp://example.com/relative/path
//  sftp://example.com/~/relative/path
//
// Takes care of the file URL bug on 10.6
//
// NOTE: +URLWithPath:relativeToURL: tends to return relative URLs. You may well find it preferable to call -absoluteURL on the result in your app to keep things simple
// I'm seriously considering removing +URLWithPath:relativeToURL: as it tends not to be that useful in practice. +URLWithPath:hostURL: does exactly what it says on the tin
//
+ (NSURL *)URLWithPath:(NSString *)path hostURL:(NSURL *)baseURL;
+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;

/**
 Extracts the path component of a URL, accounting for the subtleties of FTP etc.
 
 Normally, paths in URLs are absolute. FTP and SSH-based protocols both have the
 concept of a "home" directory though. i.e. the working directory upon login.
 Thus, their URLs must distinguish between absolute and relative paths
 (the latter are interpreted relative to the home directory). This method makes
 that same distinction to return an absolute or relative path, as interpreted
 by the specific protocol. Some examples:
 
 ftp://example.com/relative      =>  relative
 ftp://example.com//absolute     =>  /absolute
 sftp://example.com/absolute     =>  /absolute
 sftp://example.com/~/relative   =>  relative

 @param URL to extract the path from. 
 @return the URL's path
 */
+ (NSString *)pathOfURL:(NSURL *)URL;

/**
 Equivalent of CFURLSetTemporaryResourcePropertyForKey() that supports non-file URLs
 
 Calls through to Core Foundation for file URLs, but provides its own storage for others
 When first used for a non-file URL, -[NSURL getResourceValue:forKey:error:] is swizzled so the value can be easily retreived by clients later
 This method is primarily used by non-file protocols to populate URLs returned during a directory listing. But it could be helpful to clients for adding in other info
 CRITICAL: keys are tested using POINTER equality for non-file URLs, so you must pass in a CONSTANT
 
 @param value to cache. Retained
 @param key to store under. Any existing value is overwritten
 @param url to cache for
 */
+ (void)setTemporaryResourceValue:(id)value forKey:(NSString *)key inURL:(NSURL *)url __attribute((nonnull(2,3)));

@end


@protocol CK2FileManagerDelegate <NSObject>
// Delegate methods are delivered on an arbitrary queue/thread. Your code needs to be threadsafe to handle that.
@optional

// If left unimplemented, -performDefaultHandlingForAuthenticationChallenge: will be called
- (void)fileManager:(CK2FileManager *)manager didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;


typedef enum {
	CKTranscriptSent,
	CKTranscriptReceived,
	CKTranscriptData,
    CKTranscriptInfo,
} CKTranscriptType;

- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript;

@end

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
 @return An opaque token object representing the operation for passing to `-cancelOperation:` if needed.
 */
- (id)contentsOfDirectoryAtURL:(NSURL *)url
    includingPropertiesForKeys:(NSArray *)keys
                       options:(NSDirectoryEnumerationOptions)mask
             completionHandler:(void (^)(NSArray *contents, NSError *error))block __attribute((nonnull(1,4)));

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
 @return An opaque token object representing the operation for passing to `-cancelOperation:` if needed.
 */
- (id)enumerateContentsOfURL:(NSURL *)url
  includingPropertiesForKeys:(NSArray *)keys
                     options:(NSDirectoryEnumerationOptions)mask
                  usingBlock:(void (^)(NSURL *url))block
           completionHandler:(void (^)(NSError *error))completionBlock __attribute((nonnull(1,4)));

extern NSString * const CK2URLSymbolicLinkDestinationKey; // The destination URL of a symlink


#pragma mark Creating Items

/**
 Creates a directory at the specified URL.
 
 If a file or directory already exists at `url`, it is at the server's discretion
 whether the operation succeeds by replacing the existing item, or fails.
 
 Only some protocols/servers support/respect applying attributes to a directory
 as part of creating it. Indeed, some servers don't really support attributes at
 all! So any attributes you pass here might well go ignored. In practice, at
 present you should see something like this:
 
 - FTP:    Attributes are completely ignored
 - SFTP:   Only `NSFilePosixPermissions` is used; some servers choose to ignore it
 - WebDAV: Attributes are ignored
 - file:   The full suite of attributes supported by `NSFileManager` should be available
 
 If you particularly care about setting attributes on a remote server, then a
 follow-up call to -setAttributes:… is needed.
 
 @param url A URL that specifies the directory to create. This parameter must not be nil.
 @param createIntermediates If YES, this method creates any non-existent parent directories as part of creating the directory in url. If NO, this method fails if any of the intermediate parent directories does not exist.
 @param attributes to apply *only* if the server supports supplying them at creation time. See discussion for more details.
 @param handler Called at the end of the operation. A non-nil error indicates failure.
 @return An opaque token object representing the operation for passing to `-cancelOperation:` if needed. 
 */
- (id)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1)));

/**
 Creates a file with the specified content at the specified URL.
 
 If a file or directory already exists at `url`, it is at the server's discretion
 whether the operation succeeds by replacing the existing item, or fails.
 
 Only some protocols/servers support/respect applying attributes to a file as
 part of creating it. Indeed, some servers don't really support attributes at
 all! So any attributes you pass here might well go ignored. In practice, at
 present you should see something like this:
 
 - FTP:    Attributes are completely ignored
 - SFTP:   Only `NSFilePosixPermissions` is used; some servers choose to ignore it
 - WebDAV: Only `CK2FileMIMEType` is supported
 - file:   Attributes are ignored
 
 If you particularly care about setting attributes on a remote server, then a
 follow-up call to -setAttributes:… is needed.
 
 @param url A URL that specifies the file to create. This parameter must not be nil.
 @param data A data object containing the contents of the new file.
 @param createIntermediates If YES, this method creates any non-existent parent directories as part of creating the file in url. If NO, this method fails if any of the intermediate parent directories does not exist.
 @param attributes to apply *only* if the server supports supplying them at creation time. See discussion for more details.
 @param progressBlock Called as each "chunk" of the file is written. In some cases, uploads have to be restarted from the beginning; the previousAttemptCount argument tells you how many times that has happened so far
 @param handler Called at the end of the operation. A non-nil error indicates failure.
 @return An opaque token object representing the operation for passing to `-cancelOperation:` if needed.
 */
- (id)createFileAtURL:(NSURL *)url contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1,2)));

/**
 Creates a file by copying the content of the specified URL.
 
 If a file or directory already exists at `destinationURL`, it is at the
 server's discretion whether the operation succeeds by replacing the existing
 item, or fails.
 
 Only some protocols/servers support/respect applying attributes to a file as
 part of creating it. Indeed, some servers don't really support attributes at
 all! So any attributes you pass here might well go ignored. In practice, at
 present you should see something like this:
 
 - FTP:    Attributes are completely ignored
 - SFTP:   Only `NSFilePosixPermissions` is used; some servers choose to ignore it
 - WebDAV: Only `CK2FileMIMEType` is supported
 - file:   Attributes are ignored
 
 If you particularly care about setting attributes on a remote server, then a
 follow-up call to -setAttributes:… is needed.
 
 It's up to the individual protocol implementation, but generally ConnectionKit
 will avoid loading the entire source file into memory at once.
 
 @param destinationURL A URL that specifies the file to create. This parameter must not be nil.
 @param sourceURL The file whose contents to use for creating the new file.
 @param createIntermediates If YES, this method creates any non-existent parent directories as part of creating the file in url. If NO, this method fails if any of the intermediate parent directories does not exist.
 @param attributes to apply *only* if the server supports supplying them at creation time. See discussion for more details.
 @param progressBlock Called as each "chunk" of the file is written. In some cases, uploads have to be restarted from the beginning; the previousAttemptCount argument tells you how many times that has happened so far
 @param handler Called at the end of the operation. A non-nil error indicates failure.
 @return An opaque token object representing the operation for passing to `-cancelOperation:` if needed.
 */
- (id)createFileAtURL:(NSURL *)destinationURL withContentsOfURL:(NSURL *)sourceURL withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1,2)));


#pragma mark Deleting Items

/**
 Removes the item at the specified URL.
 
 Right now, deletion of files is fully implemented, but whether deleting a
 directory succeeds is pretty much at the mercy of the server/protocol used.
 
 @param url A file URL specifying the file or directory to remove.
 @param handler Called at the end of the operation. A non-nil error indicates failure.
 @return An opaque token object representing the operation for passing to `-cancelOperation:` if needed.
 */
- (id)removeItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1)));


#pragma mark Getting and Setting Attributes

/**
 Sets the attributes of the specified file or directory.
 
 Unsupported attributes are ignored. Failure is only considered to have occurred
 when an attribute appears to be supported by the server/protocol in use, but
 actually fails to set. In practice at present the supported attributes should
 be:
 
 - FTP:    Only NSFilePosixPermissions is supported, and not by all servers
 - SFTP:   Only NSFilePosixPermissions is supported
 - WebDAV: No attributes are supported
 - file:   Same attributes as NSFileManager supports
 
 @param keyedValues A dictionary containing as keys the attributes to set for path and as values the corresponding value for the attribute.
 @param url The URL of a file or directory.
 @param handler Called at the end of the operation. A non-nil error indicates failure.
 @return An opaque token object representing the operation for passing to `-cancelOperation:` if needed.
 */
- (id)setAttributes:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1,2)));

// To retrieve attributes, instead perform a listing of the *parent* directory, and pick out resource properties from the returned URLs that you're interested in


#pragma mark Cancelling Operations

/**
 Cancels an operation.
 
 If an operation is cancelled before it finishes, its completion handler is
 called with an `NSURLErrorCancelled` error to indicate the failure can be
 ignored.
 
 @param operation An opaque token object representing the operation, as returned by any of `CK2FileManager`'s worker methods.
 */
- (void)cancelOperation:(id)operation __attribute((nonnull(1)));


#pragma mark Delegate

/**
 The file manager's delegate.
 
 Delegate methods are delivered on an arbitrary queue/thread.
 Changing delegate might mean you still receive messages shortly after the change. Not ideal I know!
 */
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
+ (NSURL *)URLWithPath:(NSString *)path hostURL:(NSURL *)baseURL __attribute((nonnull(1,2)));
+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL  __attribute((nonnull(1,2)));

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

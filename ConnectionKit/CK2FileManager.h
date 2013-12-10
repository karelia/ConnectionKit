//
//  CK2FileManager
//  Connection
//
//  Created by Mike on 08/10/2012.
//

#import <Foundation/Foundation.h>


typedef void (^CK2ProgressBlock)(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToSend);


extern NSString * const CK2FileMIMEType;


typedef NS_OPTIONS(NSInteger, CK2DirectoryEnumerationOptions) {
    CK2DirectoryEnumerationIncludesDirectory = 1L << 31,    // see directory methods below for details
};


@protocol CK2FileManagerDelegate;
@class CK2FileOperation;


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
 
 Supported protocols and their URL schemes:
 
 Scheme | Protocol
 ------ | --------
 file   | Local files
 ftp    | FTP
 ftps   | FTP with Implicit SSL
 ftpes  | FTP with TLS/SSL
 http   | WebDAV
 https  | WebDAV over HTTPS
 sftp   | SFTP
 
 Completion handlers (and other blocks) and delegate methods are called by
 CK2FileManager on arbitrary threads/queues. It is your responsibility not to
 block that thread for too long, and to dispatch work over to another thread if
 required.
 
 Note that on OS releases where `-[NSURLConnection setDelegateQueue:]` is
 unavailable, WebDAV operations rely on the main thread running its runloop in
 the default mode.
 
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
 
 Many protocols provide a decent error code indicating *why* the operation
 failed. Unfortunately, FTP cannot. The FTP spec means the only machine-readable
 response is a 550 code. This covers pretty much any sort of filesystem access
 problem (as opposed to an issue with the connection itself). Thus FTP ops
 cannot distinguish between a folder not existing, not actually being a folder,
 and the user having insufficient permissions to access it. Instead you'll get
 back plain old `NSFileReadUnknownError`.
 
 @param url for the directory whose contents you want to enumerate.
 @param keys to try and include from the server. Pass nil to get a default set. Include NSURLParentDirectoryURLKey to get 
 @param mask of options. In addition to NSDirectoryEnumerationOptions, accepts CK2DirectoryEnumerationIncludesDirectory
 @param block called with URLs, each of which identifies a file, directory, or symbolic link. If the directory contains no entries, the array is empty. If an error occurs, contents is nil and error should be non-nil.
 @return The new file operation.
 */
- (CK2FileOperation *)contentsOfDirectoryAtURL:(NSURL *)url
                    includingPropertiesForKeys:(NSArray *)keys
                                       options:(NSUInteger)mask
                             completionHandler:(void (^)(NSArray *contents, NSError *error))block __attribute((nonnull(1,4)));

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
 
 Note: Even though this is a "write" operation, it is still possible to get back
 something like `NSFileReadUnknownError`. In particular, FTP must traverse the
 directory hierarchy which can fail if the target directory turns out not to
 exist, or the user has insufficient permissions to access it.
 
 @param url A URL that specifies the directory to create. This parameter must not be nil.
 @param createIntermediates If YES, this method creates any non-existent parent directories as part of creating the directory in url. If NO, this method fails if any of the intermediate parent directories does not exist.
 @param attributes to apply *only* if the server supports supplying them at creation time. See discussion for more details.
 @param handler Called at the end of the operation. A non-nil error indicates failure.
 @return The new file operation.
 */
- (CK2FileOperation *)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1)));

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
 
 Note: Even though this is a "write" operation, it is still possible to get back
 something like `NSFileReadUnknownError`. In particular, FTP must traverse the
 directory hierarchy which can fail if the target directory turns out not to
 exist, or the user has insufficient permissions to access it.
 
 @param url A URL that specifies the file to create. This parameter must not be nil.
 @param data A data object containing the contents of the new file.
 @param createIntermediates If YES, this method creates any non-existent parent directories as part of creating the file in url. If NO, this method fails if any of the intermediate parent directories does not exist.
 @param attributes to apply *only* if the server supports supplying them at creation time. See discussion for more details.
 @param progressBlock Called as each "chunk" of the file is written. In some cases, uploads have to be restarted from the beginning; the previousAttemptCount argument tells you how many times that has happened so far
 @param handler Called at the end of the operation. A non-nil error indicates failure.
 @return The new file operation.
 */
- (CK2FileOperation *)createFileAtURL:(NSURL *)url contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1,2)));

- (CK2FileOperation *)createFileOperationWithURL:(NSURL *)url
                                        fromData:(NSData *)data
                     withIntermediateDirectories:(BOOL)createIntermediates
                               openingAttributes:(NSDictionary *)attributes
                               completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1,2)));

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
 
 Note: Even though this is a "write" operation, it is still possible to get back
 something like `NSFileReadUnknownError`. In particular, FTP must traverse the
 directory hierarchy which can fail if the target directory turns out not to
 exist, or the user has insufficient permissions to access it.
 
 @param destinationURL A URL that specifies the file to create. This parameter must not be nil.
 @param sourceURL The file whose contents to use for creating the new file.
 @param createIntermediates If YES, this method creates any non-existent parent directories as part of creating the file in url. If NO, this method fails if any of the intermediate parent directories does not exist.
 @param attributes to apply *only* if the server supports supplying them at creation time. See discussion for more details.
 @param progressBlock Called as each "chunk" of the file is written. In some cases, uploads have to be restarted from the beginning; the previousAttemptCount argument tells you how many times that has happened so far
 @param handler Called at the end of the operation. A non-nil error indicates failure.
 @return The new file operation.
 */
- (CK2FileOperation *)createFileAtURL:(NSURL *)destinationURL withContentsOfURL:(NSURL *)sourceURL withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1,2)));

- (CK2FileOperation *)createFileOperationWithURL:(NSURL *)destinationURL
                                        fromFile:(NSURL *)sourceURL
                     withIntermediateDirectories:(BOOL)createIntermediates
                               openingAttributes:(NSDictionary *)attributes
                               completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1,2)));


#pragma mark Deleting Items

/**
 Removes the item at the specified URL.
 
 The handling of files versus directories is heavily at the discretion of the
 protocol implementation at present:
 
 - file:   Like NSFileManager, cheerfully deletes files or directories,
           including contents.
 - WebDAV: Provided the server adheres to the WebDAV spec, has the same
           behaviour as local files.
 - SFTP:   If the URL has `NSURLIsDirectoryKey` set to `YES`, or a trailing
           slash, is treated as a directory. Only empty directories can be
           deleted though, so your code is responsible for making the directory
           (and it's subdirectories) empty first. Otherwise, the URL is treated
           as a file. As far as I am aware, SFTP servers are quite strict on the
           difference between files and directories.
 - FTP:    The same as SFTP except there are definitely plenty of servers in the
           wild which will delete empty directories when asked to delete a *file*
           of that name. Even though this is a "write" operation, it is still
           possible to get back something like `NSFileReadUnknownError`, as FTP
           may require traversing the directory hierarchy which can fail if the
           target directory turns out not to exist, or the user has insufficient
           permissions to access it.
 
 @param url A file URL specifying the file or directory to remove.
 @param handler Called at the end of the operation. A non-nil error indicates failure.
 @return The new file operation.
 */
- (CK2FileOperation *)removeItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1)));

- (CK2FileOperation *)removeOperationWithURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1)));


#pragma mark Moving Items
/**
 Renames the item at the specified URL
 
 @param srcURL The file or directory to rename.
 @param newName The new name for the file. Note that some FTP servers seem to cope poorly with filenames containing a space, truncating at the first space character.
 @param handler Called at the end of the operation. A non-nil error indicates failure.
 @return The new file operation.
 */
- (CK2FileOperation *)renameItemAtURL:(NSURL *)srcURL toFilename:(NSString *)newName completionHandler:(void (^)(NSError *error))handler;


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
 
 Note: Even though this is a "write" operation, it is still possible to get back
 something like `NSFileReadUnknownError`. In particular, FTP must traverse the
 directory hierarchy which can fail if the target directory turns out not to
 exist, or the user has insufficient permissions to access it.
 
 @param keyedValues A dictionary containing as keys the attributes to set for path and as values the corresponding value for the attribute.
 @param url The URL of a file or directory.
 @param handler Called at the end of the operation. A non-nil error indicates failure.
 @return The new file operation.
 */
- (CK2FileOperation *)setAttributes:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler __attribute((nonnull(1,2)));

// To retrieve attributes, instead perform a listing of the *parent* directory, and pick out resource properties from the returned URLs that you're interested in


#pragma mark Delegate

/**
 The file manager's delegate.
 
 Delegate methods are delivered on an arbitrary queue/thread.
 Changing delegate might mean you still receive messages shortly after the change. Not ideal I know!
 */
@property(assign) id <CK2FileManagerDelegate> delegate;


@end


@interface CK2FileManager (URLs)

/**
 Initializes and returns a newly created NSURL object by changing `baseURL` to the specified path.
 
 Some protocols differentiate between absolute paths, and those relative to the
 user's home directory. This method constructs URLs to accomodate that and the
 quirks of different protocols. Here are some example URLs:
 
 Protocol | `/absolute` path              | `relative` path
 -------- | ----------------------------- | -------------------------------
 HTTP     | `http://example.com/absolute` | `http://example.com/relative`
 FTP      | `ftp://example.com//absolute` | `ftp://example.com/relative`
 SSH      | `sftp://example.com/absolute` | `sftp://example.com/~/relative`
 
 There is a subtle bug in 10.6's handling of relative file URLs. This method
 stops it hitting you.
 
 @param path The path that the NSURL object will represent. If path is a relative path, it is treated as being relative to the user's home directory once connected to `baseURL`. Passing nil for this parameter produces an exception.
 @param isDir A Boolean value that specifies whether path is treated as a directory path when resolving against relative path components. Pass YES if the path indicates a directory, NO otherwise.
 @param baseURL A URL providing at least a scheme and host for the result to be based on. Any path as part of this URL is ignored.
 @return An NSURL object initialized with path. `nil` if `baseURL` proved unsuitable.
*/
+ (NSURL *)URLWithPath:(NSString *)path isDirectory:(BOOL)isDir hostURL:(NSURL *)baseURL __attribute((nonnull(1,3)));

// NOTE: +URLWithPath:relativeToURL: tends to return relative URLs. You may well find it preferable to call -absoluteURL on the result in your app to keep things simple
// I'm seriously considering removing this method as it tends not to be that useful in practice. +URLWithPath:isDirectory:hostURL: does exactly what it says on the tin
+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL __attribute((nonnull(1,2)));

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
 @return the URL's path. If the path has a trailing slash it is stripped.
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


/**
 * Disposition options for auth challenge delegate message
 */
typedef NS_ENUM(NSInteger, CK2AuthChallengeDisposition) {
    CK2AuthChallengeUseCredential = 0,                     /* Use the specified credential, which may be `nil` */
    CK2AuthChallengePerformDefaultHandling = 1,            /* Default handling for the challenge - as if this delegate were not implemented; the credential parameter is ignored. */
    CK2AuthChallengeCancelAuthenticationChallenge = 2,     /* The entire request will be canceled; the credential parameter is ignored. */
    CK2AuthChallengeRejectProtectionSpace = 3,             /* This challenge is rejected and the next authentication protection space should be tried;the credential parameter is ignored. */
};


@protocol CK2FileManagerDelegate <NSObject>
@optional

/**
 EXPERIMENTAL
 
 Gives the delegate a chance to customise requests for those protocols which use
 them (currently WebDAV only)
 */
- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation
                                        willSendRequest:(NSURLRequest *)request
                                       redirectResponse:(NSURLResponse *)response
                                      completionHandler:(void (^)(NSURLRequest *))completionHandler;

/**
 The task has received an authentication challenge.
 
 If this delegate is not implemented, the behavior will be the same as using the
 default handling disposition.
 */
- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation
                                    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
                                      completionHandler:(void (^)(CK2AuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler;

/**
 * Sent periodically to notify the delegate of upload progress. This
 * information is also available as properties of the operation.
 */
- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation
                                       didWriteBodyData:(int64_t)bytesSent
                                      totalBytesWritten:(int64_t)totalBytesSent
                              totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToSend;


typedef NS_ENUM(NSUInteger, CK2TranscriptType) {
	CK2TranscriptText,
	CK2TranscriptHeaderIn,
	CK2TranscriptHeaderOut,
};    // deliberately aligned with curl_infotype for convenience

/**
 Reports received transcript info.
 
 @param manager The file manager.
 @param info The received transcript line(s). Should end in a newline character.
 @param transcript The type of transcript received.
 */
- (void)fileManager:(CK2FileManager *)manager appendString:(NSString *)info toTranscript:(CK2TranscriptType)transcript;

/**
 * Sent as the last message related to a specific operation. Error may be
 * `nil`, which implies that no error occurred and this operation is finished.
 */
- (void)fileManager:(CK2FileManager *)manager operation:(CK2FileOperation *)operation
                                   didCompleteWithError:(NSError *)error;

- (void)fileManager:(CK2FileManager *)manager didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge __attribute((deprecated("implement -fileManager:operation:didReceiveChallenge:completionHandler: instead")));

@end


@interface CK2FileManager (Deprecated)

- (void)cancelOperation:(CK2FileOperation *)operation __attribute((nonnull(1), deprecated("Use -[CK2FileOperation cancel] instead")));

@end

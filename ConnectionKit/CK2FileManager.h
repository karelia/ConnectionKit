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


typedef void (^CK2ProgressBlock)(NSUInteger bytesWritten, NSUInteger previousAttemptCount);


extern NSString * const CK2FileMIMEType;



@protocol CK2FileManagerDelegate;


@interface CK2FileManager : NSObject
{
  @private
    id <CK2FileManagerDelegate> _delegate;
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

- (id)createFileAtURL:(NSURL *)url contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes progressBlock:(CK2ProgressBlock)progressBlock completionHandler:(void (^)(NSError *error))handler;

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

/// \param [in] URL to extract the path from. Unlike -path, handles the subtleties of different schemes. Some examples:
/// ftp://example.com/relative      =>  relative
/// ftp://example.com//absolute     =>  /absolute
/// sftp://example.com/absolute     =>  /absolute
/// sftp://example.com/~/relative   =>  relative
/// \returns the path.
+ (NSString *)pathOfURL:(NSURL *)URL;

// CFURLSetTemporaryResourcePropertyForKey() is a very handy function, but currently only supports file URLs
// This method calls through to Core Foundation for file URLs, but provides its own storage for others
// When first used for a non-file URL, -[NSURL getResourceValue:forKey:error:] is swizzled so the value can be easily retreived by clients later
// This method is primarily used by non-file protocols to populate URLs returned during a directory listing. But it could be helpful to clients for adding in other info
// CRITICAL: keys are tested using POINTER equality for non-file URLs, so you must pass in a CONSTANT
/// \param [in] value to cache. Retained
/// \param [in] key to store under. Any existing value is overwritten
/// \param [in] url to cache for
+ (void)setTemporaryResourceValue:(id)value forKey:(NSString *)key inURL:(NSURL *)url;

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

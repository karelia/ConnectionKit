//
//  CK2FileTransferSession.h
//  Connection
//
//  Created by Mike on 08/10/2012.
//
//

#import <Foundation/Foundation.h>

#import "CKConnectionProtocol.h"


@protocol CK2FileTransferSessionDelegate;


@interface CK2FileTransferSession : NSObject <NSURLAuthenticationChallengeSender>
{
@private
    NSURLRequest        *_request;
    
    // Auth
    NSURLCredential     *_credential;
    NSOperationQueue    *_opsAwaitingAuth;
    
    id <CK2FileTransferSessionDelegate> _delegate;
}

#pragma mark Discovering Directory Contents

// NSFileManager is poorly documented in this regard, but according to 10.6's release notes, an empty array for keys means to include nothing, whereas nil means to include "a standard set" of values. We try to do much the same by handling nil to fill in all reasonable values the connection hands us as part of doing a directory listing. If you want more specifics, supply your own keys array
// In order to supply resource values, have to work around rdar://problem/11069131 by returning a custom NSURL subclass. Can't guarantee therefore that they will work correctly with the CFURL APIs. So far in practice the only incompatibility I've found is CFURLHasDirectoryPath() always returning NO
- (void)contentsOfDirectoryAtURL:(NSURL *)url
      includingPropertiesForKeys:(NSArray *)keys
                         options:(NSDirectoryEnumerationOptions)mask
               completionHandler:(void (^)(NSArray *contents, NSError *error))block;

// More advanced version of directory listing
//  * listing results are delivered as they arrive over the wire, if possible
//  * FIRST result is the directory itself, with relative path resolved if possible
//  * MIGHT do true recursion of the directory tree in future, so include NSDirectoryEnumerationSkipsSubdirectoryDescendants for stable results
//
// All docs for -contentsOfDirectoryAtURL:… should apply here too
- (void)enumerateContentsOfURL:(NSURL *)url
    includingPropertiesForKeys:(NSArray *)keys
                       options:(NSDirectoryEnumerationOptions)mask
                    usingBlock:(void (^)(NSURL *url))block
             completionHandler:(void (^)(NSError *error))completionBlock;


#pragma mark Creating and Deleting Items

- (void)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates completionHandler:(void (^)(NSError *error))handler;

// 0 bytesWritten indicates writing has ended. This might be because of a failure; if so, error will be filled in
- (void)createFileAtURL:(NSURL *)url contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;

- (void)createFileAtURL:(NSURL *)destinationURL withContentsOfURL:(NSURL *)sourceURL withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;

- (void)removeFileAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;


#pragma mark Getting and Setting Attributes
// Only NSFilePosixPermissions is recognised at present. Note that some servers don't support this so will return an error (code 500)
// All other attributes are ignored
- (void)setResourceValues:(NSDictionary *)keyedValues ofItemAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler;


#pragma mark Delegate
// Delegate messages are received on arbitrary queues. So changing delegate might mean you still receive message shortly after the change. Not ideal I know!
@property(assign) id <CK2FileTransferSessionDelegate> delegate;


#pragma mark URLs
// These two methods take into account the specifics of different URL schemes. e.g. for the same relative path, but different base schemes:
//  http://example.com/relative/path
//  ftp://example.com/relative/path
//  ssh://example.com/~/relative/path
+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;


@end


@protocol CK2FileTransferSessionDelegate <NSObject>
- (void)fileTransferSession:(CK2FileTransferSession *)session didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)fileTransferSession:(CK2FileTransferSession *)session appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript;
@end


#pragma mark -


@interface NSURL (ConnectionKit)
- (BOOL)ck2_isFTPURL;   // YES if the scheme is ftp or ftps
@end
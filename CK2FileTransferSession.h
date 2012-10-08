//
//  CK2FileTransferSession.h
//  Connection
//
//  Created by Mike on 08/10/2012.
//
//

#import <Foundation/Foundation.h>


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

- (void)contentsOfDirectoryAtURL:(NSURL *)url
      includingPropertiesForKeys:(NSArray *)keys
                         options:(NSDirectoryEnumerationOptions)mask    // none supported just yet
               completionHandler:(void (^)(NSArray *contents, NSURL *dir, NSError *error))block;   // directory URL tries to resolve relative paths

- (void)enumerateContentsOfURL:(NSURL *)url
    includingPropertiesForKeys:(NSArray *)keys
                       options:(NSDirectoryEnumerationOptions)mask  // none supported just yet
                    usingBlock:(void (^)(NSURL *aURL, NSURL *dir))block  // aURL is nil for empty directories. dir tries to resolve relative paths
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
+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;


@end


@protocol CK2FileTransferSessionDelegate <NSObject>
- (void)fileTransferSession:(CK2FileTransferSession *)session didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)fileTransferSession:(CK2FileTransferSession *)session didReceiveDebugInfo:(NSString *)info;
@end

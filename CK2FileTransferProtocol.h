//
//  CK2FileTransferProtocol.h
//  Connection
//
//  Created by Mike on 11/10/2012.
//
//

#import <Foundation/Foundation.h>

#import "CKConnectionProtocol.h"


@protocol CK2FileTransferProtocolClient;


@interface CK2FileTransferProtocol : NSObject

#pragma mark For Subclasses to Implement

// A CK2FileTransferProtocol is guaranteed to only be accessed from one thread at a time. Multiple operations can be in-flight at once, but they're only kicked off serially. Thus, your code should avoid blocking the thread it's called on

+ (BOOL)canHandleURL:(NSURL *)url;

+ (void)startEnumeratingContentsOfURL:(NSURL *)url
           includingPropertiesForKeys:(NSArray *)keys
                              options:(NSDirectoryEnumerationOptions)mask
                               client:(id <CK2FileTransferProtocolClient>)client
                                token:(id)token
                           usingBlock:(void (^)(NSURL *url))block;

+ (void)startCreatingDirectoryAtURL:(NSURL *)url
        withIntermediateDirectories:(BOOL)createIntermediates
                             client:(id <CK2FileTransferProtocolClient>)client
                              token:(id)token;

// The data is supplied as -HTTPBodyData or -HTTPBodyStream on the request
+ (void)startCreatingFileWithRequest:(NSURLRequest *)request
         withIntermediateDirectories:(BOOL)createIntermediates
                              client:(id <CK2FileTransferProtocolClient>)client
                               token:(id)token
                       progressBlock:(void (^)(NSUInteger bytesWritten))progressBlock;

+ (void)startRemovingFileAtURL:(NSURL *)url
                        client:(id <CK2FileTransferProtocolClient>)client
                         token:(id)token;

+ (void)startSettingResourceValues:(NSDictionary *)keyedValues
                       ofItemAtURL:(NSURL *)url
                            client:(id <CK2FileTransferProtocolClient>)client
                             token:(id)token;


#pragma mark For Subclasses to Customize
// Session consults registered protocols to find out which is qualified to handle paths for a specific URL
// Default behaviour is generic path-handling. Override if your protocol has some special requirements. e.g. SFTP indicates home directory with a ~
+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;


#pragma mark Registration

/*!
 @method registerClass:
 @abstract This method registers a protocol class, making it visible
 to several other CK2FileTransferProtocol class methods.
 @discussion When the system begins to perform an operation,
 each protocol class that has been registered is consulted in turn to
 see if it can be initialized with a given request. The first
 protocol handler class to provide a YES answer to
 <tt>+canHandleURL:</tt> "wins" and that protocol
 implementation is used to perform the URL load. There is no
 guarantee that all registered protocol classes will be consulted.
 Hence, it should be noted that registering a class places it first
 on the list of classes that will be consulted in calls to
 <tt>+canHandleURL:</tt>, moving it in front of all classes
 that had been registered previously.
 Throws an exception if protocolClass isn't a subclass of CK2FileTransferProtocol
 @param protocolClass the class to register.
 */
+ (void)registerClass:(Class)protocolClass;

// Completion block is guaranteed to be called on our private serial queue
+ (void)classForURL:(NSURL *)url completionHandler:(void (^)(Class protocolClass))block;

+ (Class)classForURL:(NSURL *)url;    // only suitable for stateless calls to the protocol class

@end


@protocol CK2FileTransferProtocolClient <NSObject>

- (void)fileTransferProtocolDidFinishWithToken:(id)token;
- (void)fileTransferProtocolToken:(id)token didFailWithError:(NSError *)error;

- (void)fileTransferProtocolToken:(id)token didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)fileTransferProtocolToken:(id)token appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript;

@end
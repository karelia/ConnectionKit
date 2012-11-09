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

/*  A CK2FileTransferProtocol is guaranteed to only be accessed from one thread at a time. Multiple operations can be in-flight at once, but they're only kicked off serially. Thus, your code should avoid blocking the thread it's called on
 */

// Generally, subclasses check the URL's scheme to see if they support it
+ (BOOL)canHandleURL:(NSURL *)url;

// Override these methods to get setup ready for performing the operation

- (id)initForEnumeratingDirectoryAtURL:(NSURL *)url
            includingPropertiesForKeys:(NSArray *)keys
                               options:(NSDirectoryEnumerationOptions)mask
                                client:(id <CK2FileTransferProtocolClient>)client;

- (id)initForCreatingDirectoryAtURL:(NSURL *)url
        withIntermediateDirectories:(BOOL)createIntermediates
                             client:(id <CK2FileTransferProtocolClient>)client;


- (id)initForCreatingFileWithRequest:(NSURLRequest *)request    // the data is supplied as -HTTPBodyData or -HTTPBodyStream on the request
         withIntermediateDirectories:(BOOL)createIntermediates
                              client:(id <CK2FileTransferProtocolClient>)client
                       progressBlock:(void (^)(NSUInteger bytesWritten))progressBlock;

- (id)initForRemovingFileAtURL:(NSURL *)url
                        client:(id <CK2FileTransferProtocolClient>)client;

- (id)initForSettingResourceValues:(NSDictionary *)keyedValues
                       ofItemAtURL:(NSURL *)url
                            client:(id <CK2FileTransferProtocolClient>)client;

// Override to kick off the requested operation. You SHOULD avoid blocking the thread this is called on
- (void)start;

// Your cue to stop doing any more work. Once this is called, the client will ignore you should you choose to continue
- (void)stop;


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

@end


@protocol CK2FileTransferProtocolClient <NSObject>

#pragma mark General
- (void)fileTransferProtocolDidFinish:(CK2FileTransferProtocol *)protocol;
- (void)fileTransferProtocol:(CK2FileTransferProtocol *)protocol didFailWithError:(NSError *)error;
- (void)fileTransferProtocol:(CK2FileTransferProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)fileTransferProtocol:(CK2FileTransferProtocol *)protocol appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript;


#pragma mark Operation-Specific
// Only made use of by directory enumeration at present, but hey, maybe something else will in future
// URL should be pre-populated with properties requested by client
- (void)fileTransferProtocol:(CK2FileTransferProtocol *)protocol didDiscoverItemAtURL:(NSURL *)url;


@end
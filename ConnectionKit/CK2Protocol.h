//
//  CK2Protocol
//  Connection
//
//  Created by Mike on 11/10/2012.
//
//

#import <Foundation/Foundation.h>

#import "CK2FileManager.h"


@protocol CK2ProtocolClient;


@interface CK2Protocol : NSObject
{
  @private
    NSURLRequest            *_request;
    id <CK2ProtocolClient>  _client;
}

#pragma mark For Subclasses to Implement

// Generally, subclasses check the URL's scheme to see if they support it
+ (BOOL)canHandleURL:(NSURL *)url;

// Override these methods to get setup ready for performing the operation. The request is used to indicate the URL to operate on, and the timeout to apply

- (id)initForEnumeratingDirectoryWithRequest:(NSURLRequest *)request    // MUST "discover" the directory itself, first
                  includingPropertiesForKeys:(NSArray *)keys
                                     options:(NSDirectoryEnumerationOptions)mask
                                      client:(id <CK2ProtocolClient>)client;

- (id)initForCreatingDirectoryWithRequest:(NSURLRequest *)request
              withIntermediateDirectories:(BOOL)createIntermediates
                        openingAttributes:(NSDictionary *)attributes
                                   client:(id <CK2ProtocolClient>)client;

// The data is supplied as -HTTPBodyData or -HTTPBodyStream on the request
// For streams, ConnectionKit guarantees to provide the HTTP header @"Content-Length" indicating expected size
- (id)initForCreatingFileWithRequest:(NSURLRequest *)request
         withIntermediateDirectories:(BOOL)createIntermediates
                   openingAttributes:(NSDictionary *)attributes
                              client:(id <CK2ProtocolClient>)client
                       progressBlock:(CK2ProgressBlock)progressBlock;

- (id)initForReadingFileWithRequest:(NSURLRequest *)request
                              toURL:(NSURL *)destinationURL
                             client:(id <CK2ProtocolClient>)client
                      progressBlock:(void (^)(NSUInteger bytesRead))progressBlock;

- (id)initForRemovingFileWithRequest:(NSURLRequest *)request
                              client:(id <CK2ProtocolClient>)client;

- (id)initForSettingAttributes:(NSDictionary *)keyedValues
                 ofItemWithRequest:(NSURLRequest *)request
                            client:(id <CK2ProtocolClient>)client;

// Override to kick off the requested operation
- (void)start;

// Your cue to stop doing any more work. Once this is called, the client will ignore you should you choose to continue
// Called on an arbitrary thread, so bounce over to your own queue/thread if needed
- (void)stop;


#pragma mark For Subclasses to Customize
// Session consults registered protocols to find out which is qualified to handle paths for a specific URL
// Default behaviour is generic path-handling. Override if your protocol has some special requirements. e.g. SFTP indicates home directory with a ~
+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;

// Default is whether path is @"". Override to have a stab at the question if your protocol does have an idea of what absolute path is the home directory
+ (BOOL)isHomeDirectoryAtURL:(NSURL *)url;


#pragma mark For Subclasses to Use

// Most subclasses will want to use this to store the request and client upon initialization, but they're not obliged to
- (id)initWithRequest:(NSURLRequest *)request client:(id <CK2ProtocolClient>)client;
@property(nonatomic, readonly, copy) NSURLRequest *request;
@property(nonatomic, readonly, retain) id <CK2ProtocolClient> client;

/**
 Returned to represent general failures to create or write to something, in situations where we can't get a more specific error.
 */

- (NSError*)standardCouldntWriteErrorWithUnderlyingError:(NSError*)error;

/**
 Returned to represent general failures to find or read something, in situations where we can't get a more specific error.
 */

- (NSError*)standardCouldntReadErrorWithUnderlyingError:(NSError*)error;

/**
 Returned to represent a failure that we *know* was caused by the requested item not being found.
 If the protocol can't be that specific, it should use standardCouldntWriteErrorWithUnderlyingError
 or standardCouldntReadErrorWithUnderlyingError instead.
 */

- (NSError*)standardFileNotFoundErrorWithUnderlyingError:(NSError*)error;

/**
 Returned to represent an authentication error, in situations where the protocol can't be more specific.
 */

- (NSError*)standardAuthenticationErrorWithUnderlyingError:(NSError*)error;

#pragma mark Registration

/*!
 @method registerClass:
 @abstract This method registers a protocol class, making it visible
 to several other CK2Protocol class methods.
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
 Throws an exception if protocolClass isn't a subclass of CK2Protocol
 @param protocolClass the class to register.
 */
+ (void)registerClass:(Class)protocolClass;

@end


@protocol CK2ProtocolClient <NSObject>

#pragma mark General
- (void)protocolDidFinish:(CK2Protocol *)protocol;
- (void)protocol:(CK2Protocol *)protocol didFailWithError:(NSError *)error;

/*!
 @method protocoldidReceiveAuthenticationChallenge:
 @abstract Start authentication for the specified request
 @param protocol The protocol object requesting authentication.
 @param challenge The authentication challenge.
 @discussion The protocol client answers the request on the same queue
 as -start was called on. It may add a default credential to the
 challenge it issues to the connection delegate, if the protocol did not
 provide one.
 */
- (void)protocol:(CK2Protocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

- (void)protocol:(CK2Protocol *)protocol appendString:(NSString *)info toTranscript:(CKTranscriptType)transcript;


#pragma mark Operation-Specific

// Only made use of by directory enumeration at present, but hey, maybe something else will in future
// URL should be pre-populated with properties requested by client
- (void)protocol:(CK2Protocol *)protocol didDiscoverItemAtURL:(NSURL *)url;

// Used by protocols initialized with `-initForReadingFileWithRequest:toURL:client:progressBlock:`
// to indicate that the file has successfully beed transfered to the destination URL.
- (void)protocol:(CK2Protocol *)protocol didReadFileAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL;

// Call if reading from a stream needs to be retried. The client will provide you with a fresh, unopened stream to read from
- (NSInputStream *)protocol:(CK2Protocol *)protocol needNewBodyStream:(NSURLRequest *)request;

@end
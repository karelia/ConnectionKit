//
//  CK2FileOperation.h
//  Connection
//
//  Created by Mike on 22/03/2013.
//
//

#import "CK2Protocol.h"


@interface CK2FileOperation : NSObject <CK2ProtocolClient>
{
@public   // HACK so auth trampoline can get at them
    CK2FileManager  *_manager;
    NSURL           *_URL;
    dispatch_queue_t    _queue;
    
@private
    CK2Protocol     *_protocol;
    
    void    (^_completionBlock)(NSError *);
    void    (^_enumerationBlock)(NSURL *);
    NSURL   *_localURL;
    
    BOOL    _cancelled;
}

- (id)initEnumerationOperationWithURL:(NSURL *)url
           includingPropertiesForKeys:(NSArray *)keys
                              options:(NSDirectoryEnumerationOptions)mask
                              manager:(CK2FileManager *)manager
                     enumerationBlock:(void (^)(NSURL *))enumBlock
                      completionBlock:(void (^)(NSError *))block;

- (id)initDirectoryCreationOperationWithURL:(NSURL *)url
                withIntermediateDirectories:(BOOL)createIntermediates
                          openingAttributes:(NSDictionary *)attributes
                                    manager:(CK2FileManager *)manager
                            completionBlock:(void (^)(NSError *))block;

- (id)initFileCreationOperationWithURL:(NSURL *)url
                                  data:(NSData *)data
           withIntermediateDirectories:(BOOL)createIntermediates
                     openingAttributes:(NSDictionary *)attributes
                               manager:(CK2FileManager *)manager
                         progressBlock:(CK2ProgressBlock)progressBlock
                       completionBlock:(void (^)(NSError *))block;

- (id)initFileCreationOperationWithURL:(NSURL *)remoteURL
                                  file:(NSURL *)localURL
           withIntermediateDirectories:(BOOL)createIntermediates
                     openingAttributes:(NSDictionary *)attributes
                               manager:(CK2FileManager *)manager
                         progressBlock:(CK2ProgressBlock)progressBlock
                       completionBlock:(void (^)(NSError *))block;

- (id)initRemovalOperationWithURL:(NSURL *)url
                          manager:(CK2FileManager *)manager
                  completionBlock:(void (^)(NSError *))block;

- (id)initRenameOperationWithSourceURL:(NSURL *)srcURL
                      newName:(NSString *)newName
                             manager:(CK2FileManager *)manager
                     completionBlock:(void (^)(NSError *))block;

- (id)initResourceValueSettingOperationWithURL:(NSURL *)url
                                        values:(NSDictionary *)keyedValues
                                       manager:(CK2FileManager *)manager
                               completionBlock:(void (^)(NSError *))block;

@property(readonly) CK2FileManager *fileManager;    // goes to nil once finished/failed
@property(readonly) NSURL *originalURL;

- (void)cancel;

@end

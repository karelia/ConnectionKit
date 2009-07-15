//
//  CKFileRequest.h
//  ConnectionKit
//
//  Created by Mike on 14/07/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface CKFileRequest : NSObject <NSCopying, NSMutableCopying>
{
  @private
    NSString        *_operationType;
    NSString        *_path;
    
    NSDictionary    *_extensibleProperties;
}

+ (id)requestWithOperationType:(NSString *)type path:(NSString *)path;
- (id)initWithOperationType:(NSString *)type path:(NSString *)path; // designated initializer
- (id)initWithRequest:(CKFileRequest *)request;


@property(nonatomic, copy, readonly) NSString *operationType;
// All requests involve a path of some kind on the server. They are treated acording to the POSIX standard.
@property(nonatomic, copy, readonly) NSString *path;
// Similar to -[NSURL standardizedURL] and -[NSString stringyByStandardizingPath]. Removes extraneous path components and removes all trailing slashes. Mostly provided as a convenience for protocol-implementors.
@property(nonatomic, readonly) NSString *standardizedPath;


// When uploading data, need to supply both the data and its type
@property(nonatomic, copy, readonly) NSData *data;
@property(nonatomic, copy, readonly) NSString *fileType;

@end


#pragma mark -


@interface CKMutableFileRequest : CKFileRequest

@property(nonatomic, copy, readwrite) NSString *operationType;
@property(nonatomic, copy, readwrite) NSString *path;

- (void)setData:(NSData *)data fileType:(NSString *)UTI;

@end
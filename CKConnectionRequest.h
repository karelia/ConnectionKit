//
//  CKConnectionRequest.h
//  Connection
//
//  Created by Mike on 13/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//


//  The equivalent of NSURLRequest when creating a CKConnection.


#import <Foundation/Foundation.h>


extern const NSTimeInterval CKConnectionRequestDefaultTimeoutInterval;  // 60 seconds


@interface CKConnectionRequest : NSObject <NSCopying, NSMutableCopying>
{
@protected
    NSURL           *_URL;
    NSTimeInterval  _timeoutInterval;
    
    NSDictionary *_extensibleProperties;
}

+ (id)requestWithURL:(NSURL *)URL;
+ (id)requestWithURL:(NSURL *)URL timeoutInterval:(NSTimeInterval)timeoutInterval;

- (id)initWithURL:(NSURL *)URL;
- (id)initWithURL:(NSURL *)URL timeoutInterval:(NSTimeInterval)timeoutInterval;

- (NSURL *)URL;
- (NSTimeInterval)timeoutInterval;

@end


@interface CKMutableConnectionRequest : CKConnectionRequest
- (void)setURL:(NSURL *)URL;
- (void)setTimeoutInterval:(NSTimeInterval)seconds;
@end


// Methods below here are intended purely as support for protocol categories.
// Please do NOT call them from normal application code.

@interface CKConnectionRequest (CKURLRequestExtensibility)
- (id)propertyForKey:(NSString *)key;
@end


@interface CKMutableConnectionRequest (CKURLRequestExtensibility)
- (void)setProperty:(id)value forKey:(NSString *)key;
- (void)removePropertyForKey:(NSString *)key;
@end
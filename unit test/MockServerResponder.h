//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MockServer;

@interface MockServerResponder : NSObject

@property (strong, nonatomic, readonly) NSArray* initialResponse;

+ (MockServerResponder*)responderWithResponses:(NSArray*)responses;

- (id)initWithResponses:(NSArray*)responses;

- (NSArray*)responseForRequest:(NSString*)request substitutions:(NSDictionary*)substitutions;

@end

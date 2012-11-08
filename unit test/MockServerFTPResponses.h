//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MockServerFTPResponses : NSObject

+ (NSArray*)initialResponse;
+ (NSArray*)userOkResponse;
+ (NSArray*)passwordOkResponse;
+ (NSArray*)sysReponse;
+ (NSArray*)pwdResponse;
+ (NSArray*)typeResponse;
+ (NSArray*)cwdResponse;
+ (NSArray*)pasvResponse;
+ (NSArray*)sizeResponse;
+ (NSArray*)retrResponse;
+ (NSArray*)listResponse;
+ (NSArray*)commandNotUnderstoodResponse;
+ (NSArray*)standardResponses;

@end

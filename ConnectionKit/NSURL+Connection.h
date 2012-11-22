//
//  NSURL+Connection.h
//  Connection
//
//  Created by Mike on 05/12/2008.
//  Copyright 2008 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSURL (ConnectionKitAdditions)
- (id)initWithScheme:(NSString *)scheme
                host:(NSString *)host
                port:(NSNumber *)port
                user:(NSString *)username
            password:(NSString *)password;
@end

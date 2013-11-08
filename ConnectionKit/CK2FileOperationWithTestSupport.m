//
//  Created by Sam Deane on 27/03/2013.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import "CK2FileOperationWithTestSupport.h"
#import "CK2FileManagerWithTestSupport.h"

@implementation CK2FileOperationWithTestSupport

- (NSURLRequest *)requestWithURL:(NSURL *)url;
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:60.0];
    CK2FileManagerWithTestSupport* manager = [self valueForKey:@"_manager"];
    if (manager.dontShareConnections)
    {
        [request ck2_setMulti:manager.multi];
    }

    return request;
}

@end

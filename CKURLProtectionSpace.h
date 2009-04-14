//
//  CKURLProtectionSpace.h
//  Connection
//
//  Created by Mike on 18/12/2008.
//  Copyright 2008 Karelia Software. All rights reserved.
//

//  For reasons I cannot fathom, NSURLProtectionSpace will try to change the
//  protocol information from "ftp" to "ftps"
//  You can use this subclass to ensure the protocol is properly respected so
//  that fetching credentials from NSURLCredentialStorage works.


#import <Foundation/Foundation.h>


@interface CKURLProtectionSpace : NSURLProtectionSpace
{
    NSString    *_protocol;
}
@end

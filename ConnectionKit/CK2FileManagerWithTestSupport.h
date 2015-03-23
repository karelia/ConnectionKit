//
//  Created by Sam Deane on 27/03/2013.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import "CK2FileManager.h"

@class CURLTransferStack;

/**
 CK2FileManager with some additional API for test purposes.
 */

@interface CK2FileManagerWithTestSupport : CK2FileManager
{
    BOOL _dontShareConnections;
    CURLTransferStack* _multi;
}

/**
 An alternative CURLMultiHandle to use instead of the default one.
 This is generated on demand, if dontShareConnections is set.
 */

@property (strong, readonly, nonatomic) CURLTransferStack* multi;

/**
 Set this property to force CURL based protocols use an alternative CURLTransfer instead of the default one
 */

@property (assign, nonatomic) BOOL dontShareConnections;

@end

@interface NSURLRequest(CK2FileManagerDebugging)
- (CURLTransferStack*)ck2_multi;
@end

@interface NSMutableURLRequest(CK2FileManagerDebugging)
- (void)ck2_setMulti:(CURLTransferStack*)multi;
@end


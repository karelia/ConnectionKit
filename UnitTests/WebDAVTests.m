//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "CK2FileManagerGenericTests.h"

@interface WebDAVTests : CK2FileManagerGenericTests

@end

@implementation WebDAVTests

- (id)initWithInvocation:(NSInvocation *)anInvocation
{
    if ((self = [super initWithInvocation:anInvocation]) != nil)
    {
        self.responsesToUse = @"webdav";
    }

    return self;
}

@end
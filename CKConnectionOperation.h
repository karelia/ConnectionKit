//
//  CKConnectionOperation.h
//  Marvel
//
//  Created by Mike on 19/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface CKConnectionOperation : NSObject
{
    id              _identifier;
    NSInvocation    *_invocation;
}

- (id)initWithIdentifier:(id)identifier invocation:(NSInvocation *)invocation;
- (id)identifier;
- (NSInvocation *)invocation;
@end

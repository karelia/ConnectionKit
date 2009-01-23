//
//  CKConnectionOperation.m
//  Marvel
//
//  Created by Mike on 19/01/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "CKConnectionOperation.h"


@implementation CKConnectionOperation

- (id)initWithIdentifier:(id)identifier invocation:(NSInvocation *)invocation
{
    [super init];
    
    _identifier = [identifier retain];
    
    _invocation = [invocation retain];
    [_invocation retainArguments];
    
    return self;
}

- (void)dealloc
{
    [_identifier release];
    [_invocation release];
    
    [super dealloc];
}

- (id)identifier { return _identifier; }

- (NSInvocation *)invocation { return _invocation; }

@end

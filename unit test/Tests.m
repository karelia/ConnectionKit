//
//  Tests.m
//  Tests
//
//  Created by Sam Deane on 08/03/2012.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "Tests.h"
#import "CKConnectionRegistry.h"

@implementation Tests

- (void)setUp
{
    [super setUp];
    
    // Set-up code here.
}

- (void)tearDown
{
    // Tear-down code here.
    
    [super tearDown];
}

- (void)testExample
{
    NSString* path = [[CKConnectionRegistry sharedConnectionRegistry] pathOfURLRelativeToHomeDirectory:[[self uploadRequest] URL]];

    STFail(@"Unit tests are not implemented yet in Tests");
}

@end

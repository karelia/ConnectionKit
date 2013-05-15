//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "BaseCKProtocolTests.h"

@interface FileTests : BaseCKProtocolTests

@end

@implementation FileTests

- (NSString*)protocol
{
    return @"File";
}

- (BOOL)setupFromSettings
{
    // for the file tests, we always want to use a URL to a temporary folder
    self.url = [self temporaryFolder];

    return YES;
}

@end
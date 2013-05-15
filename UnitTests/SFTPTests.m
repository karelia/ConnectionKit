//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "BaseCKProtocolTests.h"

@interface SFTPTests : BaseCKProtocolTests

@end

@implementation SFTPTests

- (NSString*)protocol
{
    return @"SFTP";
}

- (BOOL)protocolUsesAuthentication
{
    return YES;
}

@end
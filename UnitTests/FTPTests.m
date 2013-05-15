//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "BaseCKProtocolTests.h"

@interface FTPTests : BaseCKProtocolTests

@end

@implementation FTPTests

- (NSString*)protocol
{
    return @"FTP";
}

- (BOOL)protocolUsesAuthentication
{
    return YES;
}

- (NSData*)mockServerDirectoryListingData
{
    NSString* listing = [NSString stringWithFormat:
                         @"total 1\r\n-rw-------   1 user  staff     3 Mar  6  2012 %@\r\n-rw-------   1 user  staff     3 Mar  6  2012 %@\r\n\r\n",
                         [[self URLForTestFile1] lastPathComponent],
                         [[self URLForTestFile2] lastPathComponent]
                         ];
    
    return [listing dataUsingEncoding:NSUTF8StringEncoding];
}

@end
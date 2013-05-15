//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "BaseCKProtocolTests.h"

@interface WebDAVTests : BaseCKProtocolTests

@end

@implementation WebDAVTests

- (NSString*)protocol
{
    return @"WebDAV";
}

- (BOOL)protocolUsesAuthentication
{
    return YES;
}

- (NSData*)mockServerDirectoryListingData
{
    NSString* xml = [NSString stringWithFormat:
                     @"<D:multistatus xmlns:D=\"DAV:\" xmlns:ns0=\"DAV:\">"

                     "<D:response xmlns:lp1=\"DAV:\">"
                     "<D:href>%@</D:href>"
                     "<D:propstat>"
                     "<D:prop>"
                     "<lp1:resourcetype><D:collection/></lp1:resourcetype>"
                     "</D:prop>"
                     "<D:status>HTTP/1.1 200 OK</D:status>"
                     "</D:propstat>"
                     "</D:response>"

                     "<D:response xmlns:lp1=\"DAV:\">"
                     "<D:href>%@</D:href>"
                     "<D:propstat>"
                     "<D:prop>"
                     "<lp1:resourcetype/>"
                     "</D:prop>"
                     "<D:status>HTTP/1.1 200 OK</D:status>"
                     "</D:propstat>"
                     "</D:response>"

                     "<D:response xmlns:lp1=\"DAV:\">"
                     "<D:href>%@</D:href>"
                     "<D:propstat>"
                     "<D:prop>"
                     "<lp1:resourcetype/>"
                     "</D:prop>"
                     "<D:status>HTTP/1.1 200 OK</D:status>"
                     "</D:propstat>"
                     "</D:response>"

                     "</D:multistatus>\r\n", [self URLForTestFolder], [self URLForTestFile1], [self URLForTestFile2]];

    NSData* data = [xml dataUsingEncoding:NSUTF8StringEncoding];
    
    return data;
}

@end